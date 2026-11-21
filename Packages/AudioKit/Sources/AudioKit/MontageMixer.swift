#if canImport(AVFoundation)
import AVFoundation
#else
import NativeAudioFile
#endif
import Foundation

// Mezcla fuera de línea del montaje (mini-spec Fase 7, «Exportación»). AudioKit no depende de Store ni de
// VideoKit: la app traduce el proyecto a `MontageMixJob`.

/// Tramo `[start, end]` en segundos del tiempo del tema.
public struct MontageSpan: Sendable, Equatable {
    public var start: Double
    public var end: Double

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }
}

/// A qué WAV por pista va una pista: el backing (lo que suena del tema sin tomas) o una parte.
public enum MontageGroup: Hashable, Sendable {
    case backing
    case part(String)
}

/// Cuándo suena una pista, en tiempo del tema.
public enum MontagePresence: Sendable, Equatable {
    /// Suena siempre.
    case always
    /// Solo suena dentro de los tramos, con fundido de entrada y de salida en cada borde.
    case audible([MontageSpan])
    /// Suena siempre salvo dentro de los tramos (guitarra original sustituida): el complemento de `audible`,
    /// con el mismo fundido a la inversa.
    case silenced([MontageSpan])
}

public struct MontageTrack: Sendable, Equatable {
    public var id: String
    public var url: URL
    /// Posición de la muestra 0 del fichero en el tiempo del tema (s); puede ser negativa o posterior al inicio del tramo.
    public var songStart: Double
    public var gainDB: Double
    public var group: MontageGroup
    public var presence: MontagePresence

    public init(id: String, url: URL, songStart: Double = 0, gainDB: Double = 0, group: MontageGroup,
                presence: MontagePresence = .always) {
        self.id = id
        self.url = url
        self.songStart = songStart
        self.gainDB = gainDB
        self.group = group
        self.presence = presence
    }
}

/// Tramo del tema `[start, end]` con sus fundidos globales: `fadeIn` si no empieza en el 0 del tema,
/// `fadeOut` si no acaba en el final del tema (lo decide quien arma el trabajo).
public struct MontageSegment: Sendable, Equatable {
    public var start: Double
    public var end: Double
    public var fadeIn: Bool
    public var fadeOut: Bool

    public init(start: Double, end: Double, fadeIn: Bool = true, fadeOut: Bool = true) {
        self.start = start
        self.end = end
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
    }
}

public enum MontageNormalization: Sendable, Equatable {
    case none
    /// Lleva la mezcla a `lufs` integrados sin que el pico real pase de `peakCeilingDB`.
    /// - `limiter: true`: la ganancia llega al objetivo y un limitador de pico con anticipación sujeta el pico;
    ///   como limitar baja algo la sonoridad, la ganancia de entrada se compensa (hasta 3 pasadas).
    /// - `limiter: false`: si el pico pasaría del tope, se frena la ganancia (`limitedByPeak`) y queda por debajo del objetivo.
    case target(lufs: Double, peakCeilingDB: Double, limiter: Bool = true)

    /// −14 LUFS y −1 dBTP con limitador (RF9, mini-spec Fase 7).
    public static let standard = MontageNormalization.target(lufs: MontageMixer.targetLUFS,
                                                             peakCeilingDB: MontageMixer.peakCeilingDB, limiter: true)
    /// −14 LUFS y −1 dBTP frenando la ganancia, sin limitador.
    public static let standardWithoutLimiter = MontageNormalization.target(
        lufs: MontageMixer.targetLUFS, peakCeilingDB: MontageMixer.peakCeilingDB, limiter: false)
}

public struct MontageMixJob: Sendable {
    /// Tramo del tema que se mezcla; todos los ficheros de salida duran `end - start`.
    /// Tramos del tema que se mezclan; la salida es su concatenación (todos los ficheros duran la suma).
    public var segments: [MontageSegment]
    /// Primer inicio y último final (el tramo entero si hay uno solo).
    public var start: Double { segments.first?.start ?? 0 }
    public var end: Double { segments.last?.end ?? 0 }
    /// 44100 o 48000.
    public var sampleRate: Double
    public var tracks: [MontageTrack]
    /// Duración (s) del fundido de entrada y de salida (un compás); `nil` = sin fundido. Se aplica a los
    /// segmentos con `fadeIn`/`fadeOut` activos (los booleanos por tramo deciden dónde, también en los cortes
    /// interiores); cada fundido se acorta a la mitad del tramo si este es más corto.
    public var fadeIn: Double?
    public var fadeOut: Double?
    public var normalization: MontageNormalization
    /// Dónde se escribe la mezcla normalizada (`mezcla.wav`).
    public var mixURL: URL
    /// Si no es `nil`, carpeta donde se escriben `backing.wav` y `<parte>.wav` (sin normalizar, con los
    /// fundidos globales). Se crea si hace falta.
    public var trackDirectory: URL?

