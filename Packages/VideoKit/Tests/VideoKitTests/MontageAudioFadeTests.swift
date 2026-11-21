import AudioKit
#if canImport(AVFoundation)
import AVFoundation
#endif
import XCTest
@testable import VideoKit
import struct VideoKit.MontageSpan

/// Fundido de 80 ms de cada parte (mini-spec Fase 7, «Transiciones»): la vista previa (`AVAudioMix` de
/// `MontageBuilder`) frente a la exportación (`MontageMixer` de AudioKit, la referencia), medidos los dos sobre una
/// señal continua (DC) renderizada de verdad, muestra a muestra.
final class MontageAudioFadeTests: XCTestCase {
    static let fs = 48_000.0
    static let level: Float = 0.5
    /// Tramos de presencia (s del tema): dos normales y uno de 100 ms, más corto que los dos fundidos juntos.
    static let spans = [MontageSpan(start: 4, end: 5), MontageSpan(start: 6, end: 6.1), MontageSpan(start: 7.5, end: 8.5)]
    static let span = MontageSpan(start: 2, end: 10)
    /// Error de ganancia admitido entre las dos curvas (fracción del valor pleno). La cota de la interpolación con
    /// 16 rampas es π²/(16·16²) ≈ 0,0024; se deja margen para el redondeo del mezclador de AVFoundation.
    static let maxGainError = 0.005
    /// Error admitido en dB donde la referencia está por encima de −30 dB.
    static let maxDBError = 0.5
    static let dbFloor = -30.0

    #if canImport(AVFoundation)
    /// Ganancia aplicada por la exportación, muestra a muestra desde `span.start`.
    static func exportGain(_ dc: URL, presence: MontagePresence, dir: URL) async throws -> [Double] {
        let out = dir.appendingPathComponent("export-\(UUID().uuidString).wav")
        let job = MontageMixJob(start: span.start, end: span.end, sampleRate: fs,
                                tracks: [MontageTrack(id: "C", url: dc, songStart: span.start, group: .part("C"), presence: presence)],
                                normalization: .none, mixURL: out)
        _ = try await MontageMixer.mix(job)
        return try TestWav.readFirst(out).map { Double($0 / level) }
    }

