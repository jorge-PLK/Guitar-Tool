#if DEBUG
import AVFoundation
import Foundation
import Store
import VideoKit

/// `--screen montage | montage-framing` (solo DEBUG): si el proyecto no tiene tomas con vídeo, se generan tres
/// partes (dos rítmicas y una solista) con tomas sintéticas de color liso y se marca una sección de solo; todo con
/// ficheros de verdad en el proyecto (úsalo con una copia: `--projects-folder`). `--montage-layout side|grid|stack|single|single-landscape`
/// elige el layout y `--seek` el instante de la vista previa (por defecto, un segundo dentro del primer solo).
/// Cronómetro de la comprobación `--montage-export`: instantes (s desde `reset`) de cada fase. Las fases de la mezcla
/// salen del progreso de `MontageMixer.mix` (0,5 = fin del pase 1; cada salto posterior por debajo de 1 = una pasada
/// del limitador; 1 = escrita `mezcla.wav`).
final class ExportClock: @unchecked Sendable {
    private let lock = NSLock()
    private var origin = Date()
    private var lastMix = -1.0
    private(set) var marks: [(String, Double)] = []

    func reset() { lock.withLock { origin = Date(); lastMix = -1; marks = [] } }

    func mark(_ name: String) {
        lock.withLock { marks.append((name, Date().timeIntervalSince(origin))) }
    }

    func markOnce(_ name: String) {
        lock.withLock { if !marks.contains(where: { $0.0 == name }) { marks.append((name, Date().timeIntervalSince(origin))) } }
    }

    func mixProgress(_ p: Double) {
        lock.withLock {
            defer { lastMix = max(lastMix, p) }
            guard p >= 0.5 - 1e-9, p > lastMix + 1e-9 else { return }
            let name = p >= 1 - 1e-9 ? "mezcla: escritura final" : (lastMix < 0.5 - 1e-9 ? "mezcla: pase 1 (render + medida + pistas)" : "mezcla: pasada limitador")
            marks.append((name, Date().timeIntervalSince(origin)))
        }
    }

    var json: [[String: Any]] { lock.withLock { marks.map { ["phase": $0.0, "t": $0.1] } } }
}

enum MontageDemo {
    /// Duración máxima de las tomas sintéticas (s).
    private static let maxTakeSeconds = 24.0
    private static let frame = (width: 320, height: 180, fps: 6.0)

    private struct DemoPart {
        var name: String
        var role: GuitarRole
        /// Tramo de la toma en fracciones de `L` desde `s0`.
        var from: Double
        var to: Double
        var color: (b: UInt8, g: UInt8, r: UInt8)
        var hz: Double
    }

    private static let parts: [DemoPart] = [
        DemoPart(name: "Robe · rítmica", role: .rhythm, from: 0, to: 0.7, color: (0xEB, 0xC0, 0x5B), hz: 220),
        DemoPart(name: "Uoho · rítmica", role: .left, from: 0, to: 0.5, color: (0x3A, 0xA3, 0xF2), hz: 330),
        DemoPart(name: "Solo", role: .lead, from: 0.3, to: 1.0, color: (0xFF, 0x9C, 0xB7), hz: 440),
    ]