    /// Un solo tramo, con los dos fundidos globales.
    public init(start: Double, end: Double, sampleRate: Double, tracks: [MontageTrack], fadeIn: Double? = nil,
                fadeOut: Double? = nil, normalization: MontageNormalization = .standard, mixURL: URL,
                trackDirectory: URL? = nil) {
        self.init(segments: [MontageSegment(start: start, end: end)], sampleRate: sampleRate, tracks: tracks,
                  fadeIn: fadeIn, fadeOut: fadeOut, normalization: normalization, mixURL: mixURL,
                  trackDirectory: trackDirectory)
    }

    /// Varios tramos (ordenados y sin solape), concatenados en la salida.
    public init(segments: [MontageSegment], sampleRate: Double, tracks: [MontageTrack], fadeIn: Double? = nil,
                fadeOut: Double? = nil, normalization: MontageNormalization = .standard, mixURL: URL,
                trackDirectory: URL? = nil) {
        self.segments = segments
        self.sampleRate = sampleRate
        self.tracks = tracks
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
        self.normalization = normalization
        self.mixURL = mixURL
        self.trackDirectory = trackDirectory
    }
}

public struct MontageMixResult: Sendable, Equatable {
    public struct TrackFile: Sendable, Equatable {
        public var group: MontageGroup
        public var url: URL
    }

    public struct ClippedFile: Sendable, Equatable {
        public var url: URL
        public var samples: Int
    }

    public var mixURL: URL
    /// `backing.wav` y uno por parte, en el orden de aparición de los grupos.
    public var trackFiles: [TrackFile]
    /// Sonoridad integrada de la mezcla antes de normalizar (`nil` si es silencio).
    public var measuredLUFS: Double?
    /// Pico real antes de normalizar (dBTP; `-infinity` si es silencio).
    public var measuredTruePeakDB: Double
    /// Ganancia aplicada solo a `mezcla.wav`.
    public var gainDB: Double
    /// Sonoridad y pico real de `mezcla.wav` (la ganancia es lineal, así que son los medidos más `gainDB`).
    public var finalLUFS: Double?
    public var finalTruePeakDB: Double
    /// El tope de pico recortó la ganancia: `finalLUFS` queda por debajo del objetivo.
    public var limitedByPeak: Bool
    /// El limitador de pico actuó sobre `mezcla.wav` (solo con `limiter: true`).
    public var limiterApplied: Bool = false
    /// Reducción máxima de ganancia del limitador en dB (0 si no actuó).
    public var limiterMaxReductionDB: Double = 0
    /// Con limitador, la última pasada no cumplió -1 dBTP o la tolerancia de sonoridad: `finalLUFS`/`finalTruePeakDB`
    /// dicen dónde quedó realmente.
    public var limiterOutOfTolerance: Bool = false
    /// Ficheros con muestras recortadas al pasar a 24 bits (la mezcla sin normalizar, `backing.wav`, partes).
    public var clippedFiles: [ClippedFile] = []
    public var frames: Int
    public var sampleRate: Double
    public var duration: Double { Double(frames) / sampleRate }
}

public enum MontageMixError: Error, Equatable {
    case invalidRange
    case unsupportedSampleRate(Double)
    case unreadable(URL)
}

