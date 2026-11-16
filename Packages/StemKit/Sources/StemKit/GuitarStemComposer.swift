import Accelerate
import AVFoundation
import Foundation

/// Tramo de solo marcado a mano, en segundos desde el inicio de `stems/guitar.wav`
/// (mini-spec Fase 4, «Opciones de guitarras y tramos de solo»). Store tiene su tipo espejo; la app traduce.
public struct GuitarSoloSpan: Sendable, Codable, Equatable {
    public var start: Double
    public var end: Double

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }

    /// Recorta al tema `[0, duration]`, descarta los vacíos o no finitos, ordena y une los que se solapan o tocan.
    public static func normalized(_ spans: [GuitarSoloSpan], duration: Double) -> [GuitarSoloSpan] {
        let clipped = spans.compactMap { s -> GuitarSoloSpan? in
            guard s.start.isFinite, s.end.isFinite else { return nil }
            let a = max(0, s.start), b = min(duration, s.end)
            return b > a ? GuitarSoloSpan(start: a, end: b) : nil
        }.sorted { $0.start < $1.start }
        var merged: [GuitarSoloSpan] = []
        for s in clipped {
            if let last = merged.last, s.start <= last.end {
                merged[merged.count - 1].end = max(last.end, s.end)
            } else {
                merged.append(s)
            }
        }
        return merged
    }
}

/// Modelo de solista frente a rítmica (mini-spec Fase 4: Mel-Band RoFormer «Lead_Rhythm_Guitar»).
/// Recibe un tramo estéreo de la pista de guitarras (el tramo de solo más un margen, nunca el tema entero) y
/// devuelve la estimación de la solista con la misma forma: dos canales de `left.count` muestras.
/// La rítmica no se pide: es entrada − solista.
public protocol LeadGuitarSeparating: Sendable {
    func separateLead(left: [Float], right: [Float], sampleRate: Double) throws -> (left: [Float], right: [Float])
}

/// Papel de una pista de guitarra producida; `rawValue` igual que el `GuitarRole` de Store.
public enum GuitarStemRole: String, Sendable, Codable, CaseIterable {
    case rhythm, left, right, lead

    /// Nombre del WAV en `stems/` (mini-spec Fase 4, «Opciones de guitarras y tramos de solo»).
    public var fileName: String {
        switch self {
        case .rhythm: "guitar_rhythm.wav"
        case .left: "guitar_L.wav"
        case .right: "guitar_R.wav"
        case .lead: "guitar_lead.wav"
        }
    }
}

/// Pista de guitarra escrita en disco (WAV float32 estéreo, misma frecuencia y longitud que la entrada).
public struct GuitarStemTrack: Sendable, Equatable {
    public var role: GuitarStemRole
    public var url: URL
}

/// Compone las pistas de guitarra de una canción a partir de `stems/guitar.wav`
/// (mini-spec Fase 4, «Opciones de guitarras y tramos de solo»).
///
/// - Sin tramos y sin estéreo: ninguna pista (la app usa `guitar.wav`).
/// - Sin tramos, estéreo: L = (canal izquierdo, 0) y R = (0, canal derecho), copia exacta.
/// - Tramos, mono: rítmica + solista. Tramos, estéreo: L + R + solista.
///
/// Solista = `g(t) · separador(tramo)`, con `g` = 1 dentro de cada tramo, fundido de coseno alzado de
/// `fadeSeconds` por fuera de cada borde y 0 exacto fuera. Rítmica = entrada − solista (en estéreo, cada canal a su
/// pista). Así las pistas siempre suman la entrada, y fuera de los tramos la solista es 0 y la rítmica (o L y R) la
/// entrada exacta. El separador solo ve cada tramo con `fadeSeconds + contextSeconds` a cada lado; ventanas que se
/// solapan se le pasan juntas en una sola llamada. Lo demás se copia por bloques sin cargar el tema.
public struct GuitarStemComposer: Sendable {
    /// Fundido en los bordes de cada tramo (mini-spec Fase 4: «Fundidos de 100 ms en los bordes»).
    public static let fadeSeconds = 0.1
    /// Contexto extra para el modelo a cada lado del fundido. No lo fija la spec: elección de implementación, para que
    /// el modelo no vea el borde de su entrada justo donde empieza el fundido.
    public static let defaultContextSeconds = 1.0
    /// Pistas que este compositor gestiona en el directorio de salida (las que no tocan se borran), más la
    /// `guitar_C.wav` de la separación por panorama, que ya no existe como concepto.
    public static let managedFileNames: [String] = GuitarStemRole.allCases.map(\.fileName) + [GuitarSide.center.fileName]

