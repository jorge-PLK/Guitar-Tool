#if canImport(AVFoundation)
import Accelerate
import AVFoundation
#endif
import AudioKit
import XCTest
@testable import VideoKit
import struct VideoKit.MontageSpan

/// Tramos del vídeo en la rejilla de fotogramas y puerta de extremo a extremo con el mezclador real (decisiones de
/// Jorge del 16/11/2026 tras la auditoría de la Fase 7): `MontagePlan` → `MontageMixer` (−14 LUFS con limitador)
/// → `MontageExporter` (AAC). Mide la duración del vídeo, de `mezcla.wav` y del audio del `.mov`, el fundido en el
/// corte interior y la sonoridad y el pico real del audio ya en AAC.
final class MontageFrameGridTests: XCTestCase {
    static let fs = 48_000.0
    static let bar = 1.0
    static let songDuration = 15.0
    /// Tramos de duración no entera en fotogramas (encargo): 7,013 s y 3,3371 s.
    static let takeA = MontageSpan(start: 1.987, end: 9.0)
    static let takeB = MontageSpan(start: 1.987, end: 5.3241)
    static let takeC = MontageSpan(start: 1.987, end: 9.0)
    static let solos = [MontageSpan(start: 4.0129, end: 5.0), MontageSpan(start: 7.5, end: 8.4871)]
    /// «Cortar huecos»: B de 1,987 a 9,0 (segmento de 7,013 s) y un solo de C que, con la anticipación de 0,5 s,
    /// deja un segmento de 10,5129 a 13,85 (3,3371 s).
    static let cutTakeB = MontageSpan(start: 1.987, end: 9.0)
    static let cutTakeC = MontageSpan(start: 1.987, end: 14.0)
    static let cutSolo = MontageSpan(start: 11.0129, end: 13.85)
    /// Diferencia de duración admitida: menos de medio fotograma (encargo).
    static let durationTolerance = 0.5
    /// Sonoridad integrada del `.mov` (encargo: −14 ± 0,3 LUFS).
    static let lufsTolerance = 0.3
    /// Pico real del `.mov` (mini-spec, «Exportación»: tope de −1 dBTP).
    static let truePeakCeiling = MontageMixer.peakCeilingDB
    /// Holgura del códec que reserva `MontageMixer` (`codecHeadroomDB`, interno de AudioKit; Jorge, 17/11/2026):
    /// el AAC no debe subir el pico real local más que esto respecto a `mezcla.wav`.
    static let codecHeadroomDB = 0.3
    /// Ventanas para comparar el pico real del `.mov` con el de `mezcla.wav` en el mismo sitio; solo cuentan las
    /// que están a menos de `peakWindowRangeDB` del pico del WAV (las que pueden tocar el tope).
    static let peakWindow = 0.020
    static let peakWindowRangeDB = 1.0
    /// Caja de altavoz de las señales de la puerta (ver `fixture`).
    static let cabCutoff = 5_000.0
    /// Ventanas para el fundido del corte: corta en el borde, larga en mitad del tramo.
    static let edgeWindow = 0.020
    static let midWindow = 0.200
    /// En el borde del corte el nivel debe quedar al menos 20 dB por debajo del de mitad del tramo (un compás de
    /// fundido deja, a 20 ms del final, una ganancia del orden de 0,02 o menos: −34 dB).
    static let edgeMaxRatioDB = -20.0

    // MARK: Rejilla (sin AVFoundation)

    func frameDuration(_ fps: Double) -> Double {
        #if canImport(CoreMedia)
        let f = MontagePlan.frameTime(fps: fps)
        #else
        let f = MontagePlan.frameTicks(fps: fps)
        #endif
        return Double(f.value) / Double(f.timescale)
    }

    func assertOnGrid(_ t: Double, _ fps: Double, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        let k = t / frameDuration(fps)
        XCTAssertEqual(k, k.rounded(), accuracy: 1e-6, "\(what) = \(t) s no está en la rejilla de \(fps) fps", file: file, line: line)
    }

    func testQuantizedSegmentsAreWholeFramesAndCoverTheRaw() throws {
        let raw = [MontageSpan(start: 1.987, end: 9.0), MontageSpan(start: 10.5129, end: 13.85)]
        XCTAssertEqual(raw[0].duration, 7.013, accuracy: 1e-9)
        XCTAssertEqual(raw[1].duration, 3.3371, accuracy: 1e-9)
        var report: [String] = []
        for fps in [30.0, 30_000.0 / 1001, 29.97, 24, 25, 60] {
            let dt = frameDuration(fps)
            let plan = MontagePlan(canvas: .landscape, fps: fps, layout: .side, segments: raw, barDuration: Self.bar,
                                   fadeIn: false, fadeOut: false, parts: [])
            XCTAssertEqual(plan.segments.count, 2)
            var frames = 0
            for (q, r) in zip(plan.segments, raw) {
                assertOnGrid(q.start, fps, "inicio")
                assertOnGrid(q.end, fps, "final")
                // Inicio hacia abajo y final hacia arriba, menos de un fotograma.
                XCTAssertLessThanOrEqual(q.start, r.start)
                XCTAssertGreaterThan(q.start, r.start - dt)
                XCTAssertGreaterThanOrEqual(q.end, r.end)
                XCTAssertLessThan(q.end, r.end + dt)
                frames += Int((q.duration / dt).rounded())
            }
            // Sin deriva: cada inicio en el vídeo concatenado es un número entero de fotogramas.
            for v in plan.timeMap.videoStarts { assertOnGrid(v, fps, "inicio en el vídeo") }
            assertOnGrid(plan.videoDuration, fps, "duración")
            XCTAssertEqual(plan.videoDuration, Double(frames) * dt, accuracy: 1e-9)
            // Anticipación: la primera nota (presencia 0,5 s después del inicio crudo) sigue a ≥ 0,5 s del inicio.
            XCTAssertGreaterThanOrEqual(raw[0].start + MontageStyle.anticipation - plan.segments[0].start, MontageStyle.anticipation)
            report.append(String(format: "%.3f fps: %d fotogramas, %.6f s (crudo %.4f)", fps, frames, plan.videoDuration, 7.013 + 3.3371))
        }
        print("F7 rejilla: \(report.joined(separator: "; "))")
    }