public enum MontageMixer {
    /// Fundido en los bordes de la presencia de una pista (mini-spec Fase 7, «Transiciones», audio).
    public static let presenceFadeSeconds = 0.08
    /// Objetivo de sonoridad integrada (mini-spec Fase 7, «Exportación»; RF9).
    public static let targetLUFS = -14.0
    /// Tope del pico real tras la ganancia (mini-spec Fase 7, «Exportación»).
    public static let peakCeilingDB = -1.0
    /// Profundidad de los WAV de salida (mini-spec Fase 7, «Exportación»).
    public static let outputBitDepth = 24
    static let blockFrames = 32_768
    /// Pasadas máximas del limitador y tolerancia de sonoridad con la que se da por buena (ampliación de la Fase 7).
    static let limiterMaxPasses = 3
    static let limiterToleranceLU = 0.05
    /// Margen inicial del umbral del limitador. El limitador ya detecta el pico real con el interpolador de
    /// `LoudnessMeter`; el margen solo cubre lo que varía la ganancia dentro de la ventana del interpolador y el
    /// redondeo a 24 bits. Si aun así se pasa, las pasadas lo ajustan con el pico real medido.
    static let limiterMarginDB = -0.05
    /// Pendiente mínima (LU por dB de ganancia) que se admite en la corrección de sonoridad entre pasadas.
    static let limiterMinSlope = 0.2
    /// Holgura para el códec del vídeo, aparte del margen del interpolador: con limitador, `mezcla.wav` se deja en
    /// `peakCeilingDB - codecHeadroomDB` (−1,3 dBTP). El AAC del `.mov` (que no se cambia) sube el pico real
    /// respecto al WAV, y cuánto depende del contenido: en la puerta de VideoKit +0,04 dB con el WAV a −1,05 y
    /// +0,33 dB con el WAV a −1,35; en exportaciones de la app con huecos cortados, +0,1 dB (−1,0 → −0,9 dBTP,
    /// ffmpeg `ebur128=peak=true`, 17/11/2026). El tope de −1 dBTP de la mini-spec Fase 7 («Exportación») se exige
    /// en el `.mov` entregado. Vale para los dos modos: sin limitador, la ganancia se frena en este mismo techo.
    static let codecHeadroomDB = 0.3
    static let reservedNames: Set<String> = ["backing", "mezcla"]

