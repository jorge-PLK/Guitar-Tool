#if DEBUG
import AVFoundation
import Foundation
import Store
import VideoKit

extension RecordController {
    /// `--screen record | record-counting | record-offset` (solo DEBUG): tres partes con tomas (una marcada como
    /// mejor), con ficheros de verdad en el proyecto (úsalo con una copia: `--projects-folder`), cámara y audio
    /// simulados. `record-counting` deja la cuenta en curso y `record-offset` abre la hoja de desfase.
    func seedDemo(_ screen: String) async {
        let rate = session.project.song.sampleRate
        if EquipmentProfile.allowedSampleRates.contains(rate) { model.profile.workingSampleRate = rate }
        if session.project.song.artist == nil { _ = await model.updateSongInfo(id: session.projectID, title: "So payaso", artist: "Extremoduro") }
        let layout = session.layout
        let fm = FileManager.default
        if !state.parts.contains(where: { !$0.takeIDs.isEmpty }) {
            var parts = [RecordingPart(name: "Robe · rítmica", replaces: .rhythm),
                         RecordingPart(name: "Uoho · rítmica", replaces: .left),
                         RecordingPart(name: "Solo", replaces: .lead)]
            var takes: [Take] = []
            let camera = TakeVideoFormat(cameraUID: "sim-iphone", cameraName: "iPhone (Continuity Camera)", width: 1920, height: 1080, fps: 30)
            for (pi, count) in [(0, 2), (1, 1)] {
                for n in 0..<count {
                    let id = UUID()
                    let dir = layout.takeDirectory(takeId: id)
                    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
                    if let wav = try? Self.makeCountInFile(beats: 4, beatSeconds: 0.5, sampleRate: rate) {
                        try? fm.removeItem(at: layout.processedURL(takeId: id))
                        try? fm.moveItem(at: wav, to: layout.processedURL(takeId: id))
                    }
                    let withVideo = pi == 0 && n == 1
                    if withVideo { await Self.writeDemoVideo(to: layout.videoURL(takeId: id), songStart: 20) }
                    takes.append(Take(id: id, processedFile: ProjectLayout.processedRelativePath(takeId: id),
                                      createdAt: Date().addingTimeInterval(Double(pi * 10 + n)), songStart: 20, sampleRate: rate,
                                      latencyCalibrated: true, partID: parts[pi].id,
                                      videoFile: withVideo ? ProjectLayout.videoRelativePath(takeId: id) : nil,
                                      videoOffset: withVideo ? 0.065 : nil, videoFormat: withVideo ? camera : nil))
                    parts[pi].addTake(id)
                }
            }
            session.saveTakes(takes)
            state.parts = parts
            await flush()
            selectPart(parts[1].id)
            reloadTakeTracks()
        }
        switch screen {
        case "record-counting": phase = .counting(3)
        case "record-offset":
            if let best = state.parts.first?.bestTakeID { adjustOffset(takeID: best) }
        default:
            if state.parts.count > 1 { selectedTakeID = state.parts[1].bestTakeID }
        }
    }

    /// Un `video.mov` de 2 s con la cámara simulada (fotogramas con PTS = tiempo del tema).
    private static func writeDemoVideo(to url: URL, songStart: Double) async {
        let cam = SimulatedCameraCapture(config: .init(pixels: true), automatic: false, originHostSeconds: 0)
        guard let format = try? cam.start(CameraRequest(width: 1280, height: 720, fps: 30), onFrame: { _ in }),
              let writer = try? VideoTakeWriter(url: url, format: format, realTime: false) else { return }
        cam.stop()
        let source = SimulatedCameraCapture(config: .init(delaySeconds: 0, jitterSeconds: 0, pixels: true), automatic: false,
                                            originHostSeconds: 0)
        _ = try? source.start(CameraRequest(width: 1280, height: 720, fps: 30)) { frame in
            _ = writer.append(frame, songTime: songStart + frame.hostSeconds)
        }
        source.advance(toHostSeconds: 2)
        source.stop()
        _ = try? await writer.finish()
    }
}
#endif
