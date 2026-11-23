#if canImport(AVFoundation)
import AVFoundation
import XCTest
@testable import VideoKit

/// Puerta de la Fase 7 (mini-spec, «Pruebas»), sin hardware: tres tomas sintéticas de color liso (rítmica A roja
/// entera, rítmica B verde parcial, solista C azul con dos solos), exportadas en landscape (lado a lado, HEVC) y en
/// portrait (plano único, H.264).
final class MontageGateTests: XCTestCase {
    // Tiempos del tema (s). Compás de 1 s para que la suite sea corta.
    static let takeA = MontageSpan(start: 2, end: 10)
    static let takeB = MontageSpan(start: 2, end: 6)
    static let takeC = MontageSpan(start: 2, end: 10)
    static let solos = [MontageSpan(start: 4, end: 5), MontageSpan(start: 7.5, end: 8.5)]
    static let bar = 1.0
    static let fps = 30.0
    static let colors: [String: String] = ["A": "rojo", "B": "verde", "C": "azul"]
    /// Error admitido en el fundido global medido (fracción del valor pleno): 8 bits y compresión con pérdida.
    static let fadeTolerance = 0.03
    /// Diferencia admitida (niveles de 8 bits) entre el color de la toma y el del montaje leídos igual.
    static let colorTolerance = 6.0

    struct Fixture {
        let dir: URL
        let parts: [MontagePart]
        let mix: URL
        let span: MontageSpan

        func plan(_ layout: MontageLayoutKind, _ canvas: MontageCanvas) -> MontagePlan {
            let presC = parts[2].presence
            return MontagePlan(canvas: canvas, fps: MontageGateTests.fps, layout: layout, span: span, barDuration: MontageGateTests.bar,
                               fadeIn: true, fadeOut: true, parts: parts,
                               audio: [
                                   MontageAudioTrack(url: mix, songStart: 2, volume: 0.8, gate: .always),
                                   MontageAudioTrack(url: mix, songStart: 2, volume: 1, gate: .except(presC)),
                                   MontageAudioTrack(url: mix, songStart: 2, volume: 0.5, gate: .during(presC))
                               ],
                               caption: MontageCaption(title: "Tema de prueba", artist: "ToneForge"))
        }
    }

    static func fixture() async throws -> Fixture {
        let dir = try TestWav.tempDir("MontageGateTests")
        func video(_ name: String, _ span: MontageSpan, _ color: (b: UInt8, g: UInt8, r: UInt8)) async throws -> MontagePartVideo {
            let url = dir.appendingPathComponent("\(name).mov")
            _ = try await VideoFileTests.writeVideo(url, start: span.start, seconds: span.duration, color: color)
            return MontagePartVideo(url: url, videoOffset: 0, take: span)
        }
        let parts = [
            MontagePart(id: "A", name: "Rítmica 1", isSolo: false, presence: MontagePlan.presence(take: takeA, isSolo: false, soloSections: solos),
                        video: try await video("A", takeA, (0, 0, 255))),
            MontagePart(id: "B", name: "Rítmica 2", isSolo: false, presence: MontagePlan.presence(take: takeB, isSolo: false, soloSections: solos),
                        video: try await video("B", takeB, (0, 255, 0))),
            MontagePart(id: "C", name: "Solista", isSolo: true, presence: MontagePlan.presence(take: takeC, isSolo: true, soloSections: solos),
                        video: try await video("C", takeC, (255, 0, 0)))
        ]
        let span = try XCTUnwrap(MontagePlan.videoSpan(presences: parts.map(\.presence)))
        // Mezcla «ya normalizada» de AudioKit: un seno de 8 s.
        let fs = 48_000.0
        let sine = (0..<Int(span.duration * fs)).map { Float(0.3 * sin(2 * .pi * 440 * Double($0) / fs)) }
        let mix = dir.appendingPathComponent("mezcla.wav")
        try TestWav.write([sine, sine], sampleRate: fs, to: mix)
        return Fixture(dir: dir, parts: parts, mix: mix, span: span)
    }

    // MARK: Lectura de píxeles

    struct Frame {
        let px: [UInt8]
        let width: Int
        let height: Int

        /// Media RGB de un bloque de 5 × 5 alrededor de (x, y), origen arriba a la izquierda.
        func rgb(_ x: Double, _ y: Double) -> (Double, Double, Double) {
            var s = (0.0, 0.0, 0.0), n = 0.0
            for dy in -2...2 {
                for dx in -2...2 {
                    let xi = min(max(Int(x) + dx, 0), width - 1), yi = min(max(Int(y) + dy, 0), height - 1)
                    let o = (yi * width + xi) * 4
                    s.0 += Double(px[o]); s.1 += Double(px[o + 1]); s.2 += Double(px[o + 2]); n += 1
                }
            }
            return (s.0 / n, s.1 / n, s.2 / n)
        }
    }

    static func frame(_ gen: AVAssetImageGenerator, at t: Double) async throws -> Frame {
        let (img, _) = try await gen.image(at: VideoTakeWriter.time(t))
        let w = img.width, h = img.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return Frame(px: px, width: w, height: h)
    }

