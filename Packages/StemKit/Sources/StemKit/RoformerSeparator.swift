import Foundation

/// Motor de separación en 6 stems (en proceso). La app no lo usa directamente: lo ejecuta
/// `tf-separate` en un proceso aparte, vigilado por `SeparationRunner`.
public final class RoformerSeparator {
    private let processor: ChunkProcessor

    /// Carga el `.mlmodelc` compilado con `.cpuAndGPU` (ADR-004) y comprueba el contrato de entrada.
    /// En Windows lanza `PlatformError.unsupported("paso 7: onnx-runtime")`.
    public convenience init(compiledModelURL: URL) throws {
        self.init(model: try SystemMaskModel.load(modelURL: compiledModelURL, contract: .bsRoformerSW))
    }

    /// Separador con un modelo simulado (máscara 1 + 0i en todos los stems). Para tests de integración
    /// del helper sin el modelo real. `frames` < 1151 acorta el trozo.
    @_spi(Simulation)
    public convenience init(simulatedFrames frames: Int = 1151, delayPerChunk: TimeInterval = 0) {
        self.init(model: ConstantMaskModel(frames: frames, delay: delayPerChunk))
    }

    init(model: MaskModel) {
        precondition(model.contract.stemCount == RoformerContract.stemCount, "RoformerSeparator: modelo de 6 stems")
        processor = ChunkProcessor(model: model)
    }

    /// Separa `input` (WAV estéreo float32 a 44,1 o 48 kHz) y escribe `<stem>.wav` en `outputDirectory`,
    /// a la frecuencia de la entrada y con su misma longitud en muestras.
    /// - Parameters:
    ///   - progress: `(trozos hechos, trozos totales)`; empieza en `(0, n)` y acaba en `(n, n)`.
    ///   - cancel: se consulta antes de cada trozo; si devuelve `true` se lanza `SeparationError.cancelled`
    ///     y no queda ningún fichero a medias.
    public func separate(input: URL, outputDirectory: URL,
                         progress: (_ completed: Int, _ total: Int) -> Void = { _, _ in },
                         cancel: () -> Bool = { false }) throws {
        let source = try AudioIO.readStereo(input)
        let inputRate = source.sampleRate
        let inputLength = source.frameCount
        let fm = FileManager.default
        try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let work = outputDirectory.appendingPathComponent(".tf-separate-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        // El modelo trabaja siempre a 44,1 kHz.
        let audio = inputRate == RoformerContract.sampleRate
            ? source : try AudioIO.resample(source, to: RoformerContract.sampleRate)
        let modelRateFiles = try separateAtModelRate(audio, into: work, progress: progress, cancel: cancel)

        var finals: [(URL, Stem)] = []
        if inputRate == RoformerContract.sampleRate {
            finals = zip(modelRateFiles, Stem.allCases).map { ($0, $1) }
        } else {
            for (file, stem) in zip(modelRateFiles, Stem.allCases) {
                if cancel() { throw SeparationError.cancelled }
                let dst = work.appendingPathComponent("\(stem.rawValue).out.wav")
                try AudioIO.resampleFile(file, to: dst, targetRate: inputRate, exactLength: inputLength)
                try fm.removeItem(at: file)
                finals.append((dst, stem))
            }
        }
        if cancel() { throw SeparationError.cancelled }
        for (file, stem) in finals {
            let dst = outputDirectory.appendingPathComponent(stem.fileName)
            if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
            try fm.moveItem(at: file, to: dst)
        }
    }

    /// Trocea, procesa y escribe los 6 stems a 44,1 kHz en streaming. Devuelve los ficheros en orden de `Stem`.
    private func separateAtModelRate(_ audio: StereoAudio, into dir: URL,
                                     progress: (Int, Int) -> Void, cancel: () -> Bool) throws -> [URL] {
        let chunk = processor.chunk
        let plan = ChunkPlan(inputLength: audio.frameCount, chunk: chunk)
        let L = plan.paddedLength

        // Señal rellenada con reflect (el audio de entrada sí puede estar entero en memoria).
        let source = (0..<2).map { _ in UnsafeMutablePointer<Float>.allocate(capacity: L) }
        defer { source.forEach { $0.deallocate() } }
        for (c, samples) in [audio.left, audio.right].enumerated() {
            samples.withUnsafeBufferPointer { p in
                if plan.padded {
                    reflectPad(p.baseAddress!, count: p.count, left: plan.border, right: plan.border, into: source[c])
                } else {
                    source[c].initialize(from: p.baseAddress!, count: p.count)
                }
            }
        }

        let urls = Stem.allCases.map { dir.appendingPathComponent($0.fileName) }
        let writers = try urls.map { try AudioIO.StereoWriter(url: $0, sampleRate: RoformerContract.sampleRate) }
        defer { writers.forEach { $0.close() } }
        let assembler = OverlapAddAssembler(plan: plan, channelCount: 2 * RoformerContract.stemCount) { _, ch, n in
            for (s, w) in writers.enumerated() {
                try w.write(left: ch[2 * s], right: ch[2 * s + 1], count: n)
            }
        }

        let parts = (0..<2).map { _ in UnsafeMutablePointer<Float>.allocate(capacity: chunk) }
        let outs = (0..<(2 * RoformerContract.stemCount)).map { _ in
            UnsafeMutablePointer<Float>.allocate(capacity: chunk)
        }
        defer { (parts + outs).forEach { $0.deallocate() } }
        let srcPtrs = source.map { UnsafePointer($0) }
        let partPtrs = parts.map { UnsafePointer($0) }
        let outPtrs = outs.map { UnsafePointer($0) }

        progress(0, plan.count)
        for k in 0..<plan.count {
            if cancel() { throw SeparationError.cancelled }
            plan.fill(k, from: srcPtrs, into: parts)
            try processor.process(input: partPtrs, outputs: outs)
            try assembler.add(outPtrs)
            progress(k + 1, plan.count)
        }
        precondition(assembler.emitted == audio.frameCount, "OLA: \(assembler.emitted) ≠ \(audio.frameCount)")
        return urls
    }
}