    /// Mezcla y escribe los ficheros. Corre en el hilo que lo llame (con puntos de cesión): usar `Task.detached`
    /// o similar desde la interfaz. Cancelar la tarea borra lo escrito.
    public static func mix(_ job: MontageMixJob, progress: @Sendable (Double) -> Void = { _ in }) async throws -> MontageMixResult {
        guard !job.segments.isEmpty, job.segments.allSatisfy({ $0.end > $0.start }),
              zip(job.segments, job.segments.dropFirst()).allSatisfy({ $0.end <= $1.start }) else {
            throw MontageMixError.invalidRange
        }
        guard AudioImporter.supportedSampleRates.contains(job.sampleRate) else {
            throw MontageMixError.unsupportedSampleRate(job.sampleRate)
        }
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("tf-montage-\(UUID().uuidString)")
        var created: [URL] = []
        var createdDirectory: URL?
        defer { try? fm.removeItem(at: scratch) }
        try fm.createDirectory(at: job.mixURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            // Fuentes a la frecuencia de salida.
            var sources: [URL] = []
            for track in job.tracks {
                let rate: Double
                do { rate = try AudioSamples.sampleRate(of: track.url) } catch { throw MontageMixError.unreadable(track.url) }
                if rate == job.sampleRate {
                    sources.append(track.url)
                } else {
                    try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
                    let converted = scratch.appendingPathComponent("\(sources.count).wav")
                    try await AudioImporter().resample(track.url, to: converted, sampleRate: job.sampleRate)
                    sources.append(converted)
                }
                try Task.checkCancellation()
            }
            var renderer = try Renderer(job: job, sources: sources)

            // Salidas por grupo.
            var groups: [MontageGroup] = []
            for t in job.tracks where !groups.contains(t.group) { groups.append(t.group) }
            if job.trackDirectory != nil, !groups.contains(.backing) { groups.insert(.backing, at: 0) }
            var groupWriters: [MontageGroup: PCM24Writer] = [:]
            var trackFiles: [MontageMixResult.TrackFile] = []
            if let dir = job.trackDirectory {
                if !fm.fileExists(atPath: dir.path) {
                    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                    createdDirectory = dir
                }
                var used = reservedNames
                for g in groups {
                    let name: String
                    switch g {
                    case .backing: name = "backing"
                    case .part(let p): name = uniqueName(sanitized(p), used: &used)
                    }
                    let url = dir.appendingPathComponent("\(name).wav")
                    created.append(url)
                    groupWriters[g] = try makeWriter(url, sampleRate: job.sampleRate)
                    trackFiles.append(.init(group: g, url: url))
                }
            }

            let normalizes: Bool
            if case .target = job.normalization { normalizes = true } else { normalizes = false }
            // Pase 1: mide la mezcla y escribe las pistas (y la mezcla si no hay normalización).
            var meter = LoudnessMeter(sampleRate: job.sampleRate, channels: 2)
            var mixWriter: PCM24Writer?
            if !normalizes {
                created.append(job.mixURL)
                mixWriter = try makeWriter(job.mixURL, sampleRate: job.sampleRate)
            }
            var usesLimiter = false
            if case .target(_, _, true) = job.normalization { usesLimiter = true }
            // Con limitador, la mezcla sin normalizar se guarda (Float32 entrelazado) para las pasadas.
            let scratchURL = scratch.appendingPathComponent("mix.f32")
            var scratchHandle: FileHandle?
            if usesLimiter {
                try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
                fm.createFile(atPath: scratchURL.path, contents: nil)
                scratchHandle = try FileHandle(forWritingTo: scratchURL)
            }
            let share = normalizes ? 0.5 : 1.0
            try await renderer.render(progress: { progress($0 * share) }) { block in
                meter.process(block.mix)
                if let scratchHandle {
                    let n = block.mix[0].count
                    var data = Data(count: n * 8)
                    data.withUnsafeMutableBytes { raw in
                        let p = raw.bindMemory(to: Float.self)
                        for i in 0..<n { p[2 * i] = block.mix[0][i]; p[2 * i + 1] = block.mix[1][i] }
                    }
                    try scratchHandle.write(contentsOf: data)
                }
                if let mixWriter { try write(block.mix, to: mixWriter, sampleRate: job.sampleRate) }
                for (g, w) in groupWriters { try write(block.groups[g] ?? block.silence, to: w, sampleRate: job.sampleRate) }
            }
            for w in groupWriters.values { try w.finish() }
            try mixWriter?.finish()
            var clipped: [MontageMixResult.ClippedFile] = []
            for f in trackFiles { if let n = groupWriters[f.group]?.clippedSamples, n > 0 { clipped.append(.init(url: f.url, samples: n)) } }
            if let n = mixWriter?.clippedSamples, n > 0 { clipped.append(.init(url: job.mixURL, samples: n)) }
            groupWriters = [:]
            mixWriter = nil

            try scratchHandle?.close()
            let report = meter.report
            var gainDB = 0.0
            var limited = false
            var finalLUFS = report.integratedLUFS
            var finalPeak = report.truePeakDB
            var limiterReduction = 0.0
            var limiterUsed = false
            var outOfTolerance = false
            if case .target(let lufs, let deliveredCeiling, true) = job.normalization {
                // Techo efectivo de `mezcla.wav`: el tope del vídeo entregado menos la holgura del códec. El pico y
                // `limiterOutOfTolerance` se comprueban contra este techo.
                let ceiling = deliveredCeiling - codecHeadroomDB
                created.append(job.mixURL)
                let outcome = try limiterNormalize(scratchURL, frames: renderer.totalFrames, sampleRate: job.sampleRate,
                                                   report: report, lufs: lufs, ceiling: ceiling, mixURL: job.mixURL,
                                                   progress: progress)
                let last = outcome.last
                gainDB = outcome.gainDB
                outOfTolerance = outcome.outOfTolerance
                if outcome.clippedSamples > 0 { clipped.append(.init(url: job.mixURL, samples: outcome.clippedSamples)) }
                finalLUFS = last.lufs
                finalPeak = last.truePeakDB
                limiterReduction = last.reductionDB
                limiterUsed = last.reductionDB > 1e-6
            } else if case .target(let lufs, let deliveredCeiling, false) = job.normalization, let measured = report.integratedLUFS {
                // Mismo techo efectivo que con limitador (holgura del códec; Jorge, 17/11/2026).
                let ceiling = deliveredCeiling - codecHeadroomDB
                gainDB = lufs - measured
                if report.truePeakDB.isFinite, ceiling - report.truePeakDB < gainDB {
                    gainDB = ceiling - report.truePeakDB
                    limited = true
                }
                finalLUFS = measured + gainDB
                finalPeak = report.truePeakDB + gainDB
            }
            // Pase 2 sin limitador: la mezcla con la ganancia.
            if normalizes && !usesLimiter {
                created.append(job.mixURL)
                let writer = try makeWriter(job.mixURL, sampleRate: job.sampleRate)
                let gain = Float(pow(10, gainDB / 20))
                try await renderer.render(progress: { progress(0.5 + $0 * 0.5) }) { block in
                    var scaled = block.mix
                    for c in 0..<scaled.count { for i in 0..<scaled[c].count { scaled[c][i] *= gain } }
                    try write(scaled, to: writer, sampleRate: job.sampleRate)
                }
                try writer.finish()
                if writer.clippedSamples > 0 { clipped.append(.init(url: job.mixURL, samples: writer.clippedSamples)) }
            }
            progress(1)
            var result = MontageMixResult(
                mixURL: job.mixURL, trackFiles: trackFiles,
                measuredLUFS: report.integratedLUFS, measuredTruePeakDB: report.truePeakDB, gainDB: gainDB,
                finalLUFS: finalLUFS, finalTruePeakDB: finalPeak,
                limitedByPeak: limited, frames: renderer.totalFrames, sampleRate: job.sampleRate)
            result.limiterApplied = limiterUsed
            result.limiterMaxReductionDB = limiterReduction
            result.limiterOutOfTolerance = outOfTolerance
            result.clippedFiles = clipped
            return result
        } catch {
            for url in created { try? fm.removeItem(at: url) }
            if let createdDirectory { try? fm.removeItem(at: createdDirectory) }
            throw error
        }
    }