    public var contextSeconds: Double
    /// Muestras por bloque al copiar la parte sin tramos.
    var blockFrames = 1 << 16

    public init(contextSeconds: Double = GuitarStemComposer.defaultContextSeconds) {
        self.contextSeconds = contextSeconds
    }

    /// Escribe en `outputDirectory` las pistas que tocan, borra las de guitarra que ya no correspondan y devuelve las
    /// producidas en el orden de `GuitarStemRole.allCases`. `progress` recibe la fracción hecha, de 0 a 1.
    /// Hay que pasar `separator` si algún tramo cae dentro del tema.
    public func compose(input: URL, outputDirectory: URL, stereo: Bool, soloSpans: [GuitarSoloSpan],
                        separator: (any LeadGuitarSeparating)?,
                        progress: ((Double) -> Void)? = nil) throws -> [GuitarStemTrack] {
        precondition(blockFrames > 0 && contextSeconds >= 0, "GuitarStemComposer: parámetros no válidos")
        let fm = FileManager.default
        let managed = Self.managedFileNames.map { outputDirectory.appendingPathComponent($0) }
        if managed.contains(where: { $0.standardizedFileURL == input.standardizedFileURL }) {
            throw SeparationError.invalidInput("la entrada no puede ser una pista de guitarra de salida")
        }
        try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        if !stereo && soloSpans.isEmpty {
            try removeObsolete(keeping: [], in: outputDirectory)
            progress?(1)
            return []
        }

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: input, commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            throw SeparationError.invalidInput("no se puede leer \(input.lastPathComponent): \(error.localizedDescription)")
        }
        let fmt = file.processingFormat
        guard fmt.channelCount == 2 else {
            throw SeparationError.invalidInput("se esperaba audio estéreo y tiene \(fmt.channelCount) canales")
        }
        let n = Int(file.length)
        guard n > 0 else { throw SeparationError.invalidInput("el audio está vacío") }
        let rate = fmt.sampleRate

        let windows = Self.plan(spans: soloSpans, sampleRate: rate, frameCount: n,
                                fadeFrames: Self.frames(Self.fadeSeconds, rate),
                                contextFrames: Self.frames(contextSeconds, rate))
        let roles: [GuitarStemRole] = (stereo ? [.left, .right] : [.rhythm]) + (windows.isEmpty ? [] : [.lead])
        if roles == [.rhythm] {
            // Todos los tramos caían fuera del tema: sin tramos no hay solista, y la rítmica sería guitar.wav.
            try removeObsolete(keeping: [], in: outputDirectory)
            progress?(1)
            return []
        }
        guard windows.isEmpty || separator != nil else {
            throw SeparationError.invalidInput("hay tramos de solo y no hay separador de solista")
        }

        let partials = roles.map { outputDirectory.appendingPathComponent(".partial-\($0.fileName)") }
        var finished = false
        defer {
            if !finished { for u in partials { try? fm.removeItem(at: u) } }
        }
        var writers: [GuitarStemRole: AudioIO.StereoWriter] = [:]
        for (role, url) in zip(roles, partials) {
            writers[role] = try AudioIO.StereoWriter(url: url, sampleRate: rate)
        }
        let sink = TrackSink(writers: writers, blockFrames: blockFrames)
        defer { writers.values.forEach { $0.close() } }

