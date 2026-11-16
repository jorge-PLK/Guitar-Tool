import AudioKit
import Foundation
import VideoKit

/// Códigos de salida: 0 bien, 1 fuera de tolerancia, 2 error de uso o de dispositivo.
enum Exit {
    static let ok: Int32 = 0
    static let outOfTolerance: Int32 = 1
    static let error: Int32 = 2
}

@MainActor
enum CLI {
    static let help = """
    tf-video: cámaras, grabación con vídeo y sincronía (herramienta de desarrollo de ToneForge)

    Uso: tf-video <cameras|record|sync|frame|montage> [opciones]

      cameras
          Lista las cámaras con UID, tipo y formatos (resolución y fps).
          Ejemplo: tf-video cameras

      record --in <uid|nombre> --out <uid|nombre> --guitar <c[,c]> --seconds N [--song <wav>] [--camera <uid|nombre>]
             [--width 1920 --height 1080 --fps 30] [--backing l,r] [--rate 48000]
          Graba cámara + guitarra sobre el backing (silencio si no hay --song) con la sesión de audio de la Fase 3.
          Deja video.mov (PTS = tiempo del tema), processed.wav (alineado) y frames.csv en Temp/tf-video/take-<fecha>/.
          Usa la calibración de Temp/tf-audio/calibration.json si vale.
          Ejemplo: tf-video record --in flex --out flex --guitar 1,2 --seconds 30 --camera iphone

      sync <mismas opciones que record>
          Igual sin escribir ficheros: informe de marcas (jitter, fotogramas perdidos, deriva cámara/audio,
          retardo de entrega).

      frame <video.mov> [--interval 0.25] [--png <ruta.png>]
          Encuadre automático (Vision): caja fija y resumen de la trayectoria; con --png, el fotograma central con
          la caja fija (rojo) y la de la trayectoria (verde).
          Ejemplo: tf-video frame Temp/tf-video/take-x/video.mov --png Temp/tf-video/frame.png

      montage <plan.json> <salida.mov> [--mix <wav>] [--codec hevc|h264] [--width W --height H] [--fps F]
          Exporta un MontagePlan en JSON (por defecto, lienzo y fps del plan, HEVC); --mix multiplexa el WAV.

    Sin hardware: --simulated L (audio simulado con latencia L muestras y cámara simulada),
      --sim-drift P (deriva del audio frente al host, ppm), --sim-camera-delay MS, --sim-drop N.
      Ejemplo: tf-video record --simulated 2400.81 --seconds 20 --sim-drift 50 --sim-drop 37

    Salida: 0 bien, 1 jitter de la cámara de medio fotograma o más, 2 error.
    """

    static func run(_ args: [String], env: Env) async -> Int32 {
        do {
            let o = try Parse.options(args)
            if o.help {
                env.line(help)
                return Exit.ok
            }
            switch o.command {
            case .cameras: return cameras(o, env)
            case .record, .sync: return try await take(o, env, write: o.command == .record)
            case .frame: return try await frame(o, env)
            case .montage: return try await montage(o, env)
            }
        } catch let e as CLIError {
            env.line("Error: \(e.description)")
            return Exit.error
        } catch {
            env.line("Error: \(error)")
            return Exit.error
        }
    }

    static func describe(_ f: CameraFormat) -> String {
        let rates = f.frameRates.map { $0.min == $0.max ? "\($0.max.fixed(2))" : "\($0.min.fixed(2))–\($0.max.fixed(2))" }
        return "\(f.width)×\(f.height) @ \(rates.joined(separator: ", ")) fps"
    }

    static func cameras(_ o: Options, _ env: Env) -> Int32 {
        let provider: any CameraProviding = o.simulated != nil ? SimulatedCameraProvider() : AVCameraProvider()
        let list = provider.cameras()
        let def = provider.defaultCamera()?.id
        if list.isEmpty { env.line("No hay cámaras.") }
        for c in list {
            env.line("Cámara: \(c.name)\(c.id == def ? " (por defecto)" : "")")
            env.line("  UID: \(c.id)")
            env.line("  Tipo: \(c.kind.rawValue)")
            env.line("  Formatos (\(c.formats.count)):")
            for f in c.formats { env.line("    \(describe(f))") }
        }
        return Exit.ok
    }

    static func ms(_ s: Double) -> String { (s * 1000).fixed(2) }