    func testGridHoldsOnAssignmentFpsChangeDecodeAndMerges() throws {
        var plan = MontagePlan(canvas: .landscape, fps: 30, layout: .side, segments: [MontageSpan(start: 1.987, end: 9.0)],
                               barDuration: Self.bar, fadeIn: false, fadeOut: false, parts: [])
        XCTAssertEqual(plan.segments, [MontageSpan(start: 59.0 / 30, end: 9.0)])
        // Ya en la rejilla (salvo coma flotante): no se mueve.
        XCTAssertEqual(MontagePlan.quantized([MontageSpan(start: 2, end: 3.2)], fps: 30), [MontageSpan(start: 2, end: 3.2)])
        // Dos tramos a menos de un fotograma tras redondear: se funden.
        XCTAssertEqual(MontagePlan.quantized([MontageSpan(start: 1, end: 2.01), MontageSpan(start: 2.02, end: 3)], fps: 30),
                       [MontageSpan(start: 1, end: 3)])
        plan.segments = [MontageSpan(start: 0.01, end: 3.3371)]
        assertOnGrid(plan.segments[0].start, 30, "asignado")
        assertOnGrid(plan.segments[0].end, 30, "asignado")
        plan.fps = 30_000.0 / 1001
        assertOnGrid(plan.segments[0].end, plan.fps, "tras cambiar fps")
        let json = """
        {"canvas":{"width":1920,"height":1080},"fps":30,"layout":"side","segments":[{"start":1.987,"end":9.0}],
         "barDuration":1,"fadeIn":false,"fadeOut":false,"parts":[],"audio":[]}
        """
        let decoded = try JSONDecoder().decode(MontagePlan.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.segments, [MontageSpan(start: 59.0 / 30, end: 9.0)])
        XCTAssertEqual(try JSONDecoder().decode(MontagePlan.self, from: JSONEncoder().encode(decoded)), decoded)
    }

    // Mac y Windows (parte 7.9): en Windows el audio se decodifica con Media Foundation y el pico real va sin vDSP.
    // MARK: Señales

    /// Ruido uniforme determinista.
    static func noise(_ n: Int, seed: UInt64, amp: Float) -> [Float] {
        var s = seed
        return (0..<n).map { _ in
            s = s &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return amp * (Float(Double(s >> 11) / Double(1 << 53)) * 2 - 1)
        }
    }

    /// Notas punteadas: diente de sierra con ataque seco y caída exponencial cada `period` s (rico en armónicos y
    /// con transitorios, para que el limitador trabaje y el AAC tenga picos que sobrepasar).
    static func plucks(_ seconds: Double, freq: Double, period: Double, amp: Float) -> [Float] {
        (0..<Int(seconds * fs)).map { i in
            let t = Double(i) / fs
            let local = t.truncatingRemainder(dividingBy: period)
            let phase = (freq * t).truncatingRemainder(dividingBy: 1)
            return amp * Float((2 * phase - 1) * exp(-local / 0.12))
        }
    }

    /// Paso bajo de 12 dB/oct (dos polos simples en cascada) a `cutoff` Hz: la caja de altavoz por la que pasa
    /// cualquier guitarra real (IR de la HeadRush). `nil`: la señal tal cual.
    static func cab(_ x: [Float], cutoff: Double?) -> [Float] {
        guard let fc = cutoff else { return x }
        let a = Float(exp(-2 * .pi * fc / fs))
        var y1: Float = 0, y2: Float = 0
        return x.map { v in
            y1 = a * y1 + (1 - a) * v
            y2 = a * y2 + (1 - a) * y1
            return y2
        }
    }

    struct Source {
        let id: String
        let name: String
        let isSolo: Bool
        let take: MontageSpan
        let presence: [MontageSpan]
        let freq: Double
        let color: (b: UInt8, g: UInt8, r: UInt8)
    }

    struct Fixture {
        let dir: URL
        let parts: [MontagePart]
        let tracks: [MontageTrack]
    }