    /// Fotogramas del fichero exportado en los instantes `times` (s del vídeo), con `AVAssetReader` en BGRA: solo la
    /// matriz YCbCr → RGB, sin la conversión de color de `AVAssetImageGenerator` (BT.709 → sRGB sube un 50 % a 54 %).
    static func frames(_ url: URL, at times: [Double], fps: Double) async throws -> [Double: Frame] {
        let asset = AVURLAsset(url: url)
        let track = try await asset.loadTracks(withMediaType: .video).first!
        let reader = try AVAssetReader(asset: asset)
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(out)
        reader.startReading()
        var found: [Double: Frame] = [:]
        while let sb = out.copyNextSampleBuffer() {
            let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))
            guard let t = times.first(where: { abs($0 - pts) < 0.25 / fps }), let pb = CMSampleBufferGetImageBuffer(sb) else { continue }
            CVPixelBufferLockBaseAddress(pb, .readOnly)
            let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb), row = CVPixelBufferGetBytesPerRow(pb)
            let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
            var px = [UInt8](repeating: 0, count: w * h * 4)
            for y in 0..<h {
                for x in 0..<w {
                    let s = y * row + x * 4, d = (y * w + x) * 4
                    px[d] = base[s + 2]; px[d + 1] = base[s + 1]; px[d + 2] = base[s]; px[d + 3] = base[s + 3]
                }
            }
            CVPixelBufferUnlockBaseAddress(pb, .readOnly)
            found[t] = Frame(px: px, width: w, height: h)
        }
        return found
    }

    static func name(_ c: (Double, Double, Double)) -> String {
        let v = [c.0, c.1, c.2], m = v.max()!
        let second = v.sorted()[1]
        guard m >= 60, m - second >= 40 else { return "fondo" }
        return ["rojo", "verde", "azul"][v.firstIndex(of: m)!]
    }

    static func generator(_ asset: AVAsset, videoComposition: AVVideoComposition? = nil) -> AVAssetImageGenerator {
        let gen = AVAssetImageGenerator(asset: asset)
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        gen.videoComposition = videoComposition
        return gen
    }

    // MARK: Puerta

    /// Recuadros esperados por instante (spec, no el timeline): la solista solo en sus solos, ya en la primera nota;
    /// la parcial fuera al acabar su toma.
    static let expectSide: [(Double, [String])] = [
        (3.0, ["A", "B"]), (4.0, ["A", "B", "C"]), (4.6, ["A", "B", "C"]), (5.6, ["A", "B"]),
        (6.2, ["A", "B"]), (6.6, ["A"]), (8.0, ["A", "C"]), (9.2, ["A"])
    ]
    static let expectSingle: [(Double, [String])] = [
        (3.0, ["A"]), (3.8, ["A", "C"]), (4.0, ["C"]), (4.6, ["C"]), (5.6, ["A"]), (6.6, ["A"]), (8.0, ["C"]), (9.2, ["A"])
    ]

    func testGateExportsLandscapeAndPortrait() async throws {
        let fx = try await Self.fixture()
        defer { try? FileManager.default.removeItem(at: fx.dir) }
        XCTAssertEqual(fx.span, MontageSpan(start: 2, end: 10))
        XCTAssertEqual(fx.parts[2].presence, Self.solos)

        for (layout, canvas, settings, expect) in [
            (MontageLayoutKind.side, MontageCanvas.landscape, MontageExportSettings(codec: .hevc, width: 640, height: 360, fps: Self.fps), Self.expectSide),
            (MontageLayoutKind.single, MontageCanvas.portrait, MontageExportSettings(codec: .h264, width: 360, height: 640, fps: Self.fps), Self.expectSingle)
        ] {
            let plan = fx.plan(layout, canvas)
            let out = fx.dir.appendingPathComponent("montaje-\(layout.rawValue).mov")
            final class Progress: @unchecked Sendable { let lock = NSLock(); var values: [Double] = [] }
            let prog = Progress()
            let t0 = Date()
            let summary = try await MontageExporter.export(plan: plan, mixURL: fx.mix, settings: settings, to: out) { p in
                prog.lock.withLock { prog.values.append(p) }
            }
            let elapsed = Date().timeIntervalSince(t0)
            let progress = prog.lock.withLock { prog.values }
            XCTAssertFalse(FileManager.default.fileExists(atPath: out.deletingPathExtension().appendingPathExtension("partial.mov").path))

            // Dimensiones, fps, duración y audio.
            let asset = AVURLAsset(url: out)
            let vt = try await asset.loadTracks(withMediaType: .video)
            let at = try await asset.loadTracks(withMediaType: .audio)
            XCTAssertEqual(vt.count, 1)
            XCTAssertEqual(at.count, 1, "pista de audio")
            let (size, rate, vRange) = try await vt[0].load(.naturalSize, .nominalFrameRate, .timeRange)
            let codec = CMFormatDescriptionGetMediaSubType(try await vt[0].load(.formatDescriptions).first!)
            let aDesc = try await at[0].load(.formatDescriptions).first!
            let aRange = try await at[0].load(.timeRange)
            let duration = CMTimeGetSeconds(try await asset.load(.duration))
            let frames = try await VideoFileTests.ptsOf(out).count
            XCTAssertEqual(size, CGSize(width: settings.width, height: settings.height))
            XCTAssertEqual(codec, layout == .side ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264)
            XCTAssertEqual(Double(rate), Self.fps, accuracy: 0.01)
            XCTAssertEqual(frames, Int(fx.span.duration * Self.fps))
            XCTAssertEqual(summary.frames, frames)
            XCTAssertEqual(CMTimeGetSeconds(vRange.duration), fx.span.duration, accuracy: 1 / Self.fps)
            XCTAssertEqual(duration, fx.span.duration, accuracy: 0.05)
            XCTAssertEqual(CMFormatDescriptionGetMediaSubType(aDesc), kAudioFormatMPEG4AAC)
            XCTAssertEqual(CMTimeGetSeconds(aRange.duration), fx.span.duration, accuracy: 0.05)
            XCTAssertEqual(progress.last ?? 0, 1, accuracy: 1e-9)

            // Color en el centro de cada recuadro (centros del timeline, recuadros esperados de la spec).
            let timeline = MontageTimeline(plan: plan, images: Dictionary(uniqueKeysWithValues: fx.parts.map {
                ($0.id, (firstImage: $0.video!.take.start, frameSize: CGSize(width: 320, height: 180)))
            }))
            let fadeTimes: [(Double, Double)] = [(2.5, 0.5), (2.8, 0.8), (3.0, 1.0), (9.0, 1.0), (9.2, 0.8), (9.5, 0.5), (9.8, 0.2)]
            let songTimes = expect.map(\.0) + fadeTimes.map(\.0) + [3.5, 6.6, fx.span.start]
            let read = try await Self.frames(out, at: songTimes.map { $0 - fx.span.start }, fps: Self.fps)
            func frame(_ t: Double) throws -> Frame { try XCTUnwrap(read[t - fx.span.start], "fotograma en \(t)") }
            let k = Double(settings.width) / Double(canvas.width)
            var report: [String] = []
            for (t, ids) in expect {
                let st = timeline.state(at: t)
                XCTAssertEqual(st.boxes.map(\.partID), ids, "recuadros en \(t)")
                let f = try frame(t)
                var seen: [String] = []
                for b in st.boxes {
                    // En el fundido cruzado del plano único manda el de encima (el último).
                    if layout == .single && b.partID != st.boxes.last!.partID { continue }
                    let c = f.rgb(b.rect.midX * k, b.rect.midY * k)
                    seen.append("\(b.partID)=\(Self.name(c))")
                    XCTAssertEqual(Self.name(c), Self.colors[b.partID], "\(layout) t=\(t) \(b.partID) rgb=\(c)")
                }
                report.append("\(t): \(seen.joined(separator: " "))")
            }
            if layout == .side {
                // La parcial desaparece: donde estaba B se ve A.
                let lastB = try XCTUnwrap(timeline.state(at: 5.9).boxes.first { $0.partID == "B" })
                let f = try frame(6.6)
                XCTAssertEqual(Self.name(f.rgb(lastB.rect.midX * k, lastB.rect.midY * k)), "rojo", "B fuera a las 6,6 s")
            }

            // Fundidos de un compás: rojo de A en su centro frente al de 3,5 s (imagen entera).
            func red(_ t: Double) throws -> Double {
                let b = try XCTUnwrap(timeline.state(at: t).boxes.first { $0.partID == "A" })
                return try frame(t).rgb(b.rect.midX * k, b.rect.midY * k).0
            }
            let full = try red(3.5)
            let first = try frame(fx.span.start)
            let firstMax = first.px.enumerated().filter { $0.offset % 4 != 3 }.map { $0.element }.max() ?? 0
            var fades: [String] = []
            var worstFade = 0.0
            for (t, want) in fadeTimes {
                let got = try red(t) / full
                fades.append(String(format: "%.1f→%.3f", t, got))
                worstFade = max(worstFade, abs(got - want))
                XCTAssertEqual(got, want, accuracy: Self.fadeTolerance, "fundido en \(t)")
            }
            fades.append(String(format: "(máx |error| %.3f, rojo pleno %.1f)", worstFade, full))
            // Fidelidad: el rojo pleno del montaje frente al de la toma A leída igual.
            let src = try await Self.frames(fx.parts[0].video!.url!, at: [3.5], fps: Self.fps)
            let srcPx = try XCTUnwrap(src.values.first)
            let srcRGB = srcPx.rgb(Double(srcPx.width) / 2, Double(srcPx.height) / 2)
            let outB = try XCTUnwrap(timeline.state(at: 3.5).boxes.first { $0.partID == "A" })
            let outRGB = try frame(3.5).rgb(outB.rect.midX * k, outB.rect.midY * k)
            let colorError = max(abs(srcRGB.0 - outRGB.0), abs(srcRGB.1 - outRGB.1), abs(srcRGB.2 - outRGB.2))
            XCTAssertLessThanOrEqual(colorError, Self.colorTolerance, "color de la toma \(srcRGB) frente al montaje \(outRGB)")
            fades.append(String(format: "color toma (%.0f,%.0f,%.0f) montaje (%.0f,%.0f,%.0f)", srcRGB.0, srcRGB.1, srcRGB.2, outRGB.0, outRGB.1, outRGB.2))
            XCTAssertLessThanOrEqual(firstMax, 8, "primer fotograma negro")
            print(String(format: "F7 puerta %@ %d×%d %@: %d fotogramas a %.2f fps, %.3f s, audio %.3f s; exportado en %.2f s",
                         layout.rawValue, settings.width, settings.height, settings.codec.rawValue, frames, rate, duration,
                         CMTimeGetSeconds(aRange.duration), elapsed))
            print("F7 puerta \(layout.rawValue) colores: \(report.joined(separator: "; "))")
            print("F7 puerta \(layout.rawValue) fundidos (rojo/rojo pleno, esperado t−inicio y fin−t en compases): \(fades.joined(separator: " ")); primer fotograma máx \(firstMax)")
        }
    }

    /// Vista previa: mismo compositor sobre la composición (rejilla y apilado en `t` = 4,6 s) a resolución reducida,
    /// tiempo del item ↔ tema y mezcla con rampas de 80 ms.
    func testPreviewGridStackAndAudioMix() async throws {
        let fx = try await Self.fixture()
        defer { try? FileManager.default.removeItem(at: fx.dir) }
        for (layout, canvas) in [(MontageLayoutKind.grid, MontageCanvas.landscape), (.stack, .portrait)] {
            let plan = fx.plan(layout, canvas)
            let builder = try await MontageBuilder.load(plan)
            let size = MontageBuilder.renderSize(canvas: canvas, maxDimension: 480)
            let preview = try builder.make(renderSize: size)
            XCTAssertEqual(CMTimeGetSeconds(preview.composition.duration), 8, accuracy: 1e-4)
            XCTAssertEqual(preview.songTime(itemTime: VideoTakeWriter.time(2.6)), 4.6, accuracy: 1e-6)
            XCTAssertEqual(CMTimeGetSeconds(preview.itemTime(songTime: 4.6)), 2.6, accuracy: 1e-6)
            let gen = Self.generator(preview.composition, videoComposition: preview.videoComposition)
            let f = try await Self.frame(gen, at: 2.6)
            XCTAssertEqual(f.width, Int(size.width))
            let k = size.width / CGFloat(canvas.width)
            let st = preview.timeline.state(at: 4.6)
            XCTAssertEqual(st.boxes.map(\.partID), ["A", "B", "C"])
            var seen: [String] = []
            for b in st.boxes {
                let c = f.rgb(b.rect.midX * k, b.rect.midY * k)
                seen.append(Self.name(c))
                XCTAssertEqual(Self.name(c), Self.colors[b.partID], "\(layout) \(b.partID)")
            }
            if layout == .grid {
                // 3 en rejilla: dos arriba y uno centrado abajo.
                XCTAssertEqual(st.boxes[2].rect.midX, CGFloat(canvas.width) / 2, accuracy: 1e-6)
                XCTAssertGreaterThan(st.boxes[2].rect.minY, st.boxes[0].rect.maxY)
            }
            print("F7 vista previa \(layout.rawValue) \(Int(size.width))×\(Int(size.height)) a 4,6 s: \(seen)")

            // Mezcla: tres pistas; la de la toma C sube en 80 ms desde el inicio del solo (4,0 s → 2,0 s del item),
            // en 16 rampas de 5 ms sobre el seno al cuadrado (la curva se compara en `MontageAudioFadeTests`).
            let params = try XCTUnwrap(preview.audioMix?.inputParameters)
            XCTAssertEqual(params.count, 3)
            var start: Float = -1, end: Float = -1
            var range = CMTimeRange.zero
            let step = MontageStyle.audioFade / Double(MontageAudioEnvelope.fadeSteps)
            let first = Float(MontageAudioEnvelope.ramp(1 / Double(MontageAudioEnvelope.fadeSteps)))
            XCTAssertTrue(params[2].getVolumeRamp(for: VideoTakeWriter.time(2.001), startVolume: &start, endVolume: &end, timeRange: &range))
            XCTAssertEqual(CMTimeGetSeconds(range.start), 2.0, accuracy: 1e-4)
            XCTAssertEqual(CMTimeGetSeconds(range.duration), step, accuracy: 1e-4)
            XCTAssertEqual(start, 0, accuracy: 1e-6)
            XCTAssertEqual(end, first * 0.5, accuracy: 1e-6)
            XCTAssertTrue(params[2].getVolumeRamp(for: VideoTakeWriter.time(2.04), startVolume: &start, endVolume: &end, timeRange: &range))
            XCTAssertEqual(CMTimeGetSeconds(range.start), 2.04, accuracy: 1e-4)
            XCTAssertEqual(start, 0.25, accuracy: 1e-6, "mitad del fundido: seno² = 0,5, por el volumen 0,5")
            // La guitarra original baja con el fundido inverso en el mismo tramo.
            XCTAssertTrue(params[1].getVolumeRamp(for: VideoTakeWriter.time(2.001), startVolume: &start, endVolume: &end, timeRange: &range))
            XCTAssertEqual(start, 1, accuracy: 1e-6)
            XCTAssertEqual(end, 1 - first, accuracy: 1e-6)
        }
    }

    /// «Cortar huecos sin tomas»: B (verde) en 2–5,5 s y la solista C (azul) en 7–9,5 s con imagen desde las 2 s → segmentos
    /// 2–5,5 y 6,5–9,5 (A entra 0,5 s antes). Duración = suma, color a los dos lados del corte, fundido de salida y de
    /// entrada en el corte, audio de la misma duración.
    func testGateTwoSegments() async throws {
        let fx = try await Self.fixture()
        defer { try? FileManager.default.removeItem(at: fx.dir) }
        // La segunda es la solista C (azul): su toma tiene imagen desde las 2 s, así que entra 0,5 s antes del solo.
        var b = fx.parts[1], a = fx.parts[2]
        b.presence = [MontageSpan(start: 2, end: 5.5)]
        b.video!.take = MontageSpan(start: 2, end: 5.5)
        a.presence = [MontageSpan(start: 7, end: 9.5)]
        let segments = MontagePlan.segments(presences: [b.presence, a.presence], imageStarts: [2, 2], cutGaps: true)
        XCTAssertEqual(segments, [MontageSpan(start: 2, end: 5.5), MontageSpan(start: 6.5, end: 9.5)])
        let plan = MontagePlan(canvas: .landscape, fps: Self.fps, layout: .side, segments: segments, barDuration: Self.bar, fadeIn: true,
                               fadeOut: true, parts: [b, a], audio: [MontageAudioTrack(url: fx.mix, songStart: 2, volume: 1, gate: .always)])
        XCTAssertEqual(plan.videoDuration, 6.5)
        let mix = fx.dir.appendingPathComponent("mezcla-cortes.wav")
        let fs = 48_000.0
        let sine = (0..<Int(plan.videoDuration * fs)).map { Float(0.3 * sin(2 * .pi * 440 * Double($0) / fs)) }
        try TestWav.write([sine, sine], sampleRate: fs, to: mix)
        let out = fx.dir.appendingPathComponent("cortes.mov")
        let summary = try await MontageExporter.export(plan: plan, mixURL: mix, settings: MontageExportSettings(codec: .hevc, width: 640, height: 360, fps: Self.fps), to: out)
        let asset = AVURLAsset(url: out)
        let duration = CMTimeGetSeconds(try await asset.load(.duration))
        let at = try await asset.loadTracks(withMediaType: .audio)
        let aDur = CMTimeGetSeconds(try await at.first!.load(.timeRange).duration)
        let frames = try await VideoFileTests.ptsOf(out).count
        XCTAssertEqual(frames, 195)
        XCTAssertEqual(summary.frames, 195)
        XCTAssertEqual(duration, 6.5, accuracy: 0.05)
        XCTAssertEqual(aDur, 6.5, accuracy: 0.05)

        // Vídeo: 2,0 s = tema 4,0 (B); 5,0 s = tema 8,0 (A); el corte está en 3,5 s.
        let videoTimes = [2.0, 3.0, 104.0 / 30, 3.5, 4.0, 5.0]
        let read = try await Self.frames(out, at: videoTimes, fps: Self.fps)
        let k = 640.0 / 1920
        let center = (960.0 * k, 540.0 * k)
        func px(_ v: Double) throws -> (Double, Double, Double) { try XCTUnwrap(read[v], "fotograma \(v)").rgb(center.0, center.1) }
        XCTAssertEqual(Self.name(try px(2.0)), "verde")
        XCTAssertEqual(Self.name(try px(5.0)), "azul")
        let fullG = try px(2.0).1, fullR = try px(5.0).2
        let outFade = try px(3.0).1 / fullG      // tema 5,0: 0,5 s antes del corte
        let lastBefore = try px(104.0 / 30).1 / fullG
        let firstAfter = try px(3.5).2 / fullR   // tema 6,5: empieza el segundo segmento
        let inFade = try px(4.0).2 / fullR       // tema 7,0
        XCTAssertEqual(outFade, 0.5, accuracy: Self.fadeTolerance)
        XCTAssertEqual(inFade, 0.5, accuracy: Self.fadeTolerance)
        XCTAssertLessThan(lastBefore, 0.06)
        XCTAssertLessThan(firstAfter, 0.03)

        // Vista previa: conversión de tiempos con el hueco.
        let preview = try await MontageBuilder.load(plan).make(renderSize: CGSize(width: 320, height: 180))
        XCTAssertEqual(CMTimeGetSeconds(preview.composition.duration), 6.5, accuracy: 1e-4)
        XCTAssertEqual(CMTimeGetSeconds(preview.itemTime(songTime: 6.0)), 3.5, accuracy: 1e-6)
        XCTAssertEqual(preview.songTime(itemTime: VideoTakeWriter.time(3.5)), 6.5, accuracy: 1e-6)
        print(String(format: "F7 dos segmentos: %d fotogramas, %.3f s (3,5 + 3,0), audio %.3f s; verde %.0f / azul %.0f; fundido de salida %.3f a 0,5 s del corte, %.3f en el último fotograma; entrada %.3f en el primero y %.3f a 0,5 s",
                     frames, duration, aDur, fullG, fullR, outFade, lastBefore, firstAfter, inFade))
    }

    /// Cancelar a mitad borra el parcial y deja intacto el vídeo anterior del mismo layout.
    func testCancelRemovesPartialAndKeepsPrevious() async throws {
        let fx = try await Self.fixture()
        defer { try? FileManager.default.removeItem(at: fx.dir) }
        let out = fx.dir.appendingPathComponent("montaje.mov")
        try Data("anterior".utf8).write(to: out)
        let plan = fx.plan(.side, .landscape)
        final class Flag: @unchecked Sendable { let lock = NSLock(); var max = 0.0 }
        let flag = Flag()
        let task = Task {
            try await MontageExporter.export(plan: plan, mixURL: fx.mix, settings: MontageExportSettings(codec: .hevc, width: 640, height: 360, fps: 30),
                                             to: out) { p in flag.lock.withLock { flag.max = max(flag.max, p) } }
        }
        while flag.lock.withLock({ flag.max }) < 0.2 { try await Task.sleep(nanoseconds: 5_000_000) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("debía cancelarse")
        } catch is CancellationError {
        } catch { XCTFail("error inesperado \(error)") }
        let partial = out.deletingPathExtension().appendingPathExtension("partial.mov")
        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
        XCTAssertEqual(try String(contentsOf: out, encoding: .utf8), "anterior")
        print(String(format: "F7 cancelar: al %.0f %%, parcial borrado, anterior intacto", flag.lock.withLock { flag.max } * 100))
    }
}
#else
import Foundation
import XCTest
@testable import VideoKit