        let reader = BlockReader(file: file, format: fmt)
        var pos = 0
        func report() { progress?(Double(pos) / Double(n)) }
        for w in windows {
            try copyPlain(pos..<w.range.lowerBound, reader: reader, sink: sink) { pos = $0; report() }
            try Self.checkCancelled()
            let x = try reader.read(w.range)
            let lead = try separator!.separateLead(left: x.left, right: x.right, sampleRate: rate)
            guard lead.left.count == w.range.count, lead.right.count == w.range.count else {
                throw SeparationError.invalidInput(
                    "el separador devolvió \(lead.left.count)/\(lead.right.count) muestras para \(w.range.count)")
            }
            let g = w.gate()
            var gl = [Float](repeating: 0, count: g.count), gr = gl
            vDSP_vmul(g, 1, lead.left, 1, &gl, 1, vDSP_Length(g.count))
            vDSP_vmul(g, 1, lead.right, 1, &gr, 1, vDSP_Length(g.count))
            // Donde g = 0 la solista es 0 exacto aunque el separador dé otra cosa (o NaN).
            for k in 0..<g.count where g[k] == 0 {
                gl[k] = 0
                gr[k] = 0
            }
            try sink.emit(left: x.left, right: x.right, leadLeft: gl, leadRight: gr)
            pos = w.range.upperBound
            report()
        }
        try copyPlain(pos..<n, reader: reader, sink: sink) { pos = $0; report() }
        writers.values.forEach { $0.close() }

        var tracks: [GuitarStemTrack] = []
        for (role, partial) in zip(roles, partials) {
            let final = outputDirectory.appendingPathComponent(role.fileName)
            if fm.fileExists(atPath: final.path) { try fm.removeItem(at: final) }
            try fm.moveItem(at: partial, to: final)
            tracks.append(GuitarStemTrack(role: role, url: final))
        }
        finished = true
        try removeObsolete(keeping: Set(roles.map(\.fileName)), in: outputDirectory)
        return tracks
    }

    // MARK: - Plan de ventanas

    /// Ventana que se pasa al separador: rango de muestras y tramos (en muestras, `[s, e)`) que caen dentro.
    struct LeadWindow: Equatable {
        var range: Range<Int>
        var spans: [Range<Int>]
        var fadeFrames: Int

        /// Ganancia de la solista en cada muestra de la ventana: 1 dentro de un tramo y, a `d` muestras del tramo más
        /// cercano, `0,5 + 0,5·cos(π·d/fade)`; 0 exacto desde `d = fade`.
        func gate() -> [Float] {
            var g = [Float](repeating: 0, count: range.count)
            let lo = range.lowerBound
            for s in spans {
                for k in s { g[k - lo] = 1 }
                for d in 1..<max(1, fadeFrames) {
                    let v = GuitarStemComposer.fadeGain(distance: d, fadeFrames: fadeFrames)
                    let before = s.lowerBound - d, after = s.upperBound - 1 + d
                    if range.contains(before) { g[before - lo] = max(g[before - lo], v) }
                    if range.contains(after) { g[after - lo] = max(g[after - lo], v) }
                }
            }
            return g
        }
    }

    static func fadeGain(distance d: Int, fadeFrames: Int) -> Float {
        if d <= 0 { return 1 }
        if d >= fadeFrames { return 0 }
        return Float(0.5 + 0.5 * cos(Double.pi * Double(d) / Double(fadeFrames)))
    }

    static func frames(_ seconds: Double, _ rate: Double) -> Int { Int((seconds * rate).rounded()) }

    /// Tramos normalizados → ventanas `[s − fade − contexto, e + fade + contexto)` recortadas al tema; las que se solapan
    /// se unen en una.
    static func plan(spans: [GuitarSoloSpan], sampleRate rate: Double, frameCount n: Int, fadeFrames: Int,
                     contextFrames: Int) -> [LeadWindow] {
        var out: [LeadWindow] = []
        for span in GuitarSoloSpan.normalized(spans, duration: Double(n) / rate) {
            let s = min(n, frames(span.start, rate)), e = min(n, frames(span.end, rate))
            guard e > s else { continue }
            let pad = fadeFrames + contextFrames
            let w = max(0, s - pad)..<min(n, e + pad)
            if let last = out.last, w.lowerBound < last.range.upperBound {
                out[out.count - 1].range = last.range.lowerBound..<max(last.range.upperBound, w.upperBound)
                out[out.count - 1].spans.append(s..<e)
            } else {
                out.append(LeadWindow(range: w, spans: [s..<e], fadeFrames: fadeFrames))
            }
        }
        return out
    }

    // MARK: - Disco

    private func copyPlain(_ range: Range<Int>, reader: BlockReader, sink: TrackSink,
                           advanced: (Int) -> Void) throws {
        var p = range.lowerBound
        while p < range.upperBound {
            try Self.checkCancelled()
            let q = min(range.upperBound, p + blockFrames)
            let x = try reader.read(p..<q)
            try sink.emit(left: x.left, right: x.right, leadLeft: nil, leadRight: nil)
            p = q
            advanced(p)
        }
    }

    private func removeObsolete(keeping keep: Set<String>, in dir: URL) throws {
        let fm = FileManager.default
        for name in Self.managedFileNames where !keep.contains(name) {
            let u = dir.appendingPathComponent(name)
            if fm.fileExists(atPath: u.path) { try fm.removeItem(at: u) }
        }
    }

    private static func checkCancelled() throws {
        if Task.isCancelled { throw SeparationError.cancelled }
    }
}