    /// Tomas de vídeo de color liso, sus WAV de notas y el backing del tema entero, todo por la caja de altavoz.
    ///
    /// Por qué la caja (investigación del 17/11/2026): sin ella (dientes de sierra con ataque seco y ruido blanco
    /// hasta 24 kHz; energía por encima de 16 kHz a −18 dB del total, frente a −42 dB en la mezcla de la demo) el
    /// AAC de 128 kb/s/canal sube el pico real local de forma errática, de −0,48 a +0,49 dB según el ataque, y el
    /// del `.mov` quedaba en ≈ −1,0 dBTP por casualidad (techo del WAV −0,85/−1,05/−1,35/−1,65 → `.mov`
    /// −0,92/−1,01/−1,02/−1,19). Mitad del sobrepaso es Gibbs del recorte de banda del códec (~21 kHz: un paso bajo
    /// a 20 kHz sin códec ya da +0,14 dB en el mismo ataque) y el resto, ruido de cuantización en el transitorio
    /// (error AAC −37 dBFS RMS, frente a −51 en la demo). Con la caja a 5 kHz (espectro como el de la demo, error
    /// −47,6 dBFS) el sobrepaso local cerca del pico es ≤ +0,06 dB y el `.mov` sigue al WAV.
    static func fixture(_ sources: [Source], dir: URL, cabCutoff: Double? = MontageFrameGridTests.cabCutoff) async throws -> Fixture {
        let n = Int(songDuration * fs)
        let backing = dir.appendingPathComponent("backing-src.wav")
        let bass = plucks(songDuration, freq: 82.41, period: 0.5, amp: 0.25)
        let l = cab(zip(noise(n, seed: 1, amp: 0.08), bass).map(+), cutoff: cabCutoff)
        let r = cab(zip(noise(n, seed: 2, amp: 0.08), bass).map(+), cutoff: cabCutoff)
        try TestWav.write([l, r], sampleRate: fs, to: backing)
        var parts: [MontagePart] = []
        var tracks = [MontageTrack(id: "backing", url: backing, songStart: 0, gainDB: 0, group: .backing, presence: .always)]
        for s in sources {
            let mov = dir.appendingPathComponent("\(s.id).mov")
            _ = try await VideoFileTests.writeVideo(mov, start: s.take.start, seconds: s.take.duration, color: s.color)
            parts.append(MontagePart(id: s.id, name: s.name, isSolo: s.isSolo, presence: s.presence,
                                     video: MontagePartVideo(url: mov, videoOffset: 0, take: s.take)))
            guard !s.presence.isEmpty else { continue }
            let wav = dir.appendingPathComponent("\(s.id).wav")
            let notes = cab(plucks(s.take.duration, freq: s.freq, period: 0.25, amp: 0.5), cutoff: cabCutoff)
            try TestWav.write([notes, notes], sampleRate: fs, to: wav)
            tracks.append(MontageTrack(id: "take-\(s.id)", url: wav, songStart: s.take.start, gainDB: 0, group: .part(s.name),
                                       presence: .audible(s.presence.map { AudioKit.MontageSpan(start: $0.start, end: $0.end) })))
        }
        return Fixture(dir: dir, parts: parts, tracks: tracks)
    }

    static func gateSources() -> [Source] {
        [Source(id: "A", name: "Rítmica 1", isSolo: false, take: takeA,
                presence: MontagePlan.presence(take: takeA, isSolo: false, soloSections: solos), freq: 196, color: (0, 0, 255)),
         Source(id: "B", name: "Rítmica 2", isSolo: false, take: takeB,
                presence: MontagePlan.presence(take: takeB, isSolo: false, soloSections: solos), freq: 247, color: (0, 255, 0)),
         Source(id: "C", name: "Solista", isSolo: true, take: takeC,
                presence: MontagePlan.presence(take: takeC, isSolo: true, soloSections: solos), freq: 659, color: (255, 0, 0))]
    }

    static func cutSources() -> [Source] {
        [Source(id: "B", name: "Rítmica 2", isSolo: false, take: cutTakeB,
                presence: MontagePlan.presence(take: cutTakeB, isSolo: false, soloSections: [cutSolo]), freq: 247, color: (0, 255, 0)),
         Source(id: "C", name: "Solista", isSolo: true, take: cutTakeC,
                presence: MontagePlan.presence(take: cutTakeC, isSolo: true, soloSections: [cutSolo]), freq: 659, color: (255, 0, 0))]
    }

    // MARK: Medidas del fichero final

    struct Decoded {
        var channels: [[Float]]
        var sampleRate: Double
        var duration: Double { Double(channels.first?.count ?? 0) / sampleRate }
    }