/// Windows (parte 7.9): la misma puerta con el lector de Media Foundation, el compositor Direct2D y el mux de Media
/// Foundation. Los ficheros se leen con `MediaFoundationReader` (BT.709 → BGRA, la misma matriz del escritor).
final class MontageGateTests: XCTestCase {
    static let takeA = MontageSpan(start: 2, end: 10)
    static let takeB = MontageSpan(start: 2, end: 6)
    static let takeC = MontageSpan(start: 2, end: 10)
    static let solos = [MontageSpan(start: 4, end: 5), MontageSpan(start: 7.5, end: 8.5)]
    static let bar = 1.0
    static let fps = 30.0
    static let colors: [String: String] = ["A": "rojo", "B": "verde", "C": "azul"]
    static let fadeTolerance = 0.03
    static let colorTolerance = 6.0

    struct Fixture {
        let dir: URL
        let parts: [MontagePart]
        let mix: URL
        let span: MontageSpan

        func plan(_ layout: MontageLayoutKind, _ canvas: MontageCanvas) -> MontagePlan {
            let presC = parts[2].presence
            return MontagePlan(canvas: canvas, fps: MontageGateTests.fps, layout: layout, span: span, barDuration: MontageGateTests.bar,
                               fadeIn: true, fadeOut: true, parts: parts,
                               audio: [
                                   MontageAudioTrack(url: mix, songStart: 2, volume: 0.8, gate: .always),
                                   MontageAudioTrack(url: mix, songStart: 2, volume: 1, gate: .except(presC)),
                                   MontageAudioTrack(url: mix, songStart: 2, volume: 0.5, gate: .during(presC))
                               ],
                               caption: MontageCaption(title: "Tema de prueba", artist: "ToneForge"))
        }
    }