    /// Ganancia aplicada por la vista previa: la composición del montaje con su `AVAudioMix`, leída con
    /// `AVAssetReaderAudioMixOutput` (el mismo mezclador que usa `AVPlayer`).
    static func previewGain(_ dc: URL, gate: MontageAudioGate, part: MontagePart) async throws -> [Double] {
        let plan = MontagePlan(canvas: .landscape, fps: 30, layout: .side, span: span, barDuration: 1, fadeIn: false, fadeOut: false,
                               parts: [part], audio: [MontageAudioTrack(url: dc, songStart: span.start, volume: 1, gate: gate)])
        let preview = try await MontageBuilder.load(plan).make(renderSize: CGSize(width: 320, height: 180))
        let tracks = try await preview.composition.loadTracks(withMediaType: .audio)
        XCTAssertEqual(tracks.count, 1)
        let reader = try AVAssetReader(asset: preview.composition)
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: fs, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        output.audioMix = preview.audioMix
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var left: [Double] = []
        while let s = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(s) else { continue }
            let bytes = CMBlockBufferGetDataLength(block)
            var raw = [Float](repeating: 0, count: bytes / 4)
            _ = raw.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes, destination: $0.baseAddress!) }
            for i in stride(from: 0, to: raw.count, by: 2) { left.append(Double(raw[i] / level)) }
        }
        XCTAssertEqual(reader.status, .completed)
        return left
    }
    #endif

    /// Curva lineal (trapecio) que usaba la vista previa antes: sirve para dar la diferencia que había.
    static func linear(_ t: Double) -> Double {
        let f = MontageStyle.audioFade
        return spans.reduce(0) { max($0, min(max(min((t - $1.start) / f, ($1.end - t) / f, 1), 0), 1)) }
    }

    struct Diff {
        var maxAbs = 0.0, maxDB = 0.0, atAbs = 0.0, atDB = 0.0
        mutating func add(_ a: Double, _ ref: Double, t: Double) {
            let e = abs(a - ref)
            if e > maxAbs { maxAbs = e; atAbs = t }
            guard ref > pow(10, MontageAudioFadeTests.dbFloor / 20) else { return }
            let d = abs(20 * log10(max(a, 1e-9) / ref))
            if d > maxDB { maxDB = d; atDB = t }
        }
    }

    #if !canImport(AVFoundation)
    // Windows (parte 7.9): la vista previa no tiene mezclador de AVFoundation; su envolvente es `MontagePreviewAudio`
    // (los mismos vértices y rampas lineales que el `AVAudioMix`), aplicada muestra a muestra a la señal continua.
    static func previewGain(_ preview: MontagePreview, samples: Int) throws -> [Double] {
        XCTAssertEqual(preview.audioTracks.count, 1)
        let a = try XCTUnwrap(preview.audioTracks.first)
        return (0..<samples).map { n in
            let v = Double(n) / fs
            return a.fileTime(atVideoTime: v) == nil ? 0 : Double(Float(a.gain(atVideoTime: v)))
        }
    }

    func testPreviewFadeFollowsExportCurve() async throws {
        let dir = try TestWav.tempDir("MontageAudioFadeTests")
        defer { try? FileManager.default.removeItem(at: dir) }
        let dc = dir.appendingPathComponent("dc.wav")
        let samples = [Float](repeating: Self.level, count: Int(Self.span.duration * Self.fs))
        try TestWav.write([samples, samples], sampleRate: Self.fs, to: dc)
        let video = dir.appendingPathComponent("A.mov")
        _ = try await VideoFileTests.writeVideo(video, start: Self.span.start, seconds: Self.span.duration, color: (0, 0, 255))
        let part = MontagePart(id: "A", name: "Rítmica 1", isSolo: false, presence: [Self.span],
                               video: MontagePartVideo(url: video, videoOffset: 0, take: Self.span))
        let audioSpans = Self.spans.map { AudioKit.MontageSpan(start: $0.start, end: $0.end) }
        for (name, gate, presence, inverse) in [("toma", MontageAudioGate.during(Self.spans), MontagePresence.audible(audioSpans), false),
                                                ("original", .except(Self.spans), .silenced(audioSpans), true)] {
            let out = dir.appendingPathComponent("export-\(UUID().uuidString).wav")
            let job = MontageMixJob(start: Self.span.start, end: Self.span.end, sampleRate: Self.fs,
                                    tracks: [MontageTrack(id: "C", url: dc, songStart: Self.span.start, group: .part("C"), presence: presence)],
                                    normalization: .none, mixURL: out)
            _ = try await MontageMixer.mix(job)
            let ref = try TestWav.readFirst(out).map { Double($0 / Self.level) }
            let plan = MontagePlan(canvas: .landscape, fps: 30, layout: .side, span: Self.span, barDuration: 1, fadeIn: false, fadeOut: false,
                                   parts: [part], audio: [MontageAudioTrack(url: dc, songStart: Self.span.start, volume: 1, gate: gate)])
            let preview = try await MontageBuilder.load(plan).make(renderSize: CGSize(width: 320, height: 180))
            let got = try Self.previewGain(preview, samples: ref.count)
            var now = Diff(), before = Diff()
            for n in 0..<min(ref.count, got.count) {
                let t = Self.span.start + Double(n) / Self.fs
                now.add(got[n], ref[n], t: t)
                before.add(inverse ? 1 - Self.linear(t) : Self.linear(t), ref[n], t: t)
            }
            let mid = Int((4.04 - Self.span.start) * Self.fs)
            XCTAssertEqual(ref[mid], 0.5, accuracy: 1e-3, name)
            print(String(format: "7.9 fundido 80 ms (%@): vista previa − exportación máx |Δg| %.4f en %.4f s, máx %.3f dB en %.4f s; con la rampa lineal de antes: |Δg| %.4f, %.2f dB",
                         name, now.maxAbs, now.atAbs, now.maxDB, now.atDB, before.maxAbs, before.maxDB))
            XCTAssertLessThanOrEqual(now.maxAbs, Self.maxGainError, name)
            XCTAssertLessThanOrEqual(now.maxDB, Self.maxDBError, name)
        }
    }

    func testPreviewGlobalFadeFollowsExportCurve() async throws {
        let dir = try TestWav.tempDir("MontageAudioFadeTests")
        defer { try? FileManager.default.removeItem(at: dir) }
        let dc = dir.appendingPathComponent("dc.wav")
        let samples = [Float](repeating: Self.level, count: Int(14.0 * Self.fs))
        try TestWav.write([samples, samples], sampleRate: Self.fs, to: dc)
        let video = dir.appendingPathComponent("A.mov")
        _ = try await VideoFileTests.writeVideo(video, start: 2, seconds: 10, color: (0, 0, 255))
        let take = MontageSpan(start: 2, end: 12)
        let part = MontagePart(id: "A", name: "Rítmica 1", isSolo: false, presence: [take],
                               video: MontagePartVideo(url: video, videoOffset: 0, take: take))
        let audioEdges = Self.edgeSpans.map { AudioKit.MontageSpan(start: $0.start, end: $0.end) }
        for (name, gate, presence) in [("siempre", MontageAudioGate.always, MontagePresence.always),
                                       ("toma con bordes en los fundidos", .during(Self.edgeSpans), .audible(audioEdges))] {
            let out = dir.appendingPathComponent("export-\(UUID().uuidString).wav")
            let job = MontageMixJob(segments: Self.cutSegments.map { MontageSegment(start: $0.start, end: $0.end) }, sampleRate: Self.fs,
                                    tracks: [MontageTrack(id: "A", url: dc, songStart: 0, group: .part("A"), presence: presence)],
                                    fadeIn: Self.bar, fadeOut: Self.bar, normalization: .none, mixURL: out)
            _ = try await MontageMixer.mix(job)
            let ref = try TestWav.readFirst(out).map { Double($0 / Self.level) }
            let plan = MontagePlan(canvas: .landscape, fps: 30, layout: .side, segments: Self.cutSegments, barDuration: Self.bar,
                                   fadeIn: true, fadeOut: true, parts: [part], audio: [MontageAudioTrack(url: dc, songStart: 0, volume: 1, gate: gate)])
            XCTAssertEqual(plan.segments, Self.cutSegments)
            let preview = try await MontageBuilder.load(plan).make(renderSize: CGSize(width: 320, height: 180))
            let got = try Self.previewGain(preview, samples: ref.count)
            let tl = preview.timeline
            var now = Diff(), before = Diff()
            for n in 0..<min(ref.count, got.count) {
                let t = plan.songTime(videoTime: Double(n) / Self.fs)
                now.add(got[n], ref[n], t: t)
                before.add(MontageAudioEnvelope.gate(gate, at: t) * tl.globalFade(at: t), ref[n], t: t)
            }
            if case .always = gate {
                for (v, want) in [(1.0, 0.5), (4.0, 0.5), (6.0, 0.5), (8.0, 0.5)] {
                    XCTAssertEqual(ref[Int(v * Self.fs)], want, accuracy: 1e-3, "\(name) referencia en \(v) s del vídeo")
                }
            }
            print(String(format: "7.9 fundido global de %.0f s (%@): vista previa − exportación máx |Δg| %.4f en %.4f s, máx %.3f dB en %.4f s; con el lineal de antes: |Δg| %.4f, %.2f dB",
                         Self.bar, name, now.maxAbs, now.atAbs, now.maxDB, now.atDB, before.maxAbs, before.maxDB))
            XCTAssertLessThanOrEqual(now.maxAbs, Self.maxGainError, name)
            XCTAssertLessThanOrEqual(now.maxDB, Self.maxDBError, name)
        }
    }
    #else
    func testPreviewFadeFollowsExportCurve() async throws {
        let dir = try TestWav.tempDir("MontageAudioFadeTests")
        defer { try? FileManager.default.removeItem(at: dir) }
        let dc = dir.appendingPathComponent("dc.wav")
        let samples = [Float](repeating: Self.level, count: Int(Self.span.duration * Self.fs))
        try TestWav.write([samples, samples], sampleRate: Self.fs, to: dc)
        let video = dir.appendingPathComponent("A.mov")
        _ = try await VideoFileTests.writeVideo(video, start: Self.span.start, seconds: Self.span.duration, color: (0, 0, 255))
        let part = MontagePart(id: "A", name: "Rítmica 1", isSolo: false, presence: [Self.span],
                               video: MontagePartVideo(url: video, videoOffset: 0, take: Self.span))
        let audioSpans = Self.spans.map { AudioKit.MontageSpan(start: $0.start, end: $0.end) }

        for (name, gate, presence, inverse) in [("toma", MontageAudioGate.during(Self.spans), MontagePresence.audible(audioSpans), false),
                                                ("original", .except(Self.spans), .silenced(audioSpans), true)] {
            let ref = try await Self.exportGain(dc, presence: presence, dir: dir)
            let got = try await Self.previewGain(dc, gate: gate, part: part)
            XCTAssertGreaterThanOrEqual(got.count, ref.count - 1, name)
            var now = Diff(), before = Diff()
            for n in 0..<min(ref.count, got.count) {
                let t = Self.span.start + Double(n) / Self.fs
                now.add(got[n], ref[n], t: t)
                let lin = inverse ? 1 - Self.linear(t) : Self.linear(t)
                before.add(lin, ref[n], t: t)
            }
            // La exportación es seno al cuadrado: 0,5 en la mitad del fundido y pleno tras 80 ms.
            let mid = Int((4.04 - Self.span.start) * Self.fs)
            XCTAssertEqual(ref[mid], 0.5, accuracy: 1e-3, name)
            print(String(format: "F7 fundido 80 ms (%@): vista previa − exportación máx |Δg| %.4f en %.4f s, máx %.3f dB en %.4f s (ref ≥ %.0f dB); con la rampa lineal de antes: |Δg| %.4f en %.4f s, %.2f dB en %.4f s",
                         name, now.maxAbs, now.atAbs, now.maxDB, now.atDB, Self.dbFloor, before.maxAbs, before.atAbs, before.maxDB, before.atDB))
            XCTAssertLessThanOrEqual(now.maxAbs, Self.maxGainError, name)
            XCTAssertLessThanOrEqual(now.maxDB, Self.maxDBError, name)
        }
    }
    #endif

    // MARK: Fundido global de un compás

    /// Compás de 2 s y dos segmentos («Cortar huecos»): el primero entra y sale con un compás entero; el segundo, de
    /// 4 s, entra y sale con 2 s cada uno (se tocan en el centro y la curva es el producto).
    static let bar = 2.0
    static let cutSegments = [MontageSpan(start: 2, end: 7), MontageSpan(start: 8, end: 12)]
    /// Presencia de la toma con bordes en el inicio, en el corte y en el final: el fundido de 80 ms coincide con el
    /// global y la ganancia es el producto de los dos.
    static let edgeSpans = [MontageSpan(start: 2, end: 5), MontageSpan(start: 8, end: 12)]

    #if canImport(AVFoundation)
    func testPreviewGlobalFadeFollowsExportCurve() async throws {
        let dir = try TestWav.tempDir("MontageAudioFadeTests")
        defer { try? FileManager.default.removeItem(at: dir) }
        let song = 14.0
        let dc = dir.appendingPathComponent("dc.wav")
        let samples = [Float](repeating: Self.level, count: Int(song * Self.fs))
        try TestWav.write([samples, samples], sampleRate: Self.fs, to: dc)
        let video = dir.appendingPathComponent("A.mov")
        _ = try await VideoFileTests.writeVideo(video, start: 2, seconds: 10, color: (0, 0, 255))
        let take = MontageSpan(start: 2, end: 12)
        let part = MontagePart(id: "A", name: "Rítmica 1", isSolo: false, presence: [take],
                               video: MontagePartVideo(url: video, videoOffset: 0, take: take))
        let audioEdges = Self.edgeSpans.map { AudioKit.MontageSpan(start: $0.start, end: $0.end) }

        for (name, gate, presence) in [("siempre", MontageAudioGate.always, MontagePresence.always),
                                       ("toma con bordes en los fundidos", .during(Self.edgeSpans), .audible(audioEdges))] {
            // Exportación (referencia): los tramos del plan con fundido en los extremos y en el corte.
            let out = dir.appendingPathComponent("export-\(UUID().uuidString).wav")
            let job = MontageMixJob(segments: Self.cutSegments.map { MontageSegment(start: $0.start, end: $0.end) }, sampleRate: Self.fs,
                                    tracks: [MontageTrack(id: "A", url: dc, songStart: 0, group: .part("A"), presence: presence)],
                                    fadeIn: Self.bar, fadeOut: Self.bar, normalization: .none, mixURL: out)
            _ = try await MontageMixer.mix(job)
            let ref = try TestWav.readFirst(out).map { Double($0 / Self.level) }

            // Vista previa: misma composición y mismo `AVAudioMix` que el reproductor.
            let track = MontageAudioTrack(url: dc, songStart: 0, volume: 1, gate: gate)
            let plan = MontagePlan(canvas: .landscape, fps: 30, layout: .side, segments: Self.cutSegments, barDuration: Self.bar,
                                   fadeIn: true, fadeOut: true, parts: [part], audio: [track])
            XCTAssertEqual(plan.segments, Self.cutSegments)
            let preview = try await MontageBuilder.load(plan).make(renderSize: CGSize(width: 320, height: 180))
            let tracks = try await preview.composition.loadTracks(withMediaType: .audio)
            let reader = try AVAssetReader(asset: preview.composition)
            let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: Self.fs, AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ])
            output.audioMix = preview.audioMix
            reader.add(output)
            XCTAssertTrue(reader.startReading())
            var got: [Double] = []
            while let s = output.copyNextSampleBuffer() {
                guard let block = CMSampleBufferGetDataBuffer(s) else { continue }
                let bytes = CMBlockBufferGetDataLength(block)
                var raw = [Float](repeating: 0, count: bytes / 4)
                _ = raw.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes, destination: $0.baseAddress!) }
                for i in stride(from: 0, to: raw.count, by: 2) { got.append(Double(raw[i] / Self.level)) }
            }
            XCTAssertEqual(reader.status, .completed)
            XCTAssertGreaterThanOrEqual(got.count, ref.count - 1, name)

            // Antes: fundido global lineal (el de la imagen) por la compuerta.
            let tl = preview.timeline
            var now = Diff(), before = Diff()
            for n in 0..<min(ref.count, got.count) {
                let v = Double(n) / Self.fs
                let t = plan.songTime(videoTime: v)
                now.add(got[n], ref[n], t: t)
                before.add(MontageAudioEnvelope.gate(gate, at: t) * tl.globalFade(at: t), ref[n], t: t)
            }
            // Seno al cuadrado: 0,5 a mitad del compás de entrada (tema 3,0 s; vídeo 1,0 s) y del de salida del corte
            // (tema 6,0 s; vídeo 4,0 s); 0,5 también a mitad de la entrada del segundo (tema 9,0; vídeo 6,0).
            if case .always = gate {
                for (v, want) in [(1.0, 0.5), (4.0, 0.5), (6.0, 0.5), (8.0, 0.5)] {
                    XCTAssertEqual(ref[Int(v * Self.fs)], want, accuracy: 1e-3, "\(name) referencia en \(v) s del vídeo")
                }
            }
            print(String(format: "F7 fundido global de %.0f s (%@): vista previa − exportación máx |Δg| %.4f en %.4f s, máx %.3f dB en %.4f s (ref ≥ %.0f dB); con el lineal de antes: |Δg| %.4f en %.4f s, %.2f dB en %.4f s",
                         Self.bar, name, now.maxAbs, now.atAbs, now.maxDB, now.atDB, Self.dbFloor, before.maxAbs, before.atAbs, before.maxDB, before.atDB))
            XCTAssertLessThanOrEqual(now.maxAbs, Self.maxGainError, name)
            XCTAssertLessThanOrEqual(now.maxDB, Self.maxDBError, name)
        }
    }
    #endif

    /// Lo mismo sin AVFoundation para el fundido global: interpolación entre vértices frente a la curva, en los dos
    /// segmentos, sola y multiplicada por fundidos de 80 ms en los mismos bordes.
    func testGlobalFadeBreakpointsBoundInterpolationError() {
        let parts = [MontageTimeline.Part(id: "A", name: "A", isSolo: false, presence: [MontageSpan(start: 2, end: 12)], firstImage: 2,
                                          frameSize: CGSize(width: 320, height: 180))]
        let tl = MontageTimeline(canvas: MontageCanvas.landscape.size, layout: .side, span: MontageSpan(start: 2, end: 12),
                                 segments: Self.cutSegments, barDuration: Self.bar, fadeIn: true, fadeOut: true, parts: parts)
        let bound = Double.pi * Double.pi / (16 * Double(MontageAudioEnvelope.globalFadeSteps * MontageAudioEnvelope.globalFadeSteps))
        var line: [String] = []
        for (name, gate) in [("siempre", MontageAudioGate.always), ("bordes", .during(Self.edgeSpans))] {
            let track = MontageAudioTrack(url: URL(fileURLWithPath: "/dev/null"), songStart: 0, volume: 1, gate: gate)
            var worst = 0.0
            for k in 0..<Self.cutSegments.count {
                let bp = MontageAudioEnvelope.breakpoints(track, timeline: tl, segment: k)
                let end = Self.cutSegments[k].end
                for (a, b) in zip(bp, bp.dropFirst()) {
                    let ga = MontageAudioEnvelope.gain(track, at: a, timeline: tl)
                    let gb = MontageAudioEnvelope.gain(track, at: b == end ? b - 1e-9 : b, timeline: tl)
                    for i in 0...20 {
                        let t = a + (b - a) * Double(i) / 20
                        let e = abs(ga + (gb - ga) * Double(i) / 20 - MontageAudioEnvelope.gain(track, at: t == end ? t - 1e-9 : t, timeline: tl))
                        worst = max(worst, e)
                    }
                }
            }
            line.append(String(format: "%@ %.5f", name, worst))
            XCTAssertLessThanOrEqual(worst, bound + 1e-9, name)
        }
        print(String(format: "F7 rampas del fundido global (%d por compás): error de interpolación máx %@ (cota %.5f)",
                     MontageAudioEnvelope.globalFadeSteps, line.joined(separator: ", "), bound))
    }

    /// Cota teórica de la aproximación por rampas, sin AVFoundation: interpolación lineal entre los vértices de
    /// `breakpoints` frente a la curva de la compuerta (que es la de `MontageMixer`). En un fundido suelto,
    /// h²·max|g''|/8 = π²/(16·N²); en un tramo de menos de 160 ms la curva es el producto de las dos rampas y
    /// |g''| ≤ 3π²/2, así que la cota se triplica.
    func testBreakpointsBoundInterpolationError() {
        let parts = [MontageTimeline.Part(id: "A", name: "A", isSolo: false, presence: [Self.span], firstImage: 2,
                                          frameSize: CGSize(width: 320, height: 180))]
        let tl = MontageTimeline(canvas: MontageCanvas.landscape.size, layout: .side, span: Self.span, segments: [Self.span],
                                 barDuration: 1, fadeIn: false, fadeOut: false, parts: parts)
        let track = MontageAudioTrack(url: URL(fileURLWithPath: "/dev/null"), songStart: 2, volume: 1, gate: .during(Self.spans))
        let bp = MontageAudioEnvelope.breakpoints(track, timeline: tl, segment: 0)
        var worst = 0.0, worstShort = 0.0
        for (a, b) in zip(bp, bp.dropFirst()) {
            let ga = MontageAudioEnvelope.gain(track, at: a, timeline: tl), gb = MontageAudioEnvelope.gain(track, at: b, timeline: tl)
            let short = Self.spans.contains { $0.duration < 2 * MontageStyle.audioFade && a >= $0.start && b <= $0.end }
            for i in 0...20 {
                let t = a + (b - a) * Double(i) / 20
                let lerp = ga + (gb - ga) * Double(i) / 20
                let e = abs(lerp - MontageAudioEnvelope.gain(track, at: t, timeline: tl))
                if short { worstShort = max(worstShort, e) } else { worst = max(worst, e) }
            }
        }
        let bound = Double.pi * Double.pi / (16 * Double(MontageAudioEnvelope.fadeSteps * MontageAudioEnvelope.fadeSteps))
        print(String(format: "F7 rampas: %d vértices, error de interpolación máx %.5f (cota %.5f), en el tramo de 100 ms %.5f (cota %.5f)",
                     bp.count, worst, bound, worstShort, 3 * bound))
        XCTAssertLessThanOrEqual(worst, bound + 1e-9)
        XCTAssertLessThanOrEqual(worstShort, 3 * bound + 1e-9)
        XCTAssertGreaterThan(worstShort, 0, "el tramo corto se ha medido")
    }
}