    /// Audio de un fichero decodificado a PCM float con AVFoundation (el AAC del `.mov`, sin el cebado del códec).
    static func decodeAudio(_ url: URL) async throws -> Decoded {
        #if !canImport(AVFoundation)
        // Windows: lector de Media Foundation (el AAC va sin compensar y Media Foundation lo lee en su sitio).
        let a = try MediaFoundationReader.audio(url)
        return Decoded(channels: a.channels, sampleRate: a.sampleRate)
        #else
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let track = try XCTUnwrap(tracks.first, "pista de audio")
        let descs = try await track.load(.formatDescriptions)
        let desc = try XCTUnwrap(descs.first)
        let asbd = try XCTUnwrap(CMAudioFormatDescriptionGetStreamBasicDescription(desc)).pointee
        let nch = Int(asbd.mChannelsPerFrame)
        let reader = try AVAssetReader(asset: asset)
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false
        ])
        reader.add(out)
        XCTAssertTrue(reader.startReading())
        var ch = [[Float]](repeating: [], count: nch)
        while let s = out.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(s) else { continue }
            let bytes = CMBlockBufferGetDataLength(block)
            var raw = [Float](repeating: 0, count: bytes / 4)
            _ = raw.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes, destination: $0.baseAddress!) }
            for c in 0..<nch { ch[c].append(contentsOf: stride(from: c, to: raw.count, by: nch).map { raw[$0] }) }
        }
        XCTAssertEqual(reader.status, .completed)
        return Decoded(channels: ch, sampleRate: asbd.mSampleRate)
        #endif
    }

    static func readWAV(_ url: URL) throws -> Decoded {
        #if !canImport(AVFoundation)
        let a = try MediaFoundationReader.audio(url)
        return Decoded(channels: a.channels, sampleRate: a.sampleRate)
        #else
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let nch = Int(file.processingFormat.channelCount)
        var ch = [[Float]](repeating: [], count: nch)
        let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 65_536)!
        while file.framePosition < file.length {
            try file.read(into: buf)
            if buf.frameLength == 0 { break }
            for c in 0..<nch { ch[c].append(contentsOf: UnsafeBufferPointer(start: buf.floatChannelData![c], count: Int(buf.frameLength))) }
        }
        return Decoded(channels: ch, sampleRate: file.processingFormat.sampleRate)
        #endif
    }

    /// RMS (dBFS, todos los canales) en `[from, from + length)` s.
    static func rmsDB(_ d: Decoded, from: Double, length: Double) -> Double {
        let a = max(0, Int((from * d.sampleRate).rounded())), b = min(d.channels[0].count, a + Int((length * d.sampleRate).rounded()))
        guard b > a else { return -.infinity }
        var sum = 0.0
        for c in d.channels { for i in a..<b { sum += Double(c[i]) * Double(c[i]) } }
        return 10 * log10(max(sum / Double((b - a) * d.channels.count), 1e-20))
    }

    /// Pico real (dBTP, todos los canales) por ventanas consecutivas de `window` s: |x| y tres intermedias por
    /// muestra con un sinc enventanado de 48 coeficientes (4×, como BS.1770). Sirve para comparar dos señales
    /// alineadas ventana a ventana; el pico global lo da `LoudnessMeter`.
    static func windowTruePeaksDB(_ d: Decoded, window: Double) -> [Double] {
        let taps = 48, center = taps / 2 - 1
        let w = max(1, Int((window * d.sampleRate).rounded()))
        let n = d.channels.first?.count ?? 0
        var peak = [Double](repeating: 0, count: (n + w - 1) / w)
        let kernels: [[Double]] = (1..<4).map { p in
            let frac = Double(p) / 4
            return (0..<taps).map { k in
                let x = Double(k - center) - frac
                let sinc = abs(x) < 1e-12 ? 1 : sin(.pi * x) / (.pi * x)
                // Hann centrado en el instante interpolado (`center + frac`).
                return sinc * (0.5 - 0.5 * cos(2 * .pi * (Double(k) + 1 - frac) / Double(taps)))
            }
        }
        for c in d.channels {
            // y[i] = Σ x[i - center + k]·h[k]: la intermedia entre x[i] y x[i+1].
            let ext = [Double](repeating: 0, count: center) + c.map(Double.init) + [Double](repeating: 0, count: taps - center)
            var env = c.map { abs(Double($0)) }
            var y = [Double](repeating: 0, count: n)
            for h in kernels {
                #if canImport(Accelerate)
                vDSP_convD(ext, 1, h, 1, &y, 1, vDSP_Length(n), vDSP_Length(taps))
                vDSP_vabsD(y, 1, &y, 1, vDSP_Length(n))
                vDSP_vmaxD(env, 1, y, 1, &env, 1, vDSP_Length(n))
                #else
                // Windows: la misma correlación que `vDSP_convD` (y[i] = Σ ext[i + k]·h[k]).
                ext.withUnsafeBufferPointer { e in
                    for i in 0..<n {
                        var s = 0.0
                        for k in 0..<taps { s += e[i + k] * h[k] }
                        y[i] = abs(s)
                        if y[i] > env[i] { env[i] = y[i] }
                    }
                }
                #endif
            }
            for i in 0..<n where env[i] > peak[i / w] { peak[i / w] = env[i] }
        }
        return peak.map { 20 * log10(max($0, 1e-12)) }
    }

    struct Run {
        var plan: MontagePlan
        var mix: MontageMixResult
        var mov: URL
        var frames: Int
        var videoDuration: Double
        var movAudioTrack: Double
        var movAudio: Decoded
        var wav: Decoded
    }

    /// Plan → `MontageMixer` (normalización estándar con limitador, los tramos del plan con la regla de fundidos de
    /// la app: global en los extremos, siempre en los cortes) → `MontageExporter` con esa mezcla.
    static func run(_ fx: Fixture, segments raw: [MontageSpan], fps: Double, fadeIn: Bool, fadeOut: Bool, name: String,
                    settings: MontageExportSettings? = nil) async throws -> Run {
        let settings = settings ?? MontageExportSettings(codec: .h264, width: 320, height: 180, fps: fps)
        let plan = MontagePlan(canvas: .landscape, fps: fps, layout: .side, segments: raw, barDuration: bar,
                               fadeIn: fadeIn, fadeOut: fadeOut, parts: fx.parts)
        let segs = plan.segments
        let mixURL = fx.dir.appendingPathComponent("mezcla-\(name).wav")
        let job = MontageMixJob(segments: segs.enumerated().map { i, s in
            MontageSegment(start: s.start, end: s.end, fadeIn: i == 0 ? plan.fadeIn : true, fadeOut: i == segs.count - 1 ? plan.fadeOut : true)
        }, sampleRate: fs, tracks: fx.tracks, fadeIn: plan.barDuration, fadeOut: plan.barDuration,
                                normalization: .standard, mixURL: mixURL)
        let mix = try await MontageMixer.mix(job)
        let mov = fx.dir.appendingPathComponent("montaje-\(name).\(settings.container.fileExtension)")
        let summary = try await MontageExporter.export(plan: plan, mixURL: mixURL, settings: settings, to: mov)
        #if !canImport(AVFoundation)
        // Windows: duración del vídeo = último PTS + su duración (lector de Media Foundation); pista de audio = suma de
        // las duraciones de sus muestras (`stts`).
        var frames = 0, videoEnd = 0.0
        try MediaFoundationReader.forEachFrame(mov) { t, d, _ in frames += 1; videoEnd = max(videoEnd, t + d); return true }
        XCTAssertEqual(summary.frames, frames)
        let soun = try XCTUnwrap(MP4EditList.tracks(in: mov).first { $0.handler == "soun" }, "pista de audio")
        return Run(plan: plan, mix: mix, mov: mov, frames: frames, videoDuration: videoEnd,
                   movAudioTrack: Double(soun.sampleDuration) / Double(soun.mediaTimescale),
                   movAudio: try await decodeAudio(mov), wav: try readWAV(mixURL))
        #else
        let asset = AVURLAsset(url: mov)
        let vts = try await asset.loadTracks(withMediaType: .video)
        let ats = try await asset.loadTracks(withMediaType: .audio)
        let vt = try XCTUnwrap(vts.first), at = try XCTUnwrap(ats.first)
        let frames = try await VideoFileTests.ptsOf(mov).count
        XCTAssertEqual(summary.frames, frames)
        return Run(plan: plan, mix: mix, mov: mov, frames: frames,
                   videoDuration: CMTimeGetSeconds(try await vt.load(.timeRange).duration),
                   movAudioTrack: CMTimeGetSeconds(try await at.load(.timeRange).duration),
                   movAudio: try await decodeAudio(mov), wav: try readWAV(mixURL))
        #endif
    }

    /// Duraciones: vídeo = suma de tramos cuantizados = `mezcla.wav` = audio del `.mov`, todo a menos de medio
    /// fotograma. Devuelve la mayor diferencia (s) para el informe.
    @discardableResult
    func checkDurations(_ r: Run, _ name: String) -> Double {
        let dt = frameDuration(r.plan.fps)
        let want = r.plan.videoDuration
        let tol = Self.durationTolerance * dt
        XCTAssertEqual(r.frames, Int((want / dt).rounded()), "\(name): fotogramas")
        let measured = [("vídeo", r.videoDuration), ("mezcla.wav", r.wav.duration), ("pista de audio del .mov", r.movAudioTrack),
                        ("audio decodificado del .mov", r.movAudio.duration), ("mezcla (resultado)", r.mix.duration)]
        var worst = 0.0
        for (what, d) in measured {
            XCTAssertEqual(d, want, accuracy: tol, "\(name): \(what)")
            worst = max(worst, abs(d - want))
        }
        print(String(format: "F7 duraciones %@ (%.3f fps, tramos %@): plan %.6f s = %d fotogramas; vídeo %.6f, mezcla.wav %.6f, pista .mov %.6f, .mov decodificado %.6f; máx |Δ| %.3f ms (tolerancia %.3f ms)",
                     name, r.plan.fps, r.plan.segments.map { String(format: "%.4f–%.4f", $0.start, $0.end) }.joined(separator: ", "),
                     want, r.frames, r.videoDuration, r.wav.duration, r.movAudioTrack, r.movAudio.duration, worst * 1000, tol * 1000))
        return worst
    }

    /// Sonoridad y pico real del audio del `.mov` (AAC) frente a los de `mezcla.wav`.
    func checkLoudness(_ r: Run, _ name: String) {
        let mov = LoudnessMeter.measure(r.movAudio.channels, sampleRate: r.movAudio.sampleRate)
        let wav = LoudnessMeter.measure(r.wav.channels, sampleRate: r.wav.sampleRate)
        let lufs = mov.integratedLUFS ?? -.infinity
        print(String(format: "F7 sonoridad %@: según MontageMixer %.2f LUFS %.2f dBTP (fuera de tolerancia: %@)", name,
                     r.mix.finalLUFS ?? -.infinity, r.mix.finalTruePeakDB, r.mix.limiterOutOfTolerance ? "sí" : "no"))
        print(String(format: "F7 sonoridad %@: mezcla.wav %.2f LUFS %.2f dBTP (limitador %@, reducción máx %.2f dB); .mov AAC %d kb/s/canal %.2f LUFS %.2f dBTP (Δ %+.2f LU, %+.2f dB de pico)",
                     name, wav.integratedLUFS ?? -.infinity, wav.truePeakDB, r.mix.limiterApplied ? "sí" : "no", r.mix.limiterMaxReductionDB,
                     MontageExporter.aacBitRatePerChannel / 1000, lufs, mov.truePeakDB,
                     lufs - (wav.integratedLUFS ?? 0), mov.truePeakDB - wav.truePeakDB))
        XCTAssertEqual(lufs, MontageMixer.targetLUFS, accuracy: Self.lufsTolerance, "\(name): LUFS del .mov")
        XCTAssertLessThanOrEqual(mov.truePeakDB, Self.truePeakCeiling, "\(name): pico real del .mov")

        // Sobrepaso local del AAC: el tope del `.mov` no debe salir por casualidad, sino porque en cada ventana
        // que puede tocarlo el códec sube el pico menos que la holgura reservada en la mezcla.
        let pw = Self.windowTruePeaksDB(r.wav, window: Self.peakWindow)
        let pm = Self.windowTruePeaksDB(r.movAudio, window: Self.peakWindow)
        let top = pw.max() ?? -.infinity
        var worst = -Double.infinity, at = 0.0, count = 0
        for (k, (w, m)) in zip(pw, pm).enumerated() where w >= top - Self.peakWindowRangeDB {
            count += 1
            if m - w > worst { worst = m - w; at = Double(k) * Self.peakWindow }
        }
        print(String(format: "F7 sonoridad %@: sobrepaso AAC local máx %+.3f dB en %.2f s (%d ventanas de %.0f ms a < %.1f dB del pico del WAV; holgura %.2f dB)",
                     name, worst, at, count, Self.peakWindow * 1000, Self.peakWindowRangeDB, Self.codecHeadroomDB))
        XCTAssertLessThanOrEqual(worst, Self.codecHeadroomDB, "\(name): sobrepaso local del AAC en \(at) s")
    }

    // MARK: Puerta

    /// Rítmica entera, parcial y solista con dos solos, sin cortar huecos: tramo de 1,987 a 9,0 s (7,013 s, no entero
    /// en fotogramas) a 30 fps.
    func testGateRealMixerDurationsAndAACLoudness() async throws {
        let dir = try TestWav.tempDir("MontageFrameGridTests")
        defer { try? FileManager.default.removeItem(at: dir) }
        let fx = try await Self.fixture(Self.gateSources(), dir: dir)
        let raw = MontagePlan.segments(presences: fx.parts.map(\.presence), imageStarts: fx.parts.map { $0.video?.take.start }, cutGaps: false)
        XCTAssertEqual(raw, [Self.takeA])
        let fades = MontagePlan.globalFades(span: raw[0], songDuration: Self.songDuration)
        let r = try await Self.run(fx, segments: raw, fps: 30, fadeIn: fades.fadeIn, fadeOut: fades.fadeOut, name: "puerta")
        XCTAssertEqual(r.plan.segments, [MontageSpan(start: 59.0 / 30, end: 9.0)])
        XCTAssertEqual(r.frames, 211)
        checkDurations(r, "puerta")
        checkLoudness(r, "puerta")
    }

    /// Marca mayor del `ftyp` (bytes 8–11) del fichero.
    static func majorBrand(_ url: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        let head = try XCTUnwrap(try h.read(upToCount: 12))
        XCTAssertEqual(String(decoding: head[4..<8], as: UTF8.self), "ftyp", "\(url.lastPathComponent): caja ftyp")
        return String(decoding: head[8..<12], as: UTF8.self)
    }

    /// Etiqueta del códec de vídeo (`hvc1`, `avc1`…), tamaño y fps nominales de la pista.
    static func videoInfo(_ url: URL) async throws -> (fourCC: String, size: CGSize, fps: Double) {
        #if !canImport(AVFoundation)
        // Windows: la etiqueta de la entrada de muestra en el `moov`; tamaño y fps del lector de Media Foundation.
        let (moov, _) = try MP4EditList.readMoov(url)
        let cc = ["hvc1", "hev1", "avc1", "avc3"].first { moov.range(of: Data($0.utf8)) != nil } ?? "?"
        let info = try MediaFoundationReader.info(url)
        return (cc, CGSize(width: info.width, height: info.height), info.fps)
        #else
        let tracks = try await AVURLAsset(url: url).loadTracks(withMediaType: .video)
        let vt = try XCTUnwrap(tracks.first)
        let descs = try await vt.load(.formatDescriptions)
        let desc = try XCTUnwrap(descs.first)
        let st = CMFormatDescriptionGetMediaSubType(desc)
        let cc = String(decoding: [24, 16, 8, 0].map { UInt8((st >> $0) & 0xFF) }, as: UTF8.self)
        return (cc, try await vt.load(.naturalSize), Double(try await vt.load(.nominalFrameRate)))
        #endif
    }

    /// Puerta en MP4 (Jorge, 17/11/2026): la misma puerta escrita como MP4 con H.264 y con HEVC frente al `.mov`:
    /// fichero MP4 de verdad (`ftyp` no QuickTime), HEVC etiquetado `hvc1`, tamaño y fps pedidos, duraciones de vídeo
    /// y audio iguales a las del `.mov` a menos de medio fotograma y el mismo audio (LUFS y dBTP).
    func testGateMP4MatchesMOV() async throws {
        let dir = try TestWav.tempDir("MontageFrameGridTests")
        defer { try? FileManager.default.removeItem(at: dir) }
        let fx = try await Self.fixture(Self.gateSources(), dir: dir)
        let raw = MontagePlan.segments(presences: fx.parts.map(\.presence), imageStarts: fx.parts.map { $0.video?.take.start }, cutGaps: false)
        let fades = MontagePlan.globalFades(span: raw[0], songDuration: Self.songDuration)
        func go(_ name: String, _ s: MontageExportSettings) async throws -> Run {
            try await Self.run(fx, segments: raw, fps: 30, fadeIn: fades.fadeIn, fadeOut: fades.fadeOut, name: name, settings: s)
        }
        let mov = try await go("mov", MontageExportSettings(codec: .h264, width: 320, height: 180, fps: 30))
        #if canImport(AVFoundation)
        XCTAssertEqual(try Self.majorBrand(mov.mov), "qt  ")
        let hevcTag = "hvc1"
        #else
        // [windows] `IMFSinkWriter` escribe MPEG-4 sea cual sea la extensión (parte 7.2): el `.mov` lleva marca MP4.
        XCTAssertTrue(["mp42", "isom", "mp41"].contains(try Self.majorBrand(mov.mov)))
        // Sin codificador HEVC (la VM), H.264.
        let hevcTag = MediaFoundationEncoders.hasHEVC ? "hev1|hvc1" : "avc1"
        #endif
        let movLoud = LoudnessMeter.measure(mov.movAudio.channels, sampleRate: mov.movAudio.sampleRate)
        let dt = frameDuration(30)
        var lines: [String] = []
        for (codec, w, h, tag) in [(MontageCodec.h264, 320, 180, "avc1"), (MontageCodec.hevc, 640, 360, hevcTag)] {
            let name = "mp4-\(codec.rawValue)"
            let r = try await go(name, MontageExportSettings(codec: codec, width: w, height: h, fps: 30, container: .mp4))
            XCTAssertEqual(r.mov.pathExtension, "mp4")
            let brand = try Self.majorBrand(r.mov)
            XCTAssertTrue(["mp42", "isom", "mp41"].contains(brand), "\(name): marca \(brand)")
            let info = try await Self.videoInfo(r.mov)
            XCTAssertTrue(tag.split(separator: "|").contains { $0 == info.fourCC }, "\(name): etiqueta del códec \(info.fourCC), esperada \(tag)")
            XCTAssertEqual(info.size, CGSize(width: w, height: h), "\(name): tamaño")
            XCTAssertEqual(info.fps, 30, accuracy: 0.01, "\(name): fps")
            XCTAssertEqual(r.frames, mov.frames, "\(name): fotogramas")
            checkDurations(r, name)
            for (what, a, b) in [("vídeo", r.videoDuration, mov.videoDuration), ("pista de audio", r.movAudioTrack, mov.movAudioTrack),
                                 ("audio decodificado", r.movAudio.duration, mov.movAudio.duration)] {
                XCTAssertEqual(a, b, accuracy: Self.durationTolerance * dt, "\(name): \(what) frente al .mov")
            }
            checkLoudness(r, name)
            let l = LoudnessMeter.measure(r.movAudio.channels, sampleRate: r.movAudio.sampleRate)
            // Mismo WAV y mismo codificador AAC: el audio debe ser el mismo (tolerancia de redondeo del medidor).
            XCTAssertEqual(l.integratedLUFS ?? 0, movLoud.integratedLUFS ?? 0, accuracy: 0.02, "\(name): LUFS frente al .mov")
            XCTAssertEqual(l.truePeakDB, movLoud.truePeakDB, accuracy: 0.02, "\(name): dBTP frente al .mov")
            lines.append(String(format: "%@ (%@, %@, %.0f×%.0f, %.2f fps) %d fotogramas, vídeo %.6f s, audio %.6f s, %.2f LUFS %.2f dBTP",
                                name, brand, info.fourCC, info.size.width, info.size.height, info.fps, r.frames, r.videoDuration,
                                r.movAudio.duration, l.integratedLUFS ?? -.infinity, l.truePeakDB))
        }
        print(String(format: "F7 contenedor: .mov %d fotogramas, vídeo %.6f s, audio %.6f s, %.2f LUFS %.2f dBTP; ", mov.frames, mov.videoDuration,
                     mov.movAudio.duration, movLoud.integratedLUFS ?? -.infinity, movLoud.truePeakDB) + lines.joined(separator: "; "))
    }

    /// Extensión de la URL distinta del contenedor: error antes de escribir nada; ajustes antiguos sin contenedor: `.mov`.
    func testContainerMismatchAndLegacySettings() async throws {
        let dir = try TestWav.tempDir("MontageFrameGridTests")
        defer { try? FileManager.default.removeItem(at: dir) }
        let plan = MontagePlan(canvas: .landscape, fps: 30, layout: .side, segments: [MontageSpan(start: 0, end: 1)],
                               barDuration: Self.bar, fadeIn: false, fadeOut: false, parts: [])
        let out = dir.appendingPathComponent("montaje.mov")
        do {
            _ = try await MontageExporter.export(plan: plan, mixURL: nil,
                                                 settings: MontageExportSettings(codec: .h264, width: 320, height: 180, fps: 30, container: .mp4), to: out)
            XCTFail("debía fallar")
        } catch {
            XCTAssertEqual(error as? MontageError, .containerMismatch(expected: "mp4", got: "mov"))
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), [])
        let legacy = #"{"codec":"hevc","width":1920,"height":1080,"fps":30}"#
        XCTAssertEqual(try JSONDecoder().decode(MontageExportSettings.self, from: Data(legacy.utf8)).container, .mov)
        let mp4 = MontageExportSettings(codec: .hevc, width: 1920, height: 1080, fps: 30, container: .mp4)
        XCTAssertEqual(try JSONDecoder().decode(MontageExportSettings.self, from: JSONEncoder().encode(mp4)), mp4)
        #if canImport(AVFoundation)
        XCTAssertEqual(MontageVideoContainer.mp4.fileType, .mp4)
        XCTAssertEqual(MontageVideoContainer.mov.fileType, .mov)
        #endif
    }

    /// «Cortar huecos» con tramos de 7,013 y 3,3371 s, sin fundidos globales: a 30 y a 29,97 fps, duraciones iguales a
    /// menos de medio fotograma y, en el corte interior, el audio funde (mezcla.wav y .mov).
    func testGateCutGapsRealMixerFadesAtCut() async throws {
        let dir = try TestWav.tempDir("MontageFrameGridTests")
        defer { try? FileManager.default.removeItem(at: dir) }
        let fx = try await Self.fixture(Self.cutSources(), dir: dir)
        let raw = MontagePlan.segments(presences: fx.parts.map(\.presence), imageStarts: fx.parts.map { $0.video?.take.start }, cutGaps: true)
        XCTAssertEqual(raw.count, 2)
        XCTAssertEqual(raw[0].duration, 7.013, accuracy: 1e-9)
        XCTAssertEqual(raw[1].duration, 3.3371, accuracy: 1e-9)
        var worst = 0.0
        for fps in [30.0, 29.97] {
            let name = String(format: "cortes-%.2f", fps)
            let r = try await Self.run(fx, segments: raw, fps: fps, fadeIn: false, fadeOut: false, name: name)
            XCTAssertEqual(r.plan.segments.count, 2)
            worst = max(worst, checkDurations(r, name))
            if fps == 30 { checkLoudness(r, name) }

            // Fundido en el corte: ventana corta justo antes y justo después frente a mitad de cada tramo.
            let cut = r.plan.timeMap.videoStarts[1]
            let d1 = r.plan.segments[0].duration, d2 = r.plan.segments[1].duration
            var lines: [String] = []
            for (src, d) in [("mezcla.wav", r.wav), (".mov", r.movAudio)] {
                let mid1 = Self.rmsDB(d, from: d1 / 2, length: Self.midWindow)
                let mid2 = Self.rmsDB(d, from: cut + d2 / 2, length: Self.midWindow)
                let before = Self.rmsDB(d, from: cut - Self.edgeWindow, length: Self.edgeWindow)
                let after = Self.rmsDB(d, from: cut, length: Self.edgeWindow)
                // Sin fundidos globales, el primer y el último borde no funden (solo los 80 ms de presencia de B).
                let head = Self.rmsDB(d, from: 0.1, length: Self.edgeWindow)
                lines.append(String(format: "%@: mitad %.1f / %.1f dBFS, antes del corte %.1f (%+.1f dB), después %.1f (%+.1f dB), inicio sin fundido %.1f",
                                    src, mid1, mid2, before, before - mid1, after, after - mid2, head))
                XCTAssertLessThan(before - mid1, Self.edgeMaxRatioDB, "\(name) \(src): antes del corte")
                XCTAssertLessThan(after - mid2, Self.edgeMaxRatioDB, "\(name) \(src): después del corte")
                XCTAssertGreaterThan(head - mid1, Self.edgeMaxRatioDB, "\(name) \(src): sin fundido global de entrada")
            }
            print("F7 corte \(name) (en \(String(format: "%.6f", cut)) s del vídeo): \(lines.joined(separator: "; "))")
        }
        print(String(format: "F7 cortes: máx |Δ duración| %.3f ms", worst * 1000))
    }
}