    static func fixture() async throws -> Fixture {
        let dir = try TestWav.tempDir("MontageGateTests")
        func video(_ name: String, _ span: MontageSpan, _ color: (b: UInt8, g: UInt8, r: UInt8)) async throws -> MontagePartVideo {
            let url = dir.appendingPathComponent("\(name).mov")
            _ = try await VideoFileTests.writeVideo(url, start: span.start, seconds: span.duration, color: color)
            return MontagePartVideo(url: url, videoOffset: 0, take: span)
        }
        let parts = [
            MontagePart(id: "A", name: "Rítmica 1", isSolo: false, presence: MontagePlan.presence(take: takeA, isSolo: false, soloSections: solos),
                        video: try await video("A", takeA, (0, 0, 255))),
            MontagePart(id: "B", name: "Rítmica 2", isSolo: false, presence: MontagePlan.presence(take: takeB, isSolo: false, soloSections: solos),
                        video: try await video("B", takeB, (0, 255, 0))),
            MontagePart(id: "C", name: "Solista", isSolo: true, presence: MontagePlan.presence(take: takeC, isSolo: true, soloSections: solos),
                        video: try await video("C", takeC, (255, 0, 0)))
        ]
        let span = try XCTUnwrap(MontagePlan.videoSpan(presences: parts.map(\.presence)))
        let fs = 48_000.0
        let sine = (0..<Int(span.duration * fs)).map { Float(0.3 * sin(2 * .pi * 440 * Double($0) / fs)) }
        let mix = dir.appendingPathComponent("mezcla.wav")
        try TestWav.write([sine, sine], sampleRate: fs, to: mix)
        return Fixture(dir: dir, parts: parts, mix: mix, span: span)
    }