    /// `record` (escribe) y `sync` (solo informe).
    static func take(_ o: Options, _ env: Env, write: Bool) async throws -> Int32 {
        let seconds = o.seconds ?? 0
        let rig = try await Rig(o)
        env.line("Audio: \(rig.audioName)")
        env.line("Cámara: \(rig.camera.camera.name) (\(rig.camera.camera.id))")
        try rig.open()
        defer { rig.close() }
        // `sync` no escribe la toma de audio: la latencia no importa y no se calibra.
        if write {
            rig.session.calibration = try await rig.calibration(env)
            env.line("Calibración: \(rig.session.isCalibrated ? "válida" : "sin calibrar (latencia declarada)")")
        }

        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        let dir = env.dir.appendingPathComponent("take-\(stamp.string(from: Date()))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Backing: el WAV dado o silencio (para que haya ancla).
        let player = rig.makePlayer()
        var song = o.song.map { URL(fileURLWithPath: $0) }
        if song == nil {
            let silence = [Float](repeating: 0, count: Int((seconds + 2) * rig.fs))
            let url = dir.appendingPathComponent("silence.wav")
            try WavFile.write([silence, silence], sampleRate: rig.fs, to: url)
            song = url
        }
        try player.load(tracks: [Track(id: "backing", url: song!)])
        try player.attach(to: rig.session)

        let relay = FrameRelay()
        rig.prepareCamera()
        let format = try rig.camera.start(CameraRequest(width: o.width, height: o.height, fps: o.fps)) { relay.handle($0) }
        env.line("Formato real: \(format.width)×\(format.height) a \(format.fps.fixed(3)) fps")
        let videoURL = dir.appendingPathComponent("video.mov")
        let writer: VideoTakeWriter? = write ? try VideoTakeWriter(url: videoURL, format: format, realTime: rig.sim == nil) : nil
        let sink: any VideoFrameSink = writer ?? FrameLogSink()
        let recorder = VideoTakeRecorder(sink: sink, sampleRate: rig.fs, nominalFPS: format.fps)
        let feeder = MapFeeder(session: rig.session, recorder: recorder)

        player.seek(to: 0)
        try player.play()
        try await rig.waitForAnchor(feeder)
        relay.set(recorder)
        let wavURL = dir.appendingPathComponent("processed.wav")
        if write { try rig.session.startRecording(to: wavURL) }
        env.line("Grabando \(seconds.fixed(1)) s…")
        try await rig.advance(seconds: seconds, feeder: feeder)
        feeder.feed()
        var audioTake: RecordedTake?
        if write {
            do { audioTake = try rig.session.stopRecording() } catch {
                throw CLIError(((error as? LocalizedError)?.errorDescription ?? "\(error)"))
            }
        }
        relay.set(nil)
        rig.camera.stop()
        player.pause()
        let summary = try await writer?.finish()

        let r = recorder.report()
        if write {
            let csv = "sequence,host_s,arrival_s,song_s,written\n" + recorder.frames.map {
                "\($0.sequence),\($0.hostSeconds.fixed(6)),\($0.arrivalHostSeconds.fixed(6)),\($0.songTime.map { $0.fixed(6) } ?? ""),\($0.written ? 1 : 0)"
            }.joined(separator: "\n") + "\n"
            try csv.write(to: dir.appendingPathComponent("frames.csv"), atomically: true, encoding: .utf8)
            env.line("Vídeo: \(videoURL.path)")
            env.line("Audio: \(wavURL.path)")
            if let t = audioTake {
                env.line("Toma de audio: empieza en el tema a \(t.songStart.fixed(4)) s, \((Double(t.frameCount) / rig.fs).fixed(2)) s, calibrada: \(t.latencyCalibrated ? "sí" : "no")")
            }
            if let s = summary, let a = audioTake, let first = s.firstSongTime, let last = s.lastSongTime {
                env.line("Vídeo: \(s.framesWritten) fotogramas de \(first.fixed(4)) a \(last.fixed(4)) s del tema (empieza \(ms(first - a.songStart)) ms después del audio)")
            }
        }
        env.line("Fotogramas: \(r.framesReceived) recibidos, \(r.framesWritten) escritos, \(r.framesBeforeAnchor) antes del ancla, \(r.framesRejected) rechazados, \(rig.camera.droppedFrames) tirados por la captura")
        let halfFrame = 0.5 / format.fps
        var code = Exit.ok
        if let t = r.timing {
            env.line("Perdidos por huecos en las marcas: \(t.droppedFromGaps)")
            env.line("fps medidos: \(t.measuredFPS.fixed(4)) (reloj de la cámara \(t.cameraClockPPM.fixed(1)) ppm frente a \(format.fps.fixed(3)))")
            env.line("Jitter de las marcas: máx \(ms(t.jitterMax)) ms, RMS \(ms(t.jitterRMS)) ms (medio fotograma = \(ms(halfFrame)) ms): \(t.jitterMax < halfFrame ? "OK" : "REVISAR")")
            if t.jitterMax >= halfFrame { code = Exit.outOfTolerance }
        }
        if let a = r.audioClockPPM { env.line("Reloj del audio frente al host: \(a.fixed(2)) ppm") }
        if let d = r.cameraMinusAudioPPM { env.line("Deriva cámara − audio: \(d.fixed(1)) ppm") }
        if let l = r.arrivalLag {
            env.line("Retardo de entrega (llegada − marca): mín \(ms(l.min)) ms, mediana \(ms(l.median)) ms, máx \(ms(l.max)) ms\(rig.sim != nil ? " (simulado)" : "")")
        }
        return code
    }
}