    // MARK: Limitador

    struct LimiterPass {
        var lufs: Double?
        var truePeakDB: Double
        var reductionDB: Double
    }

    struct LimiterOutcome {
        /// Medida de la última pasada (la que queda en `mezcla.wav`).
        var last: LimiterPass
        var gainDB: Double
        var thresholdDB: Double
        var passes: Int
        var outOfTolerance: Bool
        var clippedSamples: Int
    }

    /// Pasadas sobre la mezcla sin normalizar guardada (`scratch`, Float32 entrelazado): ganancia, limitador y medida,
    /// corrigiendo ganancia y umbral hasta cumplir `lufs` y `ceiling` (máximo `limiterMaxPasses`). Sin medida
    /// (silencio o menos de 400 ms) no hay ganancia que calcular: 0 dB, pero la mezcla se escribe.
    ///
    /// Cada pasada escribe `mixURL` (sobrescribe la anterior). La última pasada es siempre la entregada: el bucle solo
    /// corrige ganancia y umbral antes de otra pasada, nunca después de la última, así que no se repite para escribir.
    static func limiterNormalize(_ scratch: URL, frames: Int, sampleRate: Double, report: LoudnessReport, lufs: Double,
                                 ceiling: Double, mixURL: URL, progress: (Double) -> Void) throws -> LimiterOutcome {
        var gainDB = 0.0
        var adjust = limiterMarginDB
        var outOfTolerance = false
        var passes = 0
        var last = LimiterPass(lufs: report.integratedLUFS, truePeakDB: report.truePeakDB, reductionDB: 0)
        var clippedSamples = 0
        func runPass() throws -> LimiterPass {
            let writer = try makeWriter(mixURL, sampleRate: sampleRate)
            let result = try limiterPass(scratch, frames: frames, sampleRate: sampleRate, gainDB: gainDB,
                                         thresholdDB: ceiling + adjust, writer: writer)
            try writer.finish()
            clippedSamples = writer.clippedSamples
            passes += 1
            return result
        }
        if let measured = report.integratedLUFS {
            gainDB = lufs - measured
            // Pasada anterior con el mismo umbral (ganancia, LUFS), para la pendiente de la corrección.
            var previous: (gain: Double, lufs: Double)?
            for pass in 0..<limiterMaxPasses {
                last = try runPass()
                progress(0.5 + 0.4 * Double(pass + 1) / Double(limiterMaxPasses))
                let peakOK = last.truePeakDB <= ceiling
                let loudOK = abs((last.lufs ?? lufs) - lufs) <= limiterToleranceLU
                if peakOK && loudOK { break }
                if pass == limiterMaxPasses - 1 { outOfTolerance = true; break }
                if !peakOK {
                    adjust -= (last.truePeakDB - ceiling) + 0.02
                    previous = nil
                }
                if let l = last.lufs {
                    // Con el limitador actuando, 1 dB más de ganancia sube menos de 1 LU: paso de secante.
                    var slope = 1.0
                    if let p = previous, abs(gainDB - p.gain) > 1e-6 {
                        slope = min(max((l - p.lufs) / (gainDB - p.gain), limiterMinSlope), 1)
                    }
                    if peakOK { previous = (gainDB, l) }
                    gainDB += (lufs - l) / slope
                }
            }
        } else {
            last = try runPass()
        }
        return LimiterOutcome(last: last, gainDB: gainDB, thresholdDB: ceiling + adjust, passes: passes,
                              outOfTolerance: outOfTolerance, clippedSamples: clippedSamples)
    }