    struct Frame {
        let px: [UInt8]
        let width: Int
        let height: Int

        init(px: [UInt8], width: Int, height: Int) {
            self.px = px
            self.width = width
            self.height = height
        }

        init(_ pb: FramePixelBuffer) { self.init(px: RenderSupport.rgba(pb), width: pb.width, height: pb.height) }

        func rgb(_ x: Double, _ y: Double) -> (Double, Double, Double) {
            var s = (0.0, 0.0, 0.0), n = 0.0
            for dy in -2...2 {
                for dx in -2...2 {
                    let xi = min(max(Int(x) + dx, 0), width - 1), yi = min(max(Int(y) + dy, 0), height - 1)
                    let o = (yi * width + xi) * 4
                    s.0 += Double(px[o]); s.1 += Double(px[o + 1]); s.2 += Double(px[o + 2]); n += 1
                }
            }
            return (s.0 / n, s.1 / n, s.2 / n)
        }
    }

    /// Fotogramas del fichero en los instantes `times` (s del vídeo; el exportado empieza en 0 y no lleva lista).
    static func frames(_ url: URL, at times: [Double], fps: Double) throws -> [Double: Frame] {
        var found: [Double: Frame] = [:]
        try MediaFoundationReader.forEachFrame(url, format: .bgra) { pts, _, pb in
            if let t = times.first(where: { abs($0 - pts) < 0.25 / fps }) { found[t] = Frame(pb) }
            return true
        }
        return found
    }