    @MainActor
    static func seed(session: StudySession, model: AppModel) async {
        guard let library = model.library else { return }
        let project = session.project
        if let rec = project.recording, rec.parts.contains(where: { p in
            p.bestTakeID.flatMap { id in project.takes.first { $0.id == id }?.videoFile } != nil
        }) { return }

        let total = max(project.song.duration, 30)
        let length = min(maxTakeSeconds, total * 0.5)
        let s0 = (total * 0.15 * 2).rounded() / 2
        let rate = [44_100.0, 48_000.0].contains(project.song.sampleRate) ? project.song.sampleRate : 48_000
        let layout = session.layout
        let fm = FileManager.default
        let camera = TakeVideoFormat(cameraUID: "sim-iphone", cameraName: "iPhone (Continuity Camera)", width: frame.width,
                                     height: frame.height, fps: frame.fps)

        var state = project.recordingOrInitial()
        state.parts = []
        var takes: [Take] = []
        for (i, p) in parts.enumerated() {
            let id = UUID()
            let start = s0 + p.from * length
            let seconds = (p.to - p.from) * length
            try? fm.createDirectory(at: layout.takeDirectory(takeId: id), withIntermediateDirectories: true)
            writeTone(to: layout.processedURL(takeId: id), seconds: seconds, hz: p.hz, rate: rate)
            await writeVideo(to: layout.videoURL(takeId: id), songStart: start, seconds: seconds, color: p.color)
            takes.append(Take(id: id, processedFile: ProjectLayout.processedRelativePath(takeId: id),
                              createdAt: Date().addingTimeInterval(Double(i)), songStart: start, sampleRate: rate,
                              latencyCalibrated: true, videoFile: ProjectLayout.videoRelativePath(takeId: id),
                              videoOffset: 0, videoFormat: camera))
            var part = RecordingPart(name: p.name, replaces: p.role)
            part.addTake(id)
            takes[takes.count - 1].partID = part.id
            state.parts.append(part)
        }
        if !session.project.sections.contains(where: \.isSolo) {
            // Entre el final de Estribillo (0,7) y el segundo solo (0,8) no hay ninguna parte: hueco para «Cortar huecos».
            let sections = [Store.Section(name: "Estrofa", start: s0, end: s0 + length * 0.35),
                            Store.Section(name: "Solo", start: s0 + length * 0.35, end: s0 + length * 0.55, solo: true),
                            Store.Section(name: "Estribillo", start: s0 + length * 0.55, end: s0 + length * 0.8),
                            Store.Section(name: "Solo", start: s0 + length * 0.8, end: s0 + length * 0.95, solo: true)]
            try? await library.saveStudy(id: session.projectID, study: session.study, sections: sections)
        }
        try? await library.saveTakes(id: session.projectID, takes)
        try? await library.saveRecording(id: session.projectID, state)
        session.reload()
    }

    @MainActor
    static func apply(_ options: LaunchOptions, to ctl: MontageController) {
        // Primero lo neutro y después lo que pidan los demás argumentos.
        if options.montageNeutral {
            ctl.setShowPartLabels(true)
            ctl.setKeepVideoAspect(false)
            ctl.clearCuts()
            ctl.setLayout(.side)
        }
        if let l = options.montageLayout, let kind = Store.MontageLayoutKind(rawValue: l) { ctl.setLayout(kind) }
        if let idx = options.montageOrder {
            let ids = ctl.session.project.recordingOrInitial().parts.map(\.id)
            ctl.setPartOrder(idx.filter { ids.indices.contains($0) }.map { ids[$0] })
        }
        if let c = options.montageContainer, let container = MontageContainer(rawValue: c) {
            ctl.updateExport { $0.container = container }
        }
        ctl.setCutGaps(options.montageCutGaps)
        if options.montageNoPartLabels { ctl.setShowPartLabels(false) }
        if options.montageKeepAspect { ctl.setKeepVideoAspect(true) }
        if let cuts = options.montageCuts {
            // Se sustituyen los cortes guardados; el índice es el de la parte en el orden de Grabar.
            ctl.clearCuts()
            let ids = ctl.existingPartIDs
            for c in cuts {
                var part: UUID? = nil
                if let i = c.part, ids.indices.contains(i) { part = ids[i] }
                ctl.addCut(at: c.time, partID: part, exact: true)
            }
        }
        ctl.initialSongTime = options.seek ?? ctl.sections.first(where: \.isSolo).map { $0.start + 1 }
        if options.screen == "montage-framing" { ctl.framingSheetTakeID = ctl.videoLanes.first?.takeID }
    }