    /// Lee la mezcla sin normalizar, aplica la ganancia y el limitador, mide y, si hay `writer`, escribe.
    static func limiterPass(_ url: URL, frames: Int, sampleRate: Double, gainDB: Double, thresholdDB: Double,
                            writer: PCM24Writer?) throws -> LimiterPass {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let gain = Float(pow(10, gainDB / 20))
        let limiter = PeakLimiter(sampleRate: sampleRate, thresholdDB: thresholdDB)
        var meter = LoudnessMeter(sampleRate: sampleRate, channels: 2)
        func emit(_ l: [Float], _ r: [Float]) throws {
            guard !l.isEmpty else { return }
            meter.process([l, r])
            try writer?.write([l, r])
        }
        var left = frames
        while left > 0 {
            try Task.checkCancellation()
            let n = min(blockFrames, left)
            guard let data = try handle.read(upToCount: n * 8), data.count == n * 8 else { throw MontageMixError.invalidRange }
            var l = [Float](repeating: 0, count: n), r = l
            data.withUnsafeBytes { raw in
                let p = raw.bindMemory(to: Float.self)
                for i in 0..<n { l[i] = p[2 * i] * gain; r[i] = p[2 * i + 1] * gain }
            }
            let (ol, or) = limiter.process(l, r)
            try emit(ol, or)
            left -= n
        }
        let (fl, fr) = limiter.flush()
        try emit(fl, fr)
        let report = meter.report
        return LimiterPass(lufs: report.integratedLUFS, truePeakDB: report.truePeakDB, reductionDB: limiter.maxReductionDB)
    }

    // MARK: Envolventes

    /// Curva de fundido: seno al cuadrado, continua y con derivada 0 en los extremos (sin clics).
    static func ramp(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        let s = sin(Double.pi / 2 * c)
        return s * s
    }

    /// Envolvente (0…1) de un tramo `[a, b]` en el instante `t` (mismas unidades que `fade`).
    static func spanEnvelope(_ t: Double, _ a: Double, _ b: Double, fade: Double) -> Double {
        guard t >= a, t <= b else { return 0 }
        return ramp((t - a) / fade) * ramp((b - t) / fade)
    }

    /// Envolvente de la presencia de una pista en el instante `t` (s del tema).
    static func presenceEnvelope(_ presence: MontagePresence, at t: Double, fade: Double = presenceFadeSeconds) -> Double {
        switch presence {
        case .always: return 1
        case .audible(let spans):
            return spans.reduce(0) { max($0, spanEnvelope(t, $1.start, $1.end, fade: fade)) }
        case .silenced(let spans):
            return 1 - spans.reduce(0) { max($0, spanEnvelope(t, $1.start, $1.end, fade: fade)) }
        }
    }

    // MARK: Ficheros

    static func sanitized(_ name: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
        let cleaned = name.unicodeScalars.map { bad.contains($0) ? "-" : String($0) }.joined()
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "parte" : cleaned
    }

    static func uniqueName(_ base: String, used: inout Set<String>) -> String {
        var name = base
        var n = 2
        while used.contains(name.lowercased()) {
            name = "\(base)-\(n)"
            n += 1
        }
        used.insert(name.lowercased())
        return name
    }

    static func makeWriter(_ url: URL, sampleRate: Double) throws -> PCM24Writer {
        try PCM24Writer(url: url, sampleRate: sampleRate)
    }

    static func write(_ channels: [[Float]], to writer: PCM24Writer, sampleRate: Double) throws {
        try writer.write(channels)
    }

    // MARK: Render por bloques

    /// Orden fijo en que se suman los grupos a la mezcla: fondo primero y luego las partes por nombre.
    /// La suma en coma flotante no es asociativa; recorrer un diccionario (orden distinto en cada proceso)
    /// cambiaba el último bit de `mezcla.wav` entre ejecuciones. Dentro de un grupo, las pistas se suman en
    /// el orden de `job.tracks`, que es estable.
    static func summationOrder<S: Sequence>(_ groups: S) -> [MontageGroup] where S.Element == MontageGroup {
        func key(_ g: MontageGroup) -> (Int, String) {
            switch g {
            case .backing: return (0, "")
            case .part(let p): return (1, p)
            }
        }
        return groups.sorted { key($0) < key($1) }
    }

    struct Block {
        var mix: [[Float]]
        var groups: [MontageGroup: [[Float]]]
        var silence: [[Float]]
    }

    struct Renderer {
        /// Tramo ya en muestras de salida.
        struct Seg {
            var start: Double
            var frames: Int
            var fadeInFrames: Double
            var fadeOutFrames: Double
        }

        let job: MontageMixJob
        let totalFrames: Int
        private let segs: [Seg]
        #if canImport(AVFoundation)
        private var files: [AVAudioFile]
        #else
        private var files: [AudioFileReader]
        #endif
        private let gains: [Float]