    static func name(_ c: (Double, Double, Double)) -> String {
        let v = [c.0, c.1, c.2], m = v.max()!
        let second = v.sorted()[1]
        guard m >= 60, m - second >= 40 else { return "fondo" }
        return ["rojo", "verde", "azul"][v.firstIndex(of: m)!]
    }

    static let expectSide: [(Double, [String])] = [
        (3.0, ["A", "B"]), (4.0, ["A", "B", "C"]), (4.6, ["A", "B", "C"]), (5.6, ["A", "B"]),
        (6.2, ["A", "B"]), (6.6, ["A"]), (8.0, ["A", "C"]), (9.2, ["A"])
    ]
    static let expectSingle: [(Double, [String])] = [
        (3.0, ["A"]), (3.8, ["A", "C"]), (4.0, ["C"]), (4.6, ["C"]), (5.6, ["A"]), (6.6, ["A"]), (8.0, ["C"]), (9.2, ["A"])
    ]

    func testGateExportsLandscapeAndPortrait() async throws {
        let fx = try await Self.fixture()
        defer { try? FileManager.default.removeItem(at: fx.dir) }
        XCTAssertEqual(fx.span, MontageSpan(start: 2, end: 10))
        for (layout, canvas, settings, expect) in [
            (MontageLayoutKind.side, MontageCanvas.landscape, MontageExportSettings(codec: .hevc, width: 640, height: 360, fps: Self.fps), Self.expectSide),
            (MontageLayoutKind.single, MontageCanvas.portrait, MontageExportSettings(codec: .h264, width: 360, height: 640, fps: Self.fps), Self.expectSingle)
        ] {
            let plan = fx.plan(layout, canvas)
            let out = fx.dir.appendingPathComponent("montaje-\(layout.rawValue).mov")
            final class Progress: @unchecked Sendable { let lock = NSLock(); var values: [Double] = [] }
            let prog = Progress()
            let t0 = Date()
            let summary = try await MontageExporter.export(plan: plan, mixURL: fx.mix, settings: settings, to: out) { p in
                prog.lock.withLock { prog.values.append(p) }
            }
            let elapsed = Date().timeIntervalSince(t0)
            XCTAssertFalse(FileManager.default.fileExists(atPath: out.deletingPathExtension().appendingPathExtension("partial.mov").path))
            let info = try MediaFoundationReader.info(out)
            let audio = try MediaFoundationReader.audio(out)
            var frames = 0
            try MediaFoundationReader.forEachFrame(out) { _, _, _ in frames += 1; return true }
            XCTAssertEqual([info.width, info.height], [settings.width, settings.height])
            XCTAssertEqual(info.videoCodec, summary.settings.codec == .hevc ? "HEVC" : "H264")
            XCTAssertEqual(info.fps, Self.fps, accuracy: 0.01)
            XCTAssertEqual(frames, Int(fx.span.duration * Self.fps))
            XCTAssertEqual(summary.frames, frames)
            XCTAssertTrue(info.hasAudio, "pista de audio")
            XCTAssertEqual(info.duration, fx.span.duration, accuracy: 0.05)
            XCTAssertEqual(Double(audio.channels[0].count) / audio.sampleRate, fx.span.duration, accuracy: 0.05)
            XCTAssertEqual(prog.lock.withLock { prog.values.last } ?? 0, 1, accuracy: 1e-9)

            let timeline = MontageTimeline(plan: plan, images: Dictionary(uniqueKeysWithValues: fx.parts.map {
                ($0.id, (firstImage: $0.video!.take.start, frameSize: CGSize(width: 320, height: 180)))
            }))
            let fadeTimes: [(Double, Double)] = [(2.5, 0.5), (2.8, 0.8), (3.0, 1.0), (9.0, 1.0), (9.2, 0.8), (9.5, 0.5), (9.8, 0.2)]
            let songTimes = expect.map(\.0) + fadeTimes.map(\.0) + [3.5, 6.6, fx.span.start]
            let read = try Self.frames(out, at: songTimes.map { $0 - fx.span.start }, fps: Self.fps)
            func frame(_ t: Double) throws -> Frame { try XCTUnwrap(read[t - fx.span.start], "fotograma en \(t)") }
            let k = Double(settings.width) / Double(canvas.width)
            var report: [String] = []
            for (t, ids) in expect {
                let st = timeline.state(at: t)
                XCTAssertEqual(st.boxes.map(\.partID), ids, "recuadros en \(t)")
                let f = try frame(t)
                var seen: [String] = []
                for b in st.boxes {
                    if layout == .single && b.partID != st.boxes.last!.partID { continue }
                    let c = f.rgb(b.rect.midX * k, b.rect.midY * k)
                    seen.append("\(b.partID)=\(Self.name(c))")
                    XCTAssertEqual(Self.name(c), Self.colors[b.partID], "\(layout) t=\(t) \(b.partID) rgb=\(c)")
                }
                report.append("\(t): \(seen.joined(separator: " "))")
            }
            if layout == .side {
                let lastB = try XCTUnwrap(timeline.state(at: 5.9).boxes.first { $0.partID == "B" })
                XCTAssertEqual(Self.name(try frame(6.6).rgb(lastB.rect.midX * k, lastB.rect.midY * k)), "rojo", "B fuera a las 6,6 s")
            }
            func red(_ t: Double) throws -> Double {
                let b = try XCTUnwrap(timeline.state(at: t).boxes.first { $0.partID == "A" })
                return try frame(t).rgb(b.rect.midX * k, b.rect.midY * k).0
            }
            let full = try red(3.5)
            let first = try frame(fx.span.start)
            let firstMax = first.px.enumerated().filter { $0.offset % 4 != 3 }.map { $0.element }.max() ?? 0
            var fades: [String] = []
            var worstFade = 0.0
            for (t, want) in fadeTimes {
                let got = try red(t) / full
                fades.append(String(format: "%.1f→%.3f", t, got))
                worstFade = max(worstFade, abs(got - want))
                XCTAssertEqual(got, want, accuracy: Self.fadeTolerance, "fundido en \(t)")
            }
            // La toma lleva lista de ediciones y Media Foundation la aplica: su marca es el tiempo del tema.
            let src = try Self.frames(fx.parts[0].video!.url!, at: [fx.parts[0].video!.take.start + 1.5], fps: Self.fps)
            let srcPx = try XCTUnwrap(src.values.first, "fotograma de la toma A")
            let srcRGB = srcPx.rgb(Double(srcPx.width) / 2, Double(srcPx.height) / 2)
            let outB = try XCTUnwrap(timeline.state(at: 3.5).boxes.first { $0.partID == "A" })
            let outRGB = try frame(3.5).rgb(outB.rect.midX * k, outB.rect.midY * k)
            let colorError = max(abs(srcRGB.0 - outRGB.0), abs(srcRGB.1 - outRGB.1), abs(srcRGB.2 - outRGB.2))
            XCTAssertLessThanOrEqual(colorError, Self.colorTolerance, "color de la toma \(srcRGB) frente al montaje \(outRGB)")
            XCTAssertLessThanOrEqual(firstMax, 8, "primer fotograma negro")
            // MP4 entero para el juicio visual de Jorge.
            let check = RenderSupport.repo.appendingPathComponent("Temp/win/listen/CHECK_d2d_export_\(layout.rawValue).mp4")
            try? FileManager.default.removeItem(at: check)
            try FileManager.default.copyItem(at: out, to: check)
            print(String(format: "7.9 puerta %@ %d×%d %@: %d fotogramas, %.3f s, audio %.3f s; exportado en %.2f s (%.1f ms por fotograma); fundidos máx |error| %.3f; color toma (%.0f,%.0f,%.0f) montaje (%.0f,%.0f,%.0f); primer fotograma máx %d",
                         layout.rawValue, settings.width, settings.height, summary.settings.codec.rawValue, frames, info.duration,
                         Double(audio.channels[0].count) / audio.sampleRate, elapsed, elapsed / Double(max(1, frames)) * 1000, worstFade,
                         srcRGB.0, srcRGB.1, srcRGB.2, outRGB.0, outRGB.1, outRGB.2, Int(firstMax)))
            print("7.9 puerta \(layout.rawValue) colores: \(report.joined(separator: "; ")); fundidos \(fades.joined(separator: " "))")
        }
    }

