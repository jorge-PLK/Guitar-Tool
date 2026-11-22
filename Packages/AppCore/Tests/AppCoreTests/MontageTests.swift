import Foundation
import Store
import XCTest
#if canImport(ImageIO)
import ImageIO
#endif
@testable import AppCore

/// Montaje (W2-M1): planificación, controlador con tomas sintéticas y compositor simulado, caché del WAV de la vista previa,
/// bucle de fotogramas, exportación cancelable y `montage.*` por el puente. Nada de hardware ni de audio real.
@MainActor
final class MontageTests: XCTestCase {
    final class FrameLog: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [(time: Double, pts: Double)] = []
        func add(_ pts: Double) { lock.withLock { items.append((ProcessInfo.processInfo.systemUptime, pts)) } }
        var all: [(time: Double, pts: Double)] { lock.withLock { items } }
        var count: Int { lock.withLock { items.count } }
        func clear() { lock.withLock { items = [] } }
    }

    struct Rig {
        var base: URL
        var root: URL
        var folder: URL
        var layout: ProjectLayout
        var project: Project
        var partIDs: [UUID]
        var takeIDs: [UUID]
    }

    static let songSeconds = 40.0

    /// Proyecto con dos stems, dos rítmicas (4-10 s y 14-20 s, con un hueco entre ellas) y una solista (toma 15-20, solo 16-18).
    func makeRig() throws -> Rig {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("montage-\(UUID().uuidString)", isDirectory: true)
        let root = base.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        var p = Project(song: Song(title: "Tema", artist: "Banda", source: "source/original.wav", sourceSHA256: "abc",
                                   sourceFormat: "wav", sourceSampleRate: StudyTests.sampleRate, sourceChannels: 2,
                                   sampleRate: StudyTests.sampleRate, duration: Self.songSeconds))
        p.separation = SeparationState(state: .done, model: "m", finishedAt: Date(timeIntervalSince1970: 1_700_000_000))
        p.stems = [Stem(kind: .bass, file: "stems/bass.wav"), Stem(kind: .drums, file: "stems/drums.wav")]
        p.sections = [Section(name: "Estrofa", start: 4, end: 16), Section(name: "Solo", start: 16, end: 18, solo: true)]
        let folder = root.appendingPathComponent("Banda - Tema", isDirectory: true)
        let layout = ProjectLayout(folder: folder)
        try layout.createSkeleton()
        try StudyTests.writeSine(layout.stemURL(.bass), frequency: 110, seconds: Self.songSeconds)
        try StudyTests.writeSine(layout.stemURL(.drums), frequency: 330, seconds: Self.songSeconds)

        var state = p.recordingOrInitial()
        state.parts = []
        var takes: [Take] = []
        let specs: [(String, GuitarRole, Double, Double, Double)] = [
            ("Rítmica 1", .rhythm, 4, 6, 220), ("Rítmica 2", .left, 14, 6, 262), ("Solo", .lead, 15, 5, 440)
        ]
        for (i, s) in specs.enumerated() {
            let id = UUID()
            try FileManager.default.createDirectory(at: layout.takeDirectory(takeId: id), withIntermediateDirectories: true)
            try StudyTests.writeSine(layout.processedURL(takeId: id), frequency: s.4, seconds: s.3)
            var take = Take(id: id, processedFile: ProjectLayout.processedRelativePath(takeId: id),
                            createdAt: Date().addingTimeInterval(Double(i)), songStart: s.2, sampleRate: StudyTests.sampleRate,
                            latencyCalibrated: true, videoFile: ProjectLayout.videoRelativePath(takeId: id), videoOffset: 0)
            var part = RecordingPart(name: s.0, replaces: s.1)
            part.addTake(id)
            take.partID = part.id
            takes.append(take)
            state.parts.append(part)
        }
        p.takes = takes
        p.recording = state
        try ProjectFile.save(p, to: folder)
        return Rig(base: base, root: root, folder: folder, layout: layout, project: p, partIDs: state.parts.map(\.id), takeIDs: takes.map(\.id))
    }

    func makeController(_ rig: Rig, services: MontageServices, timing: MontageController.Timing? = nil,
                        frames: FrameLog? = nil) throws -> MontageController {
        let project = try ProjectFile.load(folder: rig.folder)
        let session = StudySession(project: project, folder: rig.folder, store: FileStudyStore(folder: rig.folder))
        var t = timing ?? MontageController.Timing()
        if timing == nil { t.previewDebounce = 0.01; t.saveDelay = 0.05 }
        let c = MontageController(session: session, video: nil, store: FileMontageStore(folder: rig.folder), services: services,
                                  audio: ClockMontageAudio(), timing: t)
        if let frames { c.onPreviewFrame = { _, pts in frames.add(pts) } }
        return c
    }

    @discardableResult
    func waitUntil(_ timeout: Double = 8, _ cond: @escaping () -> Bool) async -> Bool {
        let end = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < end {
            if cond() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return cond()
    }

    func sleep(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9)) }

    func previewWAVs(_ rig: Rig) -> [String] {
        let dir = rig.layout.url(relative: MontageController.cacheFolder)
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasPrefix("preview-") }.sorted()
    }

    /// Abre y espera a tener vista previa y análisis listos.
    func openReady(_ c: MontageController) async {
        c.open()
        await waitUntil { c.previewPhase == .ready && c.audioPhase == .ready && !c.isAnalyzing }
    }

    // MARK: MontagePlanning

    func testLayoutsAndExportSizes() {
        XCTAssertFalse(MontagePlanning.isPortrait(.side))
        XCTAssertFalse(MontagePlanning.isPortrait(.grid))
        XCTAssertTrue(MontagePlanning.isPortrait(.stack))
        XCTAssertTrue(MontagePlanning.isPortrait(.single))
        XCTAssertFalse(MontagePlanning.isPortrait(.singleLandscape))
        let full = MontagePlanning.exportSize(.fullHD, kind: .side)
        XCTAssertEqual([full.width, full.height], [1920, 1080])
        let portrait = MontagePlanning.exportSize(.fullHD, kind: .stack)
        XCTAssertEqual([portrait.width, portrait.height], [1080, 1920])
        let hd = MontagePlanning.exportSize(.hd720, kind: .single)
        XCTAssertEqual([hd.width, hd.height], [720, 1280])
        XCTAssertEqual(MontagePlanning.previewMaxDimension, 640)
        XCTAssertEqual(MontagePlanning.linear(0), 1, accuracy: 1e-12)
        XCTAssertEqual(MontagePlanning.linear(-6.0206), 0.5, accuracy: 1e-4)
        XCTAssertTrue(MontagePlanning.planeShots(plan: nil).isEmpty)
        XCTAssertTrue(MontagePlanning.cutEligibleParts(plan: nil, at: 5).isEmpty)
    }

    func testDraftLanesOrderPresenceAndSegments() throws {
        let rig = try makeRig()
        let c = try makeController(rig, services: .simulated())
        XCTAssertEqual(c.lanes.map(\.partName), ["Rítmica 1", "Rítmica 2", "Solo"])
        XCTAssertEqual(c.lanes.map(\.isSolo), [false, false, true])
        XCTAssertEqual(c.lanes[0].presence, [LaneSpan(start: 4, end: 10)])
        // La solista solo está en el solo (16-18).
        XCTAssertEqual(c.lanes[2].presence.count, 1)
        XCTAssertEqual(c.lanes[2].presence[0].end, 18, accuracy: 1e-9)
        XCTAssertEqual(c.lanes[2].presence[0].start, 16, accuracy: 1e-9)
        XCTAssertEqual(c.span, LaneSpan(start: 4, end: 20))
        XCTAssertEqual(c.draft?.segments.count, 1)
        XCTAssertEqual(c.videoLanes.count, 3)
        XCTAssertTrue(c.draft?.missingParts.isEmpty ?? false)
        XCTAssertEqual(c.draft?.mixTracks.map(\.id).sorted().prefix(2), ["stem-bass", "stem-drums"])
        XCTAssertEqual(c.draft?.mixTracks.count, 5)
        // «Cortar huecos»: dos tramos, con fundidos en el corte.
        c.setCutGaps(true)
        XCTAssertEqual(c.draft?.segments.count, 2)
        XCTAssertEqual(c.draft?.segments.first?.fadeOut, true)
        XCTAssertEqual(c.draft?.segments.last?.fadeIn, true)
        // Orden y arrastre de carriles.
        c.moveLane(rig.partIDs[2], to: rig.partIDs[0])
        XCTAssertEqual(c.lanes.map(\.partName), ["Solo", "Rítmica 1", "Rítmica 2"])
        c.setPartOrder([rig.partIDs[1], rig.partIDs[0]])
        XCTAssertEqual(c.lanes.map(\.partName), ["Rítmica 2", "Rítmica 1", "Solo"])
        c.moveLane(rig.partIDs[0], to: rig.partIDs[0])   // sobre sí misma: nada
        XCTAssertEqual(c.lanes.map(\.partName), ["Rítmica 2", "Rítmica 1", "Solo"])
    }

    func testCutsPlaneAndRotation() throws {
        let rig = try makeRig()
        let c = try makeController(rig, services: .simulated())
        XCTAssertFalse(c.isSingleShot)
        c.setLayout(.single)
        XCTAssertTrue(c.isSingleShot)
        XCTAssertTrue(c.isPortrait)
        XCTAssertEqual(c.canvasLabel, "1080 × 1920")
        XCTAssertTrue(c.keepAspectApplies)
        c.setLayout(.side)
        XCTAssertFalse(c.keepAspectApplies)
        c.setLayout(.singleLandscape)
        XCTAssertEqual(c.canvasLabel, "1920 × 1080")
        let shots = c.planeShots
        XCTAssertFalse(shots.isEmpty)
        XCTAssertEqual(shots.first?.start ?? -1, c.span.start, accuracy: 1e-6)
        XCTAssertEqual(shots.last?.end ?? -1, c.span.end, accuracy: 1e-6)
        // Un corte a la solista (con imagen a las 17) cubre; uno a la rítmica 1 (su toma acabó a las 10) no.
        let a = c.addCut(at: 17, partID: rig.partIDs[2], exact: true)
        XCTAssertTrue(c.cutPartCovered(c.cuts[0]))
        c.setCutPart(a, rig.partIDs[0])
        XCTAssertFalse(c.cutPartCovered(c.cuts[0]))
        XCTAssertEqual(MontagePlanning.cutEligibleParts(plan: c.draft?.plan, at: 17), [rig.partIDs[1], rig.partIDs[2]])
        c.setCutPart(a, nil)   // un corte a «automático» sin cambio previo no cambia nada: desaparece
        XCTAssertTrue(c.cuts.isEmpty)
        // Un corte nuevo hereda la parte vigente; arrastrar respeta a los vecinos.
        let b = c.addCut(at: 12, partID: rig.partIDs[0], exact: true)
        let a2 = c.addCut(at: 17, partID: nil, exact: true)
        XCTAssertEqual(c.cuts.map(\.time), [12, 17])
        XCTAssertEqual(c.singlePart(at: 13), rig.partIDs[0])
        c.moveCut(b, to: 30)   // no pasa del vecino (17 − separación mínima)
        XCTAssertEqual(c.cuts.map(\.id), [b, a2])
        XCTAssertEqual(c.cuts.first?.time ?? 0, 17 - MontageController.minCutGap, accuracy: 1e-9)
        c.moveCut(a2, to: 30)   // el último llega al final del tramo
        XCTAssertEqual(c.cuts.last?.time ?? 0, c.span.end, accuracy: 1e-9)
        c.removeCut(a2)
        XCTAssertEqual(c.cuts.count, 1)
        c.clearCuts()
        XCTAssertTrue(c.cuts.isEmpty)
        // Rotación por toma (90° más cada vez) y de vuelta a 0 tras cuatro.
        XCTAssertEqual(c.rotation(takeID: rig.takeIDs[0]), 0)
        c.rotateTake(rig.takeIDs[0])
        XCTAssertEqual(c.rotation(takeID: rig.takeIDs[0]), 90)
        for _ in 0..<3 { c.rotateTake(rig.takeIDs[0]) }
        XCTAssertEqual(c.rotation(takeID: rig.takeIDs[0]), 0)
        XCTAssertEqual(c.barDuration, 2, accuracy: 1e-9)   // sin análisis: 120 BPM en 4/4
    }

    func testSettingsAreSavedInProjectJSON() async throws {
        let rig = try makeRig()
        let c = try makeController(rig, services: .simulated())
        c.setLayout(.grid)
        c.setCaption(false)
        c.setShowPartLabels(false)
        c.setKeepVideoAspect(true)
        c.updateExport { $0.fps = 25; $0.container = .mp4; $0.trackWAVs = false }
        c.updateFraming(rig.takeIDs[1]) { $0.mode = .follow; $0.followZoom = 1.5 }
        c.rotateTake(rig.takeIDs[0])
        await sleep(0.4)
        let saved = try ProjectFile.load(folder: rig.folder)
        let m = try XCTUnwrap(saved.montage)
        XCTAssertEqual(m.layout, .grid)
        XCTAssertFalse(m.caption)
        XCTAssertFalse(m.showPartLabels)
        XCTAssertTrue(m.keepVideoAspect)
        XCTAssertEqual(m.export.fps, 25)
        XCTAssertEqual(m.export.container, .mp4)
        XCTAssertEqual(m.framing[rig.takeIDs[1]]?.mode, .follow)
        XCTAssertEqual(m.framing[rig.takeIDs[1]]?.followZoom, 1.5)
        XCTAssertEqual(saved.takes.first { $0.id == rig.takeIDs[0] }?.rotationDegrees, 90)
        c.resetFraming(rig.takeIDs[1])
        XCTAssertEqual(c.framing(for: rig.takeIDs[1]).followZoom, TakeFraming.defaultFollowZoom)
        XCTAssertEqual(c.framing(for: rig.takeIDs[1]).mode, .follow)   // «Restablecer» conserva el modo
    }

    func testExportOptionsComeFromVideoKit() throws {
        let rig = try makeRig()
        let c = try makeController(rig, services: .simulated())
        XCTAssertFalse(c.codecOptions.isEmpty)
        XCTAssertTrue(c.codecOptions.contains(.h264))
        XCTAssertTrue(c.codecOptions.contains(c.effectiveCodec))
        XCTAssertFalse(c.containerOptions.isEmpty)
        #if os(Windows)
        XCTAssertEqual(c.codecOptions, [.h264])
        c.updateExport { $0.codec = .hevc }
        XCTAssertEqual(c.effectiveCodec, .h264)
        #endif
    }

    // MARK: Análisis de encuadre

    func testFramingAnalysisProgressAndCache() async throws {
        let rig = try makeRig()
        let counters = SimulatedMontageCounters()
        let c = try makeController(rig, services: .simulated(analysisMillis: 20, counters: counters))
        var seen: [Double] = []
        c.onFraming = { id in
            if id == rig.takeIDs[0], case .analyzing(let p)? = c.framingStatus[id] { seen.append(p) }
        }
        c.open()
        XCTAssertTrue(c.isAnalyzing)
        XCTAssertFalse(c.canExport)
        await waitUntil { !c.isAnalyzing }
        XCTAssertEqual(counters.analyses, 3)
        XCTAssertEqual(c.framingStatus[rig.takeIDs[0]], .ready(samples: 40, detected: 38))
        XCTAssertGreaterThan(seen.count, 1)
        XCTAssertEqual(seen, seen.sorted())
        XCTAssertTrue(FileManager.default.fileExists(atPath: rig.layout.framingCacheURL(takeId: rig.takeIDs[0]).path))
        XCTAssertNotNil(c.effectiveBox(takeID: rig.takeIDs[0], at: 5))
        XCTAssertTrue(c.canExport)
        // Segunda apertura: la caché vale (misma huella), no se vuelve a analizar.
        let again = SimulatedMontageCounters()
        let c2 = try makeController(rig, services: .simulated(counters: again))
        c2.open()
        await waitUntil { !c2.isAnalyzing }
        XCTAssertEqual(again.analyses, 0)
        XCTAssertEqual(c2.framingStatus[rig.takeIDs[0]], .ready(samples: 40, detected: 38))
        // «Reanalizar» borra la caché y vuelve a analizar solo esa toma.
        c2.reanalyze(rig.takeIDs[0])
        await waitUntil { !c2.isAnalyzing }
        XCTAssertEqual(again.analyses, 1)
        // «Rotar» rehace el análisis (la huella incluye el giro).
        c2.rotateTake(rig.takeIDs[1])
        await waitUntil { !c2.isAnalyzing && c2.framingStatus[rig.takeIDs[1]] != nil }
        XCTAssertEqual(again.analyses, 2)
        c.close()
        c2.close()
    }

    func testFramingFrameWritesPNG() async throws {
        let rig = try makeRig()
        let counters = SimulatedMontageCounters()
        let c = try makeController(rig, services: .simulated(counters: counters))
        let f = try await c.framingFrame(takeID: rig.takeIDs[0], at: 5)
        XCTAssertEqual(f.relativePath, "cache/montage/framing-\(rig.takeIDs[0].uuidString).png")
        XCTAssertEqual(counters.takeFrames, 1)
        let data = try Data(contentsOf: f.url)
        XCTAssertEqual(Array(data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        XCTAssertEqual([f.width, f.height], [64, 36])
        #if canImport(ImageIO)
        let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let img = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        XCTAssertEqual([img.width, img.height], [64, 36])
        #endif
        let second = try await c.framingFrame(takeID: rig.takeIDs[0], at: 6)
        XCTAssertGreaterThan(second.version, f.version)
        do { _ = try await c.framingFrame(takeID: UUID(), at: 5); XCTFail("debía fallar") } catch let e as RPCError {
            XCTAssertEqual(e.code, "not-found")
        }
    }

    func testPNGEncoderDownscalesAndChecksums() throws {
        let p = try XCTUnwrap(MontageFrameImage.solid(width: 200, height: 100, b: 1, g: 2, r: 3))
        let raw = try XCTUnwrap(MontageFrameImage.raw(p))
        XCTAssertEqual(raw.bytes[0], 1)
        XCTAssertEqual(raw.bytes[2], 3)
        let png = MontageFrameImage.png(raw, maxDimension: 50)
        #if canImport(ImageIO)
        let src = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let img = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        XCTAssertEqual([img.width, img.height], [50, 25])
        #endif
        XCTAssertEqual(MontageFrameImage.crc32(Data("123456789".utf8)), 0xCBF4_3926)
        XCTAssertEqual(MontageFrameImage.adler32(Array("Wikipedia".utf8)), 0x11E6_0398)
    }

    // MARK: Vista previa: WAV en caché

    func testPreviewWAVIsCachedAndInvalidated() async throws {
        let rig = try makeRig()
        let c = try makeController(rig, services: .simulated())
        XCTAssertEqual(c.previewPhase, .none)
        c.open()
        // Mientras se mezcla el WAV, la vista previa está «preparando» con el audio en «preparing».
        await waitUntil { c.previewPhase == .ready && c.audioPhase == .ready }
        XCTAssertEqual(c.previewMixCount, 1)
        let key1 = try XCTUnwrap(c.previewAudioKey)
        XCTAssertEqual(previewWAVs(rig), ["preview-\(key1).wav"])
        let wav = try XCTUnwrap(c.previewAudioURL)
        XCTAssertTrue(wav.path.contains("/cache/montage/"))
        XCTAssertGreaterThan(try FileManager.default.attributesOfItem(atPath: wav.path)[.size] as? Int ?? 0, 1000)
        let secs = try XCTUnwrap(c.lastPreviewMixSeconds), video = try XCTUnwrap(c.lastPreviewMixVideoSeconds)
        print("MONTAJE mezcla del WAV de vista previa: \(String(format: "%.3f", secs)) s para \(video) s de vídeo (\(String(format: "%.2f", secs / video * 60)) s por minuto de montaje)")

        // Cambios que no tocan la mezcla: no se vuelve a mezclar.
        c.setCaption(false)
        c.setShowPartLabels(false)
        c.setLayout(.stack)
        await sleep(0.4)
        XCTAssertEqual(c.previewMixCount, 1)
        XCTAssertEqual(c.previewAudioKey, key1)

        // Cortar huecos cambia los tramos: mezcla nueva y el WAV viejo desaparece.
        c.setCutGaps(true)
        await waitUntil { c.previewMixCount == 2 && c.audioPhase == .ready }
        let key2 = try XCTUnwrap(c.previewAudioKey)
        XCTAssertNotEqual(key1, key2)
        XCTAssertEqual(previewWAVs(rig), ["preview-\(key2).wav"])

        // Un fichero de audio distinto (misma ruta) también invalida.
        await sleep(0.05)
        try StudyTests.writeSine(rig.layout.stemURL(.bass), frequency: 220, seconds: Self.songSeconds - 1)
        c.setShowPartLabels(true)
        await waitUntil { c.previewMixCount == 3 && c.audioPhase == .ready }
        XCTAssertNotEqual(c.previewAudioKey, key2)

        // Reabrir con todo igual: sin mezclar de nuevo.
        await c.flush()
        c.close()
        let again = try makeController(rig, services: .simulated())
        again.open()
        await waitUntil { again.previewPhase == .ready && again.audioPhase == .ready }
        XCTAssertEqual(again.previewMixCount, 0)
        XCTAssertEqual(again.previewAudioURL, c.previewAudioURL)
        again.close()
    }

    func testPreviewWithoutPlanIsNone() async throws {
        let rig = try makeRig()
        var p = try ProjectFile.load(folder: rig.folder)
        p.recording?.parts = []
        try ProjectFile.save(p, to: rig.folder)
        let c = try makeController(rig, services: .simulated())
        XCTAssertNil(c.draft)
        c.open()
        await sleep(0.2)
        XCTAssertEqual(c.previewPhase, .none)
        XCTAssertFalse(c.canExport)
        XCTAssertFalse(c.previewReady)
        try c.play()   // sin vista previa no hace nada
        XCTAssertFalse(c.isPlaying)
    }

    func testComposerFailureShowsMacError() async throws {
        let rig = try makeRig()
        struct Boom: Error, CustomStringConvertible { var description: String { "sin GPU" } }
        var services = MontageServices.simulated()
        services.makeComposer = { _, _ in throw Boom() }
        let c = try makeController(rig, services: services)
        c.open()
        await waitUntil { c.previewPhase == .error }
        XCTAssertEqual(c.previewError, "No se pudo preparar la vista previa (sin GPU).")
        XCTAssertFalse(c.previewReady)
    }

    // MARK: Vista previa: transporte y bucle de fotogramas

    func testFrameLoopKeepsTargetRateWithFastCompositor() async throws {
        let rig = try makeRig()
        let frames = FrameLog()
        let c = try makeController(rig, services: .simulated(frameMillis: 1), frames: frames)
        await openReady(c)
        XCTAssertEqual(c.previewFPS, 15)
        frames.clear()
        try c.play()
        XCTAssertTrue(c.isPlaying)
        await sleep(2.0)
        c.pause()
        let n = frames.count
        XCTAssertFalse(c.isPlaying)
        // 15 fps durante 2 s: unos 30 fotogramas (margen del planificador).
        XCTAssertTrue((24...34).contains(n), "fotogramas: \(n)")
        XCTAssertLessThanOrEqual(c.previewStats.skipped, 3)
        // PTS crecientes, en ms de vídeo, y cercanos al reloj.
        let pts = frames.all.map(\.pts)
        XCTAssertEqual(pts.dropLast().sorted(), Array(pts.dropLast()))
        XCTAssertGreaterThan(c.videoPosition, 1.5)
        print("MONTAJE bucle rápido (1 ms/fotograma): \(n) fotogramas en 2 s, saltados \(c.previewStats.skipped)")
        c.close()
    }

    func testFrameLoopSkipsFramesWhenCompositorIsSlow() async throws {
        let rig = try makeRig()
        let frames = FrameLog()
        let box = SimulatedComposerBox()
        let c = try makeController(rig, services: .simulated(frameMillis: 110, composerBox: box), frames: frames)
        await openReady(c)
        frames.clear()
        try c.play()
        await sleep(2.0)
        c.pause()
        let n = frames.count
        // 110 ms por fotograma frente a 66 ms de periodo: se pide uno tras otro (~8 fps reales) y los de la rejilla de 15 fps
        // intermedios se saltan sin acumular retraso.
        XCTAssertTrue((14...19).contains(n), "fotogramas: \(n)")
        XCTAssertGreaterThanOrEqual(c.previewStats.skipped, 5)
        XCTAssertGreaterThan(c.previewStats.averageFrameMillis, 100)
        // El último fotograma pedido va al día con el reloj (no con el índice de fotograma).
        let last = try XCTUnwrap(frames.all.last?.pts)
        XCTAssertGreaterThan(last, 1500)
        print("MONTAJE bucle lento (110 ms/fotograma a 15 fps): \(n) fotogramas en 2 s, saltados \(c.previewStats.skipped), media \(String(format: "%.0f", c.previewStats.averageFrameMillis)) ms")
        c.close()
    }

    func testPreviewFPSIsConfigurableAndClamped() async throws {
        let rig = try makeRig()
        let frames = FrameLog()
        let c = try makeController(rig, services: .simulated(frameMillis: 1), frames: frames)
        await openReady(c)
        c.previewFPS = 5
        frames.clear()
        try c.play()
        await sleep(2.0)
        c.pause()
        XCTAssertTrue((8...12).contains(frames.count), "fotogramas a 5 fps: \(frames.count)")
        c.previewFPS = 500
        XCTAssertEqual(c.previewFPS, 60)
        c.previewFPS = 0
        XCTAssertEqual(c.previewFPS, 1)
        c.close()
    }

    func testSeekWhilePausedEmitsOneStillFrame() async throws {
        let rig = try makeRig()
        let frames = FrameLog()
        let box = SimulatedComposerBox()
        let c = try makeController(rig, services: .simulated(composerBox: box), frames: frames)
        await openReady(c)
        await waitUntil { frames.count >= 1 }   // el fotograma suelto de «lista»
        frames.clear()
        c.seek(to: 10)
        await waitUntil { frames.count == 1 }
        await sleep(0.2)
        XCTAssertEqual(frames.count, 1)
        // Tiempo del tema 10 = tiempo de vídeo 6 (el vídeo empieza a las 4).
        XCTAssertEqual(frames.all[0].pts, 6000, accuracy: 1)
        XCTAssertEqual(c.songTime, 10, accuracy: 0.01)
        c.seek(to: 1000)   // se queda dentro del tramo
        XCTAssertEqual(c.songTime, c.span.end, accuracy: 0.01)
        c.seek(to: -5)
        XCTAssertEqual(c.songTime, c.span.start, accuracy: 0.01)
        c.close()
    }

    func testPlayUntilEndStopsAndPlayAgainRestarts() async throws {
        let rig = try makeRig()
        let c = try makeController(rig, services: .simulated(frameMillis: 1))
        await openReady(c)
        c.seek(to: c.span.end - 0.4)
        try c.play()
        await waitUntil(5) { !c.isPlaying }
        XCTAssertFalse(c.isPlaying)
        XCTAssertEqual(c.songTime, c.span.end, accuracy: 0.05)
        try c.play()   // al final: vuelve al principio
        XCTAssertTrue(c.isPlaying)
        XCTAssertLessThan(c.songTime, c.span.start + 1)
        c.pause()
        c.close()
    }

    func testPlayDuringRebuildKeepsPositionAndKeepsPlaying() async throws {
        let rig = try makeRig()
        let c = try makeController(rig, services: .simulated(frameMillis: 1))
        await openReady(c)
        c.seek(to: 8)
        try c.play()
        await sleep(0.3)
        c.setCutGaps(true)   // reconstruye la vista previa y mezcla otro WAV
        await waitUntil { c.audioPhase == .ready && c.previewMixCount == 2 }
        await sleep(0.2)
        XCTAssertTrue(c.isPlaying)
        XCTAssertGreaterThan(c.songTime, 7)
        c.pause()
        c.close()
    }

    // MARK: Exportación

    func testExportDoneWritesFileAndReportsProgress() async throws {
        let rig = try makeRig()
        let counters = SimulatedMontageCounters()
        let c = try makeController(rig, services: .simulated(exportSteps: 5, exportStepMillis: 20, counters: counters))
        await openReady(c)
        c.updateExport { $0.container = .mp4; $0.trackWAVs = false; $0.normalize = false }
        var progress: [Double] = []
        c.onExport = { if case .running(_, let p) = c.exportPhase { progress.append(p) } }
        c.startExport()
        XCTAssertTrue(c.isExporting)
        XCTAssertFalse(c.canExport)
        await waitUntil { if case .done = c.exportPhase { return true }; return false }
        guard case .done(let r) = c.exportPhase else { return XCTFail("\(c.exportPhase)") }
        XCTAssertEqual(r.url.pathExtension, "mp4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: r.url.path))
        XCTAssertEqual(r.codec, c.effectiveCodec.rawValue)
        XCTAssertNil(r.tracksDirectory)
        XCTAssertEqual(progress, progress.sorted())
        XCTAssertGreaterThan(progress.count, 3)
        XCTAssertTrue(progress.contains { $0 > MontageController.mixProgressShare })
        c.dismissExportResult()
        XCTAssertEqual(c.exportPhase, .idle)
        c.close()
    }

    func testExportCancelledDeletesWhatWasWritten() async throws {
        let rig = try makeRig()
        let counters = SimulatedMontageCounters()
        let c = try makeController(rig, services: .simulated(exportSteps: 200, exportStepMillis: 20, counters: counters))
        await openReady(c)
        c.updateExport { $0.trackWAVs = true }   // WAV por pista junto al vídeo: se borran al cancelar
        c.startExport()
        await waitUntil { counters.exportStarted }
        let tracks = rig.layout.montageTracksDirectory(layout: c.state.layout)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tracks.appendingPathComponent("mezcla.wav").path))
        let t0 = ProcessInfo.processInfo.systemUptime
        c.cancelExport()
        await waitUntil { c.exportPhase == .cancelled }
        XCTAssertEqual(c.exportPhase, .cancelled)
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - t0, 1.0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tracks.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: rig.layout.montageVideoURL(layout: c.state.layout, container: c.state.export.container).path))
        XCTAssertTrue(c.canExport)
        c.close()
    }

    func testExportFailureUsesMacLiteral() async throws {
        let rig = try makeRig()
        struct Boom: Error, CustomStringConvertible { var description: String { "disco lleno" } }
        var services = MontageServices.simulated()
        services.export = { _, _, _, _, _ in throw Boom() }
        let c = try makeController(rig, services: services)
        await openReady(c)
        c.updateExport { $0.trackWAVs = false }
        await c.exportAndWait()
        XCTAssertEqual(c.exportPhase, .failed("No se pudo exportar el vídeo (disco lleno)."))
        c.close()
    }

    func testClosingWithExportRunningCancelsIt() async throws {
        let rig = try makeRig()
        let counters = SimulatedMontageCounters()
        let c = try makeController(rig, services: .simulated(exportSteps: 500, exportStepMillis: 20, counters: counters))
        await openReady(c)
        c.updateExport { $0.trackWAVs = false }
        c.startExport()
        await waitUntil { counters.exportStarted }
        c.close()
        await waitUntil { c.exportPhase == .cancelled }
        XCTAssertEqual(c.exportPhase, .cancelled)
    }

    // MARK: montage.* por el puente

    final class Events: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [(time: Double, name: String, payload: [String: Any])] = []
        func add(_ json: String) {
            guard let o = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any], let name = o["event"] as? String else { return }
            lock.withLock { items.append((ProcessInfo.processInfo.systemUptime, name, o["payload"] as? [String: Any] ?? [:])) }
        }
        func all(_ name: String) -> [(time: Double, name: String, payload: [String: Any])] { lock.withLock { items.filter { $0.name == name } } }
    }

    func makeBridge(_ rig: Rig, services: MontageServices = .simulated()) throws -> (Bridge, Events) {
        let support = rig.base.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let js = JobServices(importer: EditsImporter(), separator: EditsSeparator(), levelMeter: nil, analyzer: nil, guitarSplitter: nil)
        let bridge = try Bridge(options: LaunchOptions(projectsFolder: rig.root, supportDir: support, audio: .simulated),
                                mediaBase: "https://tf.media/", reveal: nil, services: js)
        let events = Events()
        bridge.send = { events.add($0) }
        bridge.montageService.services = services
        bridge.montageService.audioFactory = { _, _ in ClockMontageAudio() }
        bridge.montageService.timing = MontageController.Timing(previewDebounce: 0.01, saveDelay: 0.05)
        return (bridge, events)
    }

    func call(_ b: Bridge, _ method: String, _ params: String = "{}") async -> [String: Any] {
        let out = await b.router.handle("{\"id\":1,\"method\":\"\(method)\",\"params\":\(params)}")
        return (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: Any] ?? [:]
    }

    func testBridgeOpenSnapshotAndStateEventsOnlyOnChanges() async throws {
        let rig = try makeRig()
        let (b, events) = try makeBridge(rig)
        let notOpen = await call(b, "montage.snapshot")
        XCTAssertEqual((notOpen["error"] as? [String: Any])?["code"] as? String, "not-open")
        let r = await call(b, "montage.open", "{\"projectId\":\"\(rig.project.id.uuidString)\"}")
        let s = try XCTUnwrap(r["result"] as? [String: Any], "\(r)")
        XCTAssertEqual(s["title"] as? String, "Tema")
        XCTAssertEqual(s["layout"] as? String, "side")
        XCTAssertEqual(s["hasPlan"] as? Bool, true)
        XCTAssertEqual((s["lanes"] as? [[String: Any]])?.count, 3)
        XCTAssertEqual((s["lanes"] as? [[String: Any]])?.first?["partName"] as? String, "Rítmica 1")
        let export = try XCTUnwrap(s["export"] as? [String: Any])
        let options = try XCTUnwrap(export["options"] as? [String: Any])
        XCTAssertTrue((options["codecs"] as? [String])?.contains("h264") == true)
        XCTAssertEqual((options["containers"] as? [String])?.sorted(), ["mov", "mp4"])
        XCTAssertEqual((options["resolutions"] as? [[String: Any]])?.count, 3)
        XCTAssertEqual((s["preview"] as? [String: Any])?["maxDimension"] as? Int, 640)
        XCTAssertEqual(((s["preview"] as? [String: Any])?["width"] as? Int), 640)
        XCTAssertEqual(((s["preview"] as? [String: Any])?["height"] as? Int), 360)

        // La vista previa y el análisis acaban solos y avisan por `montage.state`.
        await waitUntil { events.all("montage.state").contains { ($0.payload["preview"] as? [String: Any])?["phase"] as? String == "ready"
            && (($0.payload["preview"] as? [String: Any])?["audio"] as? [String: Any])?["phase"] as? String == "ready"
            && $0.payload["isAnalyzing"] as? Bool == false } }
        await sleep(0.2)
        let before = events.all("montage.state").count
        XCTAssertGreaterThan(before, 0)
        let l = await call(b, "montage.setLayout", "{\"layout\":\"grid\"}")
        XCTAssertEqual((l["result"] as? [String: Any])?["layout"] as? String, "grid")
        await sleep(0.3)
        let afterChange = events.all("montage.state").count
        XCTAssertGreaterThan(afterChange, before)
        XCTAssertEqual(events.all("montage.state").last?.payload["layout"] as? String, "grid")
        // Lo mismo otra vez: ninguna instantánea nueva.
        _ = await call(b, "montage.setLayout", "{\"layout\":\"grid\"}")
        _ = await call(b, "montage.setCaption", "{\"on\":\(false)}")
        await sleep(0.3)
        let afterCaption = events.all("montage.state").count
        _ = await call(b, "montage.setCaption", "{\"on\":false}")
        await sleep(0.3)
        XCTAssertEqual(events.all("montage.state").count, afterCaption)
        // Parámetros erróneos.
        let bad = await call(b, "montage.setLayout", "{\"layout\":\"nope\"}")
        XCTAssertEqual((bad["error"] as? [String: Any])?["code"] as? String, "bad-params")
        let badID = await call(b, "montage.rotateTake", "{\"takeId\":\"x\"}")
        XCTAssertEqual((badID["error"] as? [String: Any])?["code"] as? String, "bad-params")
        _ = await call(b, "montage.close")
    }

    /// W2-E2: sin `setMontageFrameSink`, el núcleo manda la vista previa por `frames.montage` (relevo por tema abierto;
    /// `montage.close` lo para). El fotograma de un `seek` en pausa llega aunque el anterior acabe de salir (`latestWins`).
    func testBridgeWiresMontageRelay() async throws {
        let rig = try makeRig()
        let (b, events) = try makeBridge(rig, services: .simulated(frameMillis: 1))
        _ = await call(b, "montage.open", "{\"projectId\":\"\(rig.project.id.uuidString)\"}")
        await waitUntil { b.montageService.current?.previewPhase == .ready }
        await waitUntil { !events.all("frames.montage").isEmpty }
        let relay = try XCTUnwrap(b.montageService.frameRelay)
        XCTAssertTrue(relay.latestWins)
        XCTAssertEqual(relay.maxFPS, Bridge.montageRelayMaxFPS)
        // Varios seeks seguidos en pausa: el último siempre sale.
        for t in [12.0, 12.5, 13.0, 13.5] { _ = await call(b, "montage.seek", "{\"seconds\":\(t)}") }
        let wantVideo = try XCTUnwrap(b.montageService.current).videoPosition * 1000
        await waitUntil { (events.all("frames.montage").last?.payload["ptsMs"] as? Double).map { abs($0 - wantVideo) < 1 } ?? false }
        let last = try XCTUnwrap(events.all("frames.montage").last?.payload)
        XCTAssertEqual(last["ptsMs"] as? Double ?? -1, wantVideo, accuracy: 1, "el fotograma del último seek")
        XCTAssertFalse((last["jpeg"] as? String ?? "").isEmpty)
        let st = (await call(b, "frames.stats", "{\"channel\":\"montage\"}"))["result"] as? [String: Any] ?? [:]
        XCTAssertEqual(st["running"] as? Bool, true, "\(st)")
        _ = await call(b, "montage.close")
        XCTAssertNil(b.montageService.frameRelay)
        XCTAssertFalse(relay.stats.running)
        await b.closeMontage()   // dos veces no hace nada
    }

    func testBridgeActionsExportFramingAndTransport() async throws {
        let rig = try makeRig()
        let frames = FrameLog()
        let (b, events) = try makeBridge(rig)
        b.setMontageFrameSink { _, pts in frames.add(pts) }
        await sleep(0.05)
        _ = await call(b, "montage.open", "{\"projectId\":\"\(rig.project.id.uuidString)\"}")
        await waitUntil { b.montageService.current?.previewPhase == .ready && b.montageService.current?.isAnalyzing == false }
        await waitUntil { frames.count >= 1 }
        XCTAssertGreaterThanOrEqual(frames.count, 1)

        // Cortes y plano único.
        _ = await call(b, "montage.setLayout", "{\"layout\":\"single\"}")
        let add = await call(b, "montage.addCut", "{\"time\":17,\"partId\":\"\(rig.partIDs[2].uuidString)\",\"exact\":true}")
        let added = try XCTUnwrap(add["result"] as? [String: Any], "\(add)")
        let cutID = try XCTUnwrap(added["cutId"] as? String)
        let snap = try XCTUnwrap(added["snapshot"] as? [String: Any])
        XCTAssertEqual((snap["cuts"] as? [[String: Any]])?.first?["covered"] as? Bool, true)
        XCTAssertFalse(((snap["planeShots"] as? [[String: Any]]) ?? []).isEmpty)
        XCTAssertNotNil(snap["songDuration"] as? Double, "duración del tema en la instantánea")
        let elig = (snap["cuts"] as? [[String: Any]])?.first?["eligible"] as? [String] ?? []
        XCTAssertTrue(elig.contains(rig.partIDs[2].uuidString), "\(elig)")
        XCTAssertFalse(elig.contains(rig.partIDs[0].uuidString), "\(elig)")
        let part = await call(b, "montage.setCutPart", "{\"id\":\"\(cutID)\",\"partId\":\"\(rig.partIDs[0].uuidString)\"}")
        XCTAssertEqual(((part["result"] as? [String: Any])?["cuts"] as? [[String: Any]])?.first?["covered"] as? Bool, false)
        let rm = await call(b, "montage.removeCut", "{\"id\":\"\(cutID)\"}")
        XCTAssertEqual(((rm["result"] as? [String: Any])?["cuts"] as? [[String: Any]])?.count, 0)

        // Encuadre: ajustes, hoja y fotograma.
        let fixed = await call(b, "montage.setFraming", "{\"takeId\":\"\(rig.takeIDs[0].uuidString)\",\"mode\":\"fixed\",\"manualBox\":{\"x\":0.1,\"y\":0.1,\"width\":0.5,\"height\":0.5}}")
        XCTAssertEqual((((fixed["result"] as? [String: Any])?["framing"] as? [[String: Any]])?.first?["manualBox"] as? [String: Any])?["width"] as? Double, 0.5)
        let frame = await call(b, "montage.framingFrame", "{\"takeId\":\"\(rig.takeIDs[0].uuidString)\",\"time\":5}")
        let fres = try XCTUnwrap(frame["result"] as? [String: Any], "\(frame)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: rig.folder.appendingPathComponent(try XCTUnwrap(fres["path"] as? String)).path))
        XCTAssertEqual((fres["box"] as? [String: Any])?["width"] as? Double, 0.5)
        let fr = await call(b, "montage.setFraming", "{\"takeId\":\"\(rig.takeIDs[0].uuidString)\",\"mode\":\"follow\",\"followZoom\":1.4,\"followOffset\":{\"x\":0.1,\"y\":-0.1}}")
        let framing = ((fr["result"] as? [String: Any])?["framing"] as? [[String: Any]])?.first
        XCTAssertEqual(framing?["mode"] as? String, "follow")
        XCTAssertEqual(framing?["followZoom"] as? Double, 1.4)
        XCTAssertEqual((framing?["followOffset"] as? [String: Any])?["y"] as? Double, -0.1)
        let reset = await call(b, "montage.resetFraming", "{\"takeId\":\"\(rig.takeIDs[0].uuidString)\"}")
        XCTAssertEqual((((reset["result"] as? [String: Any])?["framing"] as? [[String: Any]])?.first?["manualBox"]) == nil, true)

        // Transporte: seek en pausa da un fotograma; play emite `montage.position` a ≤ 30 Hz.
        frames.clear()
        _ = await call(b, "montage.setLayout", "{\"layout\":\"side\"}")
        await waitUntil { b.montageService.current?.previewPhase == .ready && b.montageService.current?.audioPhase == .ready }
        await sleep(0.3)
        frames.clear()
        let seek = await call(b, "montage.seek", "{\"seconds\":12}")
        XCTAssertEqual(((seek["result"] as? [String: Any])?["transport"] as? [String: Any])?["position"] as? Double ?? 0, 12, accuracy: 0.05)
        await waitUntil { frames.count >= 1 }
        XCTAssertEqual(frames.all.first?.pts ?? 0, 8000, accuracy: 1)
        let before = events.all("montage.position").count
        let play = await call(b, "montage.play")
        XCTAssertEqual(((play["result"] as? [String: Any])?["transport"] as? [String: Any])?["playing"] as? Bool, true)
        await sleep(1.0)
        _ = await call(b, "montage.pause")
        await sleep(0.2)
        let positions = events.all("montage.position").dropFirst(before)
        XCTAssertGreaterThan(positions.count, 10)
        XCTAssertLessThanOrEqual(positions.count, 36)
        let times = positions.map(\.time)
        for (x, y) in zip(times, times.dropFirst()) { XCTAssertGreaterThanOrEqual(y - x, 0.9 / 30 - 0.004) }
        XCTAssertEqual(positions.last?.payload["playing"] as? Bool, false)

        // Exportación: ajustes, progreso, fin con la ruta.
        _ = await call(b, "montage.setExport", "{\"container\":\"mp4\",\"trackWAVs\":false,\"fps\":25,\"resolution\":{\"width\":1280,\"height\":720}}")
        let start = await call(b, "montage.startExport")
        XCTAssertNil(start["error"], "\(start)")
        await waitUntil { events.all("montage.export").contains { $0.payload["phase"] as? String == "done" } }
        let done = try XCTUnwrap(events.all("montage.export").last?.payload)
        XCTAssertEqual(done["phase"] as? String, "done")
        let result = try XCTUnwrap(done["result"] as? [String: Any])
        XCTAssertTrue((result["path"] as? String)?.hasSuffix(".mp4") == true)
        XCTAssertTrue(events.all("montage.export").contains { $0.payload["phase"] as? String == "running" })
        XCTAssertTrue(events.all("montage.framing").contains { $0.payload["status"] as? String == "ready" })
        let dismiss = await call(b, "montage.dismissExport")
        XCTAssertEqual(((dismiss["result"] as? [String: Any])?["exportStatus"] as? [String: Any])?["phase"] as? String, "idle")
        await b.closeMontage()
        let saved = try ProjectFile.load(folder: rig.folder)
        XCTAssertEqual(saved.montage?.export.fps, 25)
        XCTAssertEqual(saved.montage?.export.container, .mp4)
        XCTAssertEqual(saved.montage?.export.resolution, .hd720)
    }

    func testBridgeCancelExport() async throws {
        let rig = try makeRig()
        let counters = SimulatedMontageCounters()
        let (b, events) = try makeBridge(rig, services: .simulated(exportSteps: 400, exportStepMillis: 20, counters: counters))
        _ = await call(b, "montage.open", "{\"projectId\":\"\(rig.project.id.uuidString)\"}")
        await waitUntil { b.montageService.current?.canExport == true && b.montageService.current?.previewPhase == .ready }
        _ = await call(b, "montage.setExport", "{\"trackWAVs\":false}")
        _ = await call(b, "montage.startExport")
        await waitUntil { counters.exportStarted }
        _ = await call(b, "montage.cancelExport")
        await waitUntil { events.all("montage.export").contains { $0.payload["phase"] as? String == "cancelled" } }
        XCTAssertTrue(events.all("montage.export").contains { $0.payload["phase"] as? String == "cancelled" })
        await b.closeMontage()
    }
}