        init(job: MontageMixJob, sources: [URL]) throws {
            self.job = job
            let fs = job.sampleRate
            segs = job.segments.map { s in
                let frames = Int(((s.end - s.start) * fs).rounded())
                // Cada fundido dura como mucho la mitad del tramo, exista o no el otro (misma regla que la imagen,
                // mini-spec Fase 7, «Transiciones»).
                let din = min(s.fadeIn ? (job.fadeIn ?? 0) * fs : 0, Double(frames) / 2)
                let dout = min(s.fadeOut ? (job.fadeOut ?? 0) * fs : 0, Double(frames) / 2)
                return Seg(start: s.start, frames: frames, fadeInFrames: din, fadeOutFrames: dout)
            }
            totalFrames = segs.reduce(0) { $0 + $1.frames }
            #if canImport(AVFoundation)
            var opened: [AVAudioFile] = []
            for url in sources {
                do { opened.append(try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)) }
                catch { throw MontageMixError.unreadable(url) }
            }
            #else
            var opened: [AudioFileReader] = []
            for url in sources {
                do { opened.append(try AudioFileReader(url: url)) } catch { throw MontageMixError.unreadable(url) }
            }
            #endif
            files = opened
            gains = job.tracks.map { Float(pow(10, $0.gainDB / 20)) }
        }

        /// Recorre los tramos y entrega cada bloque ya mezclado, con los fundidos globales aplicados.
        mutating func render(progress: (Double) -> Void, sink: (Block) throws -> Void) async throws {
            var written = 0
            for seg in segs {
                let offsets = job.tracks.map { Int(((seg.start - $0.songStart) * job.sampleRate).rounded()) }
                var start = 0
                while start < seg.frames {
                    try Task.checkCancellation()
                    let n = min(MontageMixer.blockFrames, seg.frames - start)
                    let zero = [[Float]](repeating: [Float](repeating: 0, count: n), count: 2)
                    var mix = zero
                    var groups: [MontageGroup: [[Float]]] = [:]
                    for (k, track) in job.tracks.enumerated() {
                        let env = envelope(track.presence, seg: seg, from: start, count: n)
                        guard let env else { continue }
                        let samples = try read(k, from: offsets[k] + start, count: n)
                        var acc = groups[track.group] ?? zero
                        let g = gains[k]
                        for c in 0..<2 {
                            for i in 0..<n {
                                let v = samples[c][i] * g * (env.isEmpty ? 1 : env[i])
                                acc[c][i] += v
                            }
                        }
                        groups[track.group] = acc
                    }
                    // Fundidos globales y suma.
                    let fade = globalFade(seg: seg, from: start, count: n)
                    for g in MontageMixer.summationOrder(groups.keys) {
                        var acc = groups[g]!
                        if let fade { for c in 0..<2 { for i in 0..<n { acc[c][i] *= fade[i] } } }
                        groups[g] = acc
                        for c in 0..<2 { for i in 0..<n { mix[c][i] += acc[c][i] } }
                    }
                    try sink(Block(mix: mix, groups: groups, silence: zero))
                    start += n
                    written += n
                    progress(Double(written) / Double(totalFrames))
                    await Task.yield()
                }
            }
        }

        /// Envolvente del bloque: `nil` = silencio todo el bloque (se salta la pista); `[]` = ganancia 1.
        private func envelope(_ presence: MontagePresence, seg: Seg, from start: Int, count n: Int) -> [Float]? {
            if case .always = presence { return [] }
            let fs = job.sampleRate
            let fade = MontageMixer.presenceFadeSeconds
            let t0 = seg.start + Double(start) / fs
            let t1 = seg.start + Double(start + n) / fs
            // Sin tramos cerca del bloque: audible = 0, silenced = 1.
            let spans: [MontageSpan]
            let inverse: Bool
            switch presence {
            case .always: return []
            case .audible(let s): spans = s; inverse = false
            case .silenced(let s): spans = s; inverse = true
            }
            let near = spans.filter { $0.end >= t0 && $0.start <= t1 }
            if near.isEmpty { return inverse ? [] : nil }
            var out = [Float](repeating: 0, count: n)
            var any = false
            for i in 0..<n {
                let t = seg.start + Double(start + i) / fs
                var e = 0.0
                for s in near { e = max(e, MontageMixer.spanEnvelope(t, s.start, s.end, fade: fade)) }
                let v = inverse ? 1 - e : e
                out[i] = Float(v)
                if v > 0 { any = true }
            }
            return any ? out : nil
        }

        private func globalFade(seg: Seg, from start: Int, count n: Int) -> [Float]? {
            guard seg.fadeInFrames > 0 || seg.fadeOutFrames > 0 else { return nil }
            let total = Double(seg.frames)
            var out = [Float](repeating: 1, count: n)
            for i in 0..<n {
                let f = Double(start + i)
                var v = 1.0
                if seg.fadeInFrames > 0 { v *= MontageMixer.ramp(f / seg.fadeInFrames) }
                if seg.fadeOutFrames > 0 { v *= MontageMixer.ramp((total - f) / seg.fadeOutFrames) }
                out[i] = Float(v)
            }
            return out
        }