    /// Vista previa: el mismo compositor a resolución reducida, tiempo del vídeo ↔ tema y la mezcla con rampas de 80 ms.
    func testPreviewGridStackAndAudioMix() async throws {
        let fx = try await Self.fixture()
        defer { try? FileManager.default.removeItem(at: fx.dir) }
        for (layout, canvas) in [(MontageLayoutKind.grid, MontageCanvas.landscape), (.stack, .portrait)] {
            let plan = fx.plan(layout, canvas)
            let builder = try await MontageBuilder.load(plan)
            let size = MontageBuilder.renderSize(canvas: canvas, maxDimension: 480)
            let preview = try builder.make(renderSize: size)
            XCTAssertEqual(preview.duration, 8, accuracy: 1e-4)
            XCTAssertEqual(preview.songTime(videoTime: 2.6), 4.6, accuracy: 1e-6)
            XCTAssertEqual(preview.videoTime(songTime: 4.6), 2.6, accuracy: 1e-6)
            let f = Frame(try preview.frame(at: 2.6))
            XCTAssertEqual(f.width, Int(size.width))
            let k = size.width / CGFloat(canvas.width)
            let st = preview.timeline.state(at: 4.6)
            XCTAssertEqual(st.boxes.map(\.partID), ["A", "B", "C"])
            var seen: [String] = []
            for b in st.boxes {
                let c = f.rgb(b.rect.midX * k, b.rect.midY * k)
                seen.append(Self.name(c))
                XCTAssertEqual(Self.name(c), Self.colors[b.partID], "\(layout) \(b.partID)")
            }
            if layout == .grid {
                XCTAssertEqual(st.boxes[2].rect.midX, CGFloat(canvas.width) / 2, accuracy: 1e-6)
                XCTAssertGreaterThan(st.boxes[2].rect.minY, st.boxes[0].rect.maxY)
            }
            print("7.9 vista previa \(layout.rawValue) \(Int(size.width))×\(Int(size.height)) a 4,6 s: \(seen)")
            // Mezcla: tres pistas; la de la toma C sube en 80 ms desde el inicio del solo (4,0 s → 2,0 s del vídeo).
            XCTAssertEqual(preview.audioTracks.count, 3)
            let step = MontageStyle.audioFade / Double(MontageAudioEnvelope.fadeSteps)
            let first = Double(Float(MontageAudioEnvelope.ramp(1 / Double(MontageAudioEnvelope.fadeSteps))))
            func ramp(_ track: Int, _ v: Double) throws -> MontagePreviewAudio.Ramp {
                try XCTUnwrap(preview.audioTracks[track].ramps.first { v >= $0.start && v < $0.end }, "rampa en \(v)")
            }
            var r = try ramp(2, 2.001)
            XCTAssertEqual(r.start, 2.0, accuracy: 1e-4)
            XCTAssertEqual(r.end - r.start, step, accuracy: 1e-4)
            XCTAssertEqual(r.from, 0, accuracy: 1e-6)
            XCTAssertEqual(r.to, first * 0.5, accuracy: 1e-6)
            r = try ramp(2, 2.04)
            XCTAssertEqual(r.start, 2.04, accuracy: 1e-4)
            XCTAssertEqual(r.from, 0.25, accuracy: 1e-6, "mitad del fundido: seno² = 0,5, por el volumen 0,5")
            r = try ramp(1, 2.001)
            XCTAssertEqual(r.from, 1, accuracy: 1e-6)
            XCTAssertEqual(r.to, 1 - first, accuracy: 1e-6)
        }
    }