    /// `--montage-export`: espera al análisis, exporta como el botón y vuelca lo leído del fichero exportado.
    @MainActor
    static func runExportCheck(_ ctl: MontageController, options: LaunchOptions) async {
        let deadline = Date().addingTimeInterval(300)
        while (ctl.isAnalyzing || ctl.draft == nil) && Date() < deadline { try? await Task.sleep(for: .milliseconds(250)) }
        let suffix = "\(ctl.state.layout.rawValue)\(ctl.state.cutGaps ? "-cut" : "")\(ctl.state.export.container == .mov ? "" : "-\(ctl.state.export.container.rawValue)")"
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        // El plan tal cual, para reproducir con `tf-video montage` sin la app.
        if let plan = ctl.draft?.plan, let data = try? JSONEncoder().encode(plan) {
            try? data.write(to: cwd.appendingPathComponent("montage-plan-\(suffix).json"))
        }
        await ctl.exportAndWait()
        let ids = ctl.existingPartIDs
        let cutsJSON = ctl.cuts.map { c -> [String: Any] in
            ["time": c.time, "part": c.partID.flatMap { ids.firstIndex(of: $0) } as Any? ?? "auto"]
        }
        var out: [String: Any] = ["layout": ctl.state.layout.rawValue, "cutGaps": ctl.state.cutGaps,
                                  "showPartLabels": ctl.state.showPartLabels, "keepVideoAspect": ctl.state.keepVideoAspect,
                                  "keepAspectApplies": ctl.keepAspectApplies, "singleCuts": cutsJSON,
                                  "songSeconds": ctl.song.duration, "timings": ctl.exportClock.json]
        if let e = ctl.exportRawError { out["rawError"] = e }
        switch ctl.exportPhase {
        case .done(let r):
            out["video"] = r.url.path
            out["container"] = ctl.state.export.container.rawValue
            out["finalLUFS"] = r.finalLUFS as Any? ?? NSNull()
            out["finalTruePeakDB"] = r.finalTruePeakDB
            out["limitedByPeak"] = r.limitedByPeak
            out["normalized"] = r.normalized
            out["limiterEnabled"] = r.limiterEnabled
            out["limiterApplied"] = r.limiterApplied
            out["limiterMaxReductionDB"] = r.limiterMaxReductionDB
            let asset = AVURLAsset(url: r.url)
            if let v = try? await asset.loadTracks(withMediaType: .video).first,
               let (size, fps, range) = try? await v.load(.naturalSize, .nominalFrameRate, .timeRange) {
                out["width"] = Int(size.width); out["height"] = Int(size.height); out["fps"] = fps
                out["videoSeconds"] = range.duration.seconds
            }
            if let a = try? await asset.loadTracks(withMediaType: .audio).first, let range = try? await a.load(.timeRange) {
                out["audioSeconds"] = range.duration.seconds
            }
            out["plannedSeconds"] = ctl.draft?.segments.reduce(0) { $0 + ($1.end - $1.start) } as Any? ?? NSNull()
            if let dir = r.tracksDirectory {
                let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
                    .filter { $0.pathExtension == "wav" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
                out["wavs"] = files.map { u -> [String: Any] in
                    guard let f = try? AVAudioFile(forReading: u) else { return ["name": u.lastPathComponent] }
                    return ["name": u.lastPathComponent, "seconds": Double(f.length) / f.fileFormat.sampleRate, "sampleRate": f.fileFormat.sampleRate,
                            "bits": (f.fileFormat.settings[AVLinearPCMBitDepthKey] as? Int) ?? 0]
                }
            }
        case .failed(let m): out["error"] = m
        default: out["error"] = "La exportación no terminó"
        }
        let url = cwd.appendingPathComponent("export-\(suffix).json")
        if let data = try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: url) }
        exit(0)
    }

    // MARK: Ficheros sintéticos

    /// Seno de `hz` a −20 dBFS, mono, 16 bits.
    private static func writeTone(to url: URL, seconds: Double, hz: Double, rate: Double) {
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
                                       AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        guard let file = try? AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(rate)) else { return }
        let total = Int(seconds * rate)
        var written = 0
        while written < total {
            let n = min(Int(rate), total - written)
            buffer.frameLength = AVAudioFrameCount(n)
            let out = buffer.floatChannelData![0]
            for i in 0..<n { out[i] = Float(0.1 * sin(2 * .pi * hz * Double(written + i) / rate)) }
            try? file.write(from: buffer)
            written += n
        }
    }

    /// `video.mov` de color liso con las marcas en tiempo del tema (como la cámara simulada de Grabar).
    private static func writeVideo(to url: URL, songStart: Double, seconds: Double, color: (b: UInt8, g: UInt8, r: UInt8)) async {
        let request = CameraRequest(width: frame.width, height: frame.height, fps: frame.fps)
        let probe = SimulatedCameraCapture(config: .init(pixels: true, color: color), automatic: false, originHostSeconds: 0)
        guard let format = try? probe.start(request, onFrame: { _ in }),
              let writer = try? VideoTakeWriter(url: url, format: format, realTime: false) else { return }
        probe.stop()
        let source = SimulatedCameraCapture(config: .init(delaySeconds: 0, jitterSeconds: 0, pixels: true, color: color),
                                            automatic: false, originHostSeconds: 0)
        _ = try? source.start(request) { f in _ = writer.append(f, songTime: songStart + f.hostSeconds) }
        source.advance(toHostSeconds: seconds)
        source.stop()
        _ = try? await writer.finish()
    }
}
#endif
