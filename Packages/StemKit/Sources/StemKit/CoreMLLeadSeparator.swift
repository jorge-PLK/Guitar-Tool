import Foundation

/// Separador de la guitarra solista con el Mel-Band RoFormer «Lead_Rhythm_Guitar» en Core ML
/// (mini-spec Fase 4, «Opciones de guitarras y tramos de solo»; contrato en `MaskModelContract.leadRhythm` y
/// ModelCatalog.leadRhythmMelRoformer).
///
/// Corre en el proceso que lo llama (la app), no en `tf-separate`: solo ve tramos de solo (decenas de segundos,
/// nunca el tema entero), el trozo es de 3 s y la memoria medida es pequeña frente al límite del helper.
///
/// El modelo se carga en la primera llamada a `separateLead` (que el compositor hace fuera del hilo principal) y se
/// libera con la instancia: lo normal es crear uno por composición. Las llamadas se serializan.
public final class CoreMLLeadSeparator: LeadGuitarSeparating, @unchecked Sendable {
    private let lock = NSLock()
    private let loader: () throws -> MaskModel
    private var processor: ChunkProcessor?   // protegido por `lock`

    /// `compiledModelURL`: el `.mlmodelc` que instala ModelStore para `ModelCatalog.leadRhythmMelRoformer`.
    /// No carga nada todavía; si el modelo no se puede cargar, lo dirá `separateLead`.
    public convenience init(compiledModelURL: URL) {
        self.init(compiledModelURL: compiledModelURL, contract: .leadRhythm)
    }

    /// `contract`: `.leadRhythmMSST` para medir paridad con la referencia de MSST (num_overlap 1).
    convenience init(compiledModelURL: URL, contract: MaskModelContract) {
        self.init { try CoreMLMaskModel(compiledModelURL: compiledModelURL, contract: contract) }
    }

    init(loader: @escaping () throws -> MaskModel) {
        self.loader = loader
    }

    /// Solista del tramo, misma frecuencia y longitud que la entrada. A 48 kHz se remuestrea a 44,1 kHz y vuelta.
    public func separateLead(left: [Float], right: [Float], sampleRate: Double) throws -> (left: [Float], right: [Float]) {
        guard left.count == right.count, !left.isEmpty else {
            throw SeparationError.invalidInput("tramo estéreo vacío o con canales de distinta longitud")
        }
        guard sampleRate > 0 else { throw SeparationError.invalidInput("frecuencia \(sampleRate) Hz no válida") }
        lock.lock()
        defer { lock.unlock() }
        let processor = try loadedProcessor()
        let n = left.count
        let input = StereoAudio(left: left, right: right, sampleRate: sampleRate)
        let native = RoformerContract.sampleRate
        let atModelRate = sampleRate == native ? input : try AudioIO.resample(input, to: native)
        let lead = try Self.demix(atModelRate, processor: processor)
        if sampleRate == native { return (lead.left, lead.right) }
        var back = try AudioIO.resample(lead, to: sampleRate)
        for k in [0, 1] {
            var ch = k == 0 ? back.left : back.right
            if ch.count > n { ch.removeLast(ch.count - n) }
            if ch.count < n { ch.append(contentsOf: repeatElement(0, count: n - ch.count)) }
            if k == 0 { back.left = ch } else { back.right = ch }
        }
        return (back.left, back.right)
    }

    private func loadedProcessor() throws -> ChunkProcessor {
        if let processor { return processor }
        let model = try loader()
        precondition(model.contract.stemCount == 1, "CoreMLLeadSeparator: el modelo de solista tiene 1 stem")
        let p = ChunkProcessor(model: model)
        processor = p
        return p
    }

    /// `demix` de MSST con el plan del contrato (trozo 132 300, num_overlap 2: paso de 66 150, relleno reflect de un
    /// paso por lado si el tramo mide más de 3 s, último trozo con reflect o ceros, fundido de trozo/10) sobre audio a
    /// 44,1 kHz. Devuelve el stem 0 (la solista).
    static func demix(_ audio: StereoAudio, processor: ChunkProcessor) throws -> StereoAudio {
        let n = audio.frameCount
        let chunk = processor.chunk
        let plan = ChunkPlan(inputLength: n, chunk: chunk, overlaps: processor.model.contract.overlaps)
        let L = plan.paddedLength
        let source = (0..<2).map { _ in UnsafeMutablePointer<Float>.allocate(capacity: L) }
        let result = (0..<2).map { _ in UnsafeMutablePointer<Float>.allocate(capacity: n) }
        let parts = (0..<2).map { _ in UnsafeMutablePointer<Float>.allocate(capacity: chunk) }
        let outs = (0..<2).map { _ in UnsafeMutablePointer<Float>.allocate(capacity: chunk) }
        defer { (source + result + parts + outs).forEach { $0.deallocate() } }
        for (c, samples) in [audio.left, audio.right].enumerated() {
            samples.withUnsafeBufferPointer { p in
                if plan.padded {
                    reflectPad(p.baseAddress!, count: n, left: plan.border, right: plan.border, into: source[c])
                } else {
                    source[c].initialize(from: p.baseAddress!, count: n)
                }
            }
            result[c].initialize(repeating: 0, count: n)
        }
        let assembler = OverlapAddAssembler(plan: plan, channelCount: 2) { start, ch, count in
            for c in 0..<2 { (result[c] + start).update(from: ch[c], count: count) }
        }
        let srcPtrs = source.map { UnsafePointer($0) }
        let partPtrs = parts.map { UnsafePointer($0) }
        let outPtrs = outs.map { UnsafePointer($0) }
        for k in 0..<plan.count {
            if Task.isCancelled { throw SeparationError.cancelled }
            plan.fill(k, from: srcPtrs, into: parts)
            try processor.process(input: partPtrs, outputs: outs)
            try assembler.add(outPtrs)
        }
        precondition(assembler.emitted == n, "OLA: \(assembler.emitted) ≠ \(n)")
        return StereoAudio(left: Array(UnsafeBufferPointer(start: result[0], count: n)),
                           right: Array(UnsafeBufferPointer(start: result[1], count: n)),
                           sampleRate: audio.sampleRate)
    }
}