    /// «Cortar huecos sin tomas»: dos segmentos, color a los dos lados del corte, fundidos en el corte y audio igual de largo.
    func testGateTwoSegments() async throws {
        let fx = try await Self.fixture()
        defer { try? FileManager.default.removeItem(at: fx.dir) }
        var b = fx.parts[1], a = fx.parts[2]
        b.presence = [MontageSpan(start: 2, end: 5.5)]
        b.video!.take = MontageSpan(start: 2, end: 5.5)
        a.presence = [MontageSpan(start: 7, end: 9.5)]
        let segments = MontagePlan.segments(presences: [b.presence, a.presence], imageStarts: [2, 2], cutGaps: true)
        XCTAssertEqual(segments, [MontageSpan(start: 2, end: 5.5), MontageSpan(start: 6.5, end: 9.5)])
        let plan = MontagePlan(canvas: .landscape, fps: Self.fps, layout: .side, segments: segments, barDuration: Self.bar, fadeIn: true,
                               fadeOut: true, parts: [b, a], audio: [MontageAudioTrack(url: fx.mix, songStart: 2, volume: 1, gate: .always)])
        XCTAssertEqual(plan.videoDuration, 6.5)
        let mix = fx.dir.appendingPathComponent("mezcla-cortes.wav")
        let fs = 48_000.0
        let sine = (0..<Int(plan.videoDuration * fs)).map { Float(0.3 * sin(2 * .pi * 440 * Double($0) / fs)) }
        try TestWav.write([sine, sine], sampleRate: fs, to: mix)
        let out = fx.dir.appendingPathComponent("cortes.mov")
        let summary = try await MontageExporter.export(plan: plan, mixURL: mix, settings: MontageExportSettings(codec: .hevc, width: 640, height: 360, fps: Self.fps), to: out)
        let info = try MediaFoundationReader.info(out)
        let audio = try MediaFoundationReader.audio(out)
        let aDur = Double(audio.channels[0].count) / audio.sampleRate
        var frames = 0
        try MediaFoundationReader.forEachFrame(out) { _, _, _ in frames += 1; return true }
        XCTAssertEqual(frames, 195)
        XCTAssertEqual(summary.frames, 195)
        XCTAssertEqual(info.duration, 6.5, accuracy: 0.05)
        XCTAssertEqual(aDur, 6.5, accuracy: 0.05)
        let videoTimes = [2.0, 3.0, 104.0 / 30, 3.5, 4.0, 5.0]
        let read = try Self.frames(out, at: videoTimes, fps: Self.fps)
        let k = 640.0 / 1920
        func px(_ v: Double) throws -> (Double, Double, Double) { try XCTUnwrap(read[v], "fotograma \(v)").rgb(960 * k, 540 * k) }
        XCTAssertEqual(Self.name(try px(2.0)), "verde")
        XCTAssertEqual(Self.name(try px(5.0)), "azul")
        let fullG = try px(2.0).1, fullR = try px(5.0).2
        let outFade = try px(3.0).1 / fullG
        let lastBefore = try px(104.0 / 30).1 / fullG
        let firstAfter = try px(3.5).2 / fullR
        let inFade = try px(4.0).2 / fullR
        XCTAssertEqual(outFade, 0.5, accuracy: Self.fadeTolerance)
        XCTAssertEqual(inFade, 0.5, accuracy: Self.fadeTolerance)
        XCTAssertLessThan(lastBefore, 0.06)
        XCTAssertLessThan(firstAfter, 0.03)
        let preview = try await MontageBuilder.load(plan).make(renderSize: CGSize(width: 320, height: 180))
        XCTAssertEqual(preview.duration, 6.5, accuracy: 1e-4)
        XCTAssertEqual(preview.videoTime(songTime: 6.0), 3.5, accuracy: 1e-6)
        XCTAssertEqual(preview.songTime(videoTime: 3.5), 6.5, accuracy: 1e-6)
        print(String(format: "7.9 dos segmentos: %d fotogramas, %.3f s, audio %.3f s; fundido de salida %.3f a 0,5 s del corte, %.3f en el último fotograma; entrada %.3f en el primero y %.3f a 0,5 s",
                     frames, info.duration, aDur, outFade, lastBefore, firstAfter, inFade))
    }

    func testCancelRemovesPartialAndKeepsPrevious() async throws {
        let fx = try await Self.fixture()
        defer { try? FileManager.default.removeItem(at: fx.dir) }
        let out = fx.dir.appendingPathComponent("montaje.mov")
        try Data("anterior".utf8).write(to: out)
        let plan = fx.plan(.side, .landscape)
        final class Flag: @unchecked Sendable { let lock = NSLock(); var max = 0.0 }
        let flag = Flag()
        let task = Task {
            try await MontageExporter.export(plan: plan, mixURL: fx.mix, settings: MontageExportSettings(codec: .hevc, width: 640, height: 360, fps: 30),
                                             to: out) { p in flag.lock.withLock { flag.max = max(flag.max, p) } }
        }
        while flag.lock.withLock({ flag.max }) < 0.2 { try await Task.sleep(nanoseconds: 5_000_000) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("debía cancelarse")
        } catch is CancellationError {
        } catch { XCTFail("error inesperado \(error)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.deletingPathExtension().appendingPathExtension("partial.mov").path))
        XCTAssertEqual(try String(contentsOf: out, encoding: .utf8), "anterior")
        print(String(format: "7.9 cancelar: al %.0f %%, parcial borrado, anterior intacto", flag.lock.withLock { flag.max } * 100))
    }
}
#endif // canImport(AVFoundation)