/// Lectura de rangos contiguos de un `AVAudioFile` estéreo.
private struct BlockReader {
    let file: AVAudioFile
    let format: AVAudioFormat

    func read(_ range: Range<Int>) throws -> (left: [Float], right: [Float]) {
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(range.count)) else {
            throw SeparationError.invalidInput("no hay memoria para \(range.count) muestras")
        }
        file.framePosition = AVAudioFramePosition(range.lowerBound)
        try file.read(into: buf, frameCount: AVAudioFrameCount(range.count))
        guard Int(buf.frameLength) == range.count else {
            throw SeparationError.invalidInput("lectura corta: \(buf.frameLength) de \(range.count) muestras")
        }
        let ch = buf.floatChannelData!
        return (Array(UnsafeBufferPointer(start: ch[0], count: range.count)),
                Array(UnsafeBufferPointer(start: ch[1], count: range.count)))
    }
}

/// Reparte entrada y solista entre las pistas: rítmica = entrada − solista; L = (rítmica izq., 0), R = (0, rítmica der.).
private struct TrackSink {
    let writers: [GuitarStemRole: AudioIO.StereoWriter]
    let zeros: [Float]

    init(writers: [GuitarStemRole: AudioIO.StereoWriter], blockFrames: Int) {
        self.writers = writers
        zeros = [Float](repeating: 0, count: blockFrames)
    }

    /// `leadLeft == nil`: sin solista en este rango (rítmica = entrada exacta, solista = 0).
    func emit(left: [Float], right: [Float], leadLeft: [Float]?, leadRight: [Float]?) throws {
        let count = left.count
        var rl = left, rr = right
        if let leadLeft, let leadRight {
            // vDSP_vsub(B, A) = A − B.
            vDSP_vsub(leadLeft, 1, left, 1, &rl, 1, vDSP_Length(count))
            vDSP_vsub(leadRight, 1, right, 1, &rr, 1, vDSP_Length(count))
        }
        var done = 0
        while done < count {
            let m = min(zeros.count, count - done)
            try zeros.withUnsafeBufferPointer { z in
                let z0 = z.baseAddress!
                try rl.withUnsafeBufferPointer { l in
                    try rr.withUnsafeBufferPointer { r in
                        let l0 = l.baseAddress! + done, r0 = r.baseAddress! + done
                        try writers[.rhythm]?.write(left: l0, right: r0, count: m)
                        try writers[.left]?.write(left: l0, right: z0, count: m)
                        try writers[.right]?.write(left: z0, right: r0, count: m)
                    }
                }
                if let w = writers[.lead] {
                    if let leadLeft, let leadRight {
                        try leadLeft.withUnsafeBufferPointer { a in
                            try leadRight.withUnsafeBufferPointer { b in
                                try w.write(left: a.baseAddress! + done, right: b.baseAddress! + done, count: m)
                            }
                        }
                    } else {
                        try w.write(left: z0, right: z0, count: m)
                    }
                }
            }
            done += m
        }
    }
}