        /// `count` fotogramas estéreo del fichero `k` desde `from` (puede ser negativo o pasar del final: ceros).
        private mutating func read(_ k: Int, from: Int, count: Int) throws -> [[Float]] {
            var out = [[Float]](repeating: [Float](repeating: 0, count: count), count: 2)
            #if !canImport(AVFoundation)
            let reader = files[k]
            let ra = max(from, 0), rb = min(from + count, reader.frameCount)
            guard rb > ra else { return out }
            try reader.seek(toFrame: ra)
            var rdone = 0
            while rdone < rb - ra {
                let chunk = try reader.read(maxFrames: min(16_384, rb - ra - rdone))
                let got = chunk.first?.count ?? 0
                if got == 0 { break }
                for c in 0..<2 {
                    let src = chunk[min(c, chunk.count - 1)]    // mono: el mismo canal a los dos lados
                    for i in 0..<got { out[c][ra - from + rdone + i] = src[i] }
                }
                rdone += got
            }
            return out
            #else
            let file = files[k]
            let length = Int(file.length)
            let a = max(from, 0), b = min(from + count, length)
            guard b > a else { return out }
            let nch = Int(file.processingFormat.channelCount)
            guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16_384) else { return out }
            file.framePosition = AVAudioFramePosition(a)
            var done = 0
            while done < b - a {
                buf.frameLength = 0
                try file.read(into: buf, frameCount: AVAudioFrameCount(min(16_384, b - a - done)))
                let got = Int(buf.frameLength)
                if got == 0 { break }
                let data = buf.floatChannelData!
                for c in 0..<2 {
                    let src = data[min(c, nch - 1)]    // mono: el mismo canal a los dos lados
                    for i in 0..<got { out[c][a - from + done + i] = src[i] }
                }
                done += got
            }
            return out
            #endif
        }
    }
}

/// Escritor de WAV estéreo PCM de 24 bits, sin conversiones intermedias: cabecera de 44 bytes y muestras
/// enteras little-endian; la cabecera se corrige al terminar.
final class PCM24Writer {
    private let handle: FileHandle
    private let sampleRate: Double
    private var frames = 0
    /// Muestras que no cupieron en 24 bits y se recortaron.
    private(set) var clippedSamples = 0
    private var finished = false

    init(url: URL, sampleRate: Double) throws {
        try? FileManager.default.removeItem(at: url)
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw MontageMixError.unreadable(url)
        }
        handle = try FileHandle(forWritingTo: url)
        self.sampleRate = sampleRate
        try handle.write(contentsOf: header(frames: 0))
    }

    deinit { if !finished { try? handle.close() } }

    private func header(frames: Int) -> Data {
        var d = Data()
        func u32(_ v: Int) { var x = UInt32(truncatingIfNeeded: v).littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: Int) { var x = UInt16(truncatingIfNeeded: v).littleEndian; d.append(Data(bytes: &x, count: 2)) }
        let bytes = frames * 6
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes)
        d.append(contentsOf: Array("WAVEfmt ".utf8)); u32(16)
        u16(1); u16(2); u32(Int(sampleRate)); u32(Int(sampleRate) * 6); u16(6); u16(24)
        d.append(contentsOf: Array("data".utf8)); u32(bytes)
        return d
    }

    func write(_ channels: [[Float]]) throws {
        let n = channels[0].count
        var data = Data(count: n * 6)
        var clippedHere = 0
        data.withUnsafeMutableBytes { raw in
            let p = raw.bindMemory(to: UInt8.self)
            for i in 0..<n {
                for c in 0..<2 {
                    let scaled = (channels[c][i] * 8_388_608).rounded()
                    if scaled > 8_388_607 || scaled < -8_388_608 { clippedHere += 1 }
                    let v = Int32(max(-8_388_608, min(8_388_607, scaled)))
                    let o = i * 6 + c * 3
                    p[o] = UInt8(truncatingIfNeeded: v)
                    p[o + 1] = UInt8(truncatingIfNeeded: v >> 8)
                    p[o + 2] = UInt8(truncatingIfNeeded: v >> 16)
                }
            }
        }
        try handle.write(contentsOf: data)
        clippedSamples += clippedHere
        frames += n
    }

    /// Escribe las longitudes de la cabecera y cierra.
    func finish() throws {
        guard !finished else { return }
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: header(frames: frames))
        try handle.close()
        finished = true
    }
}
