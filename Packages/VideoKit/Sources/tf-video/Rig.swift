// Mac: CoreAudio, AVFoundation (cámara y WAV). Windows (parte 7.11b): WASAPI compartido (`AudioSession.systemIO`),
// cámara de Media Foundation y WAV con dr_wav (`NativeAudioFile`).
import AudioKit
import Foundation
import VideoKit
#if canImport(AVFoundation)
import AVFoundation
#else
import NativeAudioFile
#endif

/// Dónde escribe la herramienta y por dónde habla.
struct Env: Sendable {
    /// `Temp/tf-video/`.
    var dir: URL
    /// `Temp/tf-audio/calibration.json` (la calibración que deja `tf-audio latency`).
    var calibrationURL: URL
    var emit: @Sendable (String) -> Void

    func line(_ text: String) { emit(text) }

    static func standard() -> Env {
        var root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let start = root
        while !FileManager.default.fileExists(atPath: root.appendingPathComponent("Packages/VideoKit/Package.swift").path) {
            let up = root.deletingLastPathComponent()
            if up == root { root = start; break }
            root = up
        }
        return Env(dir: root.appendingPathComponent("Temp/tf-video"),
                   calibrationURL: root.appendingPathComponent("Temp/tf-audio/calibration.json"),
                   emit: { print($0); fflush(stdout) })
    }
}

/// Lee la calibración guardada por `tf-audio` (mismo formato que su `StoredCalibration`).
enum SavedCalibration {
    struct Channel: Codable {
        var channel: Int
        var lagsSamples: [Double]
        var latencySamples: Double
        var spreadSamples: Double
        var peakToFloorDB: Double
        var inputPeak: Float
        var failure: LatencyFailure?
    }
    struct Stored: Codable {
        var key: LatencyCalibrationKey
        var date: Date
        var guitarIn: [Int]
        var channels: [Channel]
        var reference: ReferenceInput?
    }

    static func load(_ url: URL) -> LatencyCalibrationResult? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let s = try? dec.decode(Stored.self, from: data) else { return nil }
        return LatencyCalibrationResult(
            key: s.key, date: s.date, guitarIn: s.guitarIn,
            channels: s.channels.map {
                LatencyChannelMeasurement(channel: $0.channel, lagsSamples: $0.lagsSamples, latencySamples: $0.latencySamples,
                                          spreadSamples: $0.spreadSamples, peakToFloorDB: $0.peakToFloorDB,
                                          inputPeak: $0.inputPeak, failure: $0.failure)
            },
            reference: s.reference)
    }
}

/// Pasa el reloj del audio (marcas de host de la sesión y ancla del reproductor) al `HostTimeMap` de la toma de
/// vídeo. Es el puente que la app también necesita (VideoKit no depende de AudioKit).
@MainActor
final class MapFeeder {
    let session: AudioSession
    let recorder: VideoTakeRecorder
    private var last = Int64.min

    init(session: AudioSession, recorder: VideoTakeRecorder) {
        self.session = session
        self.recorder = recorder
    }

    /// Añade las marcas nuevas y el ancla actual. Devuelve si ya hay ancla.
    @discardableResult
    func feed() -> Bool {
        let points = session.outputHostClock(after: last)
        let anchor = session.playbackAnchor
        if let p = points.last { last = p.sampleTime }
        recorder.updateMap { m in
            for p in points { m.addClockPoint(outputSample: Double(p.sampleTime), hostSeconds: p.hostSeconds) }
            if let a = anchor {
                m.setAnchor(HostTimeMap.Anchor(songTime: a.songTime, outputSample: a.outputSample, sampleRate: a.sampleRate, rate: a.rate))
            }
        }
        return !recorder.map.anchors.isEmpty
    }
}

/// Audio (real o simulado) y cámara (real o simulada) de una pasada de `tf-video`.
@MainActor
final class Rig {
    let session: AudioSession
    let sim: SimulatedAudioIO?
    private(set) var camera: any CameraCapture
    private let simCameraConfig: SimulatedCameraCapture.Config?
    let fs: Double
    let audioName: String

    /// Escritura atómica de `frames.csv`: en Windows no (el reemplazo atómico de Foundation falla allí; brief, «Trampas»).
    #if os(Windows)
    static let atomicWrites = false
    #else
    static let atomicWrites = true
    #endif

    /// Cámaras del sistema: AVFoundation en el Mac, Media Foundation en Windows.
    static func systemCameras() -> any CameraProviding {
        #if canImport(AVFoundation)
        AVCameraProvider()
        #else
        MediaFoundationCameraProvider()
        #endif
    }

    /// Cámara por `--camera` (UID o trozo del nombre) o la del sistema.
    static func pickCamera(_ query: String?, in provider: any CameraProviding) throws -> CameraDevice {
        let all = provider.cameras()
        guard let query else {
            guard let d = provider.defaultCamera() ?? all.first else { throw CLIError("No hay cámaras.") }
            return d
        }
        if let d = all.first(where: { $0.id == query }) { return d }
        let hits = all.filter { $0.name.localizedCaseInsensitiveContains(query) }
        guard hits.count == 1 else {
            let list = all.map { "  \($0.id)  \($0.name)" }.joined(separator: "\n")
            throw CLIError(hits.isEmpty ? "Ninguna cámara coincide con «\(query)». Cámaras:\n\(list)"
                                        : "Varias cámaras coinciden con «\(query)»; usa el UID:\n\(list)")
        }
        return hits[0]
    }

    init(_ o: Options) async throws {
        let guitar = o.guitar.isEmpty && o.simulated != nil ? [1] : o.guitar
        guard !guitar.isEmpty else { throw CLIError("Falta --guitar (canales de entrada con tu guitarra, p. ej. 1 o 1,2).") }
        if let latency = o.simulated {
            fs = o.rate ?? 48_000
            let n = max(guitar.max() ?? 1, 2)
            let inputs: [SimulatedInput] = (1...n).map { ch in
                guitar.firstIndex(of: ch).map { SimulatedInput(source: $0 + 1, noiseDBFS: -60) } ?? SimulatedInput(source: nil, noiseDBFS: -60)
            }
            let io = SimulatedAudioIO(sampleRate: fs, inputs: inputs, latencySamples: latency, declaredLatencySamples: latency / 2,
                                      hostStartSeconds: HostClock.nowSeconds, hostDriftPPM: o.simDriftPPM)
            sim = io
            session = AudioSession(setup: AudioSetup(inputDeviceUID: io.inputDeviceUID, outputDeviceUID: io.outputDeviceUID,
                                                     sampleRate: fs, backingLeft: o.backing[0], backingRight: o.backing[1],
                                                     guitarIn: guitar),
                                   makeIO: { _ in io })
            audioName = "simulado (latencia \(latency.fixed(2)) muestras, deriva \(o.simDriftPPM.fixed(1)) ppm)"
            let cfg = SimulatedCameraCapture.Config(delaySeconds: o.simCameraDelayMs / 1000, dropEvery: o.simDropEvery,
                                                    pixels: o.command == .record)
            simCameraConfig = cfg
            camera = SimulatedCameraCapture(config: cfg, originHostSeconds: io.hostStartSeconds)
            return
        }
        guard let inQuery = o.input, let outQuery = o.output else {
            throw CLIError("Faltan --in y --out (UID o trozo del nombre; mira `tf-audio devices`).")
        }
        #if !canImport(AVFoundation)
        // Windows: endpoints WASAPI por id o trozo del nombre; la sesión abre WASAPI compartido (`systemIO`).
        guard await MediaFoundationCameraProvider.ensureAccess() else {
            throw CLIError("Sin permiso de cámara: concédelo en Configuración > Privacidad y seguridad > Cámara (aplicaciones de escritorio).")
        }
        let endpoints: [WASAPIDeviceInfo]
        do { endpoints = try WASAPIAudioIO.devices() } catch { throw CLIError("No se pudieron listar los dispositivos WASAPI: \(error)") }
        func endpoint(_ q: String, _ flow: WASAPIFlow, _ role: String) throws -> WASAPIDeviceInfo {
            let list = endpoints.filter { $0.flow == flow }
            if let d = list.first(where: { $0.id == q }) { return d }
            let hits = list.filter { $0.name.localizedCaseInsensitiveContains(q) }
            guard hits.count == 1 else {
                let names = list.map { "  \($0.id)  \($0.name)" }.joined(separator: "\n")
                throw CLIError("No hay un único dispositivo de \(role) que coincida con «\(q)». Dispositivos de \(role):\n\(names)")
            }
            return hits[0]
        }
        let inDev = try endpoint(inQuery, .capture, "entrada")
        let outDev = try endpoint(outQuery, .render, "salida")
        fs = o.rate ?? outDev.mix.sampleRate
        sim = nil
        audioName = "\(inDev.name) → \(outDev.name)"
        session = AudioSession(setup: AudioSetup(inputDeviceUID: inDev.id, outputDeviceUID: outDev.id, sampleRate: fs,
                                                 backingLeft: o.backing[0], backingRight: o.backing[1], guitarIn: guitar))
        let cam = try Self.pickCamera(o.camera, in: MediaFoundationCameraProvider())
        camera = try MediaFoundationCameraCapture(cameraID: cam.id)
        simCameraConfig = nil
        #else
        guard await CoreAudioIO.ensureInputPermission() else {
            throw CLIError("Sin permiso de entrada de audio: concédelo a la terminal en Ajustes del Sistema > Privacidad > Micrófono.")
        }
        guard await AVCameraProvider.ensureAccess() else {
            throw CLIError("Sin permiso de cámara: concédelo a la terminal en Ajustes del Sistema > Privacidad > Cámara.")
        }
        CoreAudioIO.removeOrphanAggregates()
        let provider = CoreAudioDeviceProvider()
        func device(_ q: String, _ list: [AudioDevice], _ role: String) throws -> AudioDevice {
            if let d = list.first(where: { $0.uid == q }) { return d }
            let hits = list.filter { $0.name.localizedCaseInsensitiveContains(q) }
            guard hits.count == 1 else { throw CLIError("No hay un único dispositivo de \(role) que coincida con «\(q)».") }
            return hits[0]
        }
        let inDev = try device(inQuery, provider.inputDevices(), "entrada")
        let outDev = try device(outQuery, provider.outputDevices(), "salida")
        fs = o.rate ?? outDev.nominalSampleRate ?? inDev.nominalSampleRate ?? 48_000
        sim = nil
        audioName = "\(inDev.name) → \(outDev.name)"
        session = AudioSession(setup: AudioSetup(inputDeviceUID: inDev.uid, outputDeviceUID: outDev.uid, sampleRate: fs,
                                                 backingLeft: o.backing[0], backingRight: o.backing[1], guitarIn: guitar))
        let cam = try Self.pickCamera(o.camera, in: AVCameraProvider())
        camera = try AVCameraCapture(cameraID: cam.id)
        simCameraConfig = nil
        #endif
    }

    func open() throws {
        do { try session.open() } catch { throw CLIError(((error as? LocalizedError)?.errorDescription ?? "\(error)")) }
    }

    func close() {
        camera.stop()
        session.close()
    }

    /// Simulado: la cámara empieza a capturar ahora (en la hora de host del audio), no al abrir: si no, al
    /// arrancar entregaría de golpe todo lo «capturado» durante la calibración (medido: 20 s en `record`).
    func prepareCamera() {
        guard let sim, let cfg = simCameraConfig else { return }
        camera = SimulatedCameraCapture(config: cfg, originHostSeconds: sim.hostSeconds(atOutputSample: Double(sim.sampleTime)))
    }

    func makePlayer() -> StudyPlayer { sim != nil ? StudyPlayer(offlineWith: nil) : StudyPlayer() }

    /// Un ciclo del simulador: audio, vaciado de la captura y la cámara simulada hasta la hora de host del audio
    /// (así la cámara nunca se queda atrás y el retardo de entrega simulado es el de un bloque).
    private func step(_ sim: SimulatedAudioIO) {
        sim.pump()
        session.flushCapture()
        (camera as? SimulatedCameraCapture)?.advance(toHostSeconds: sim.hostSeconds(atOutputSample: Double(sim.sampleTime)))
    }

    /// Simulado: calibra conduciendo el simulador; real: la calibración de `tf-audio` si vale para esta clave.
    ///
    /// `calibrateLatency` mira su progreso cada 20 ms de reloj real bajo `consumerLock`, el mismo cerrojo que toma
    /// `flushCapture`, y luego analiza (segundos en depuración): bombeando sin pausa, el simulador corría ~145 s de
    /// audio de más (13 640 bloques). Se bombean los bloques que pide el barrido, con 1 ms de pausa, y luego solo
    /// se espera; si no acaba, un bloque más cada 100 ms.
    func calibration(_ env: Env) async throws -> LatencyCalibrationResult? {
        guard let sim else { return SavedCalibration.load(env.calibrationURL) }
        final class Box: @unchecked Sendable {
            let lock = NSLock()
            var value: Result<LatencyCalibrationResult, any Error>?
            var started = false
        }
        let box = Box()
        let s = session
        Task.detached {
            let r: Result<LatencyCalibrationResult, any Error>
            box.lock.withLock { box.started = true }
            do { r = .success(try await s.calibrateLatency()) } catch { r = .failure(error) }
            box.lock.withLock { box.value = r }
        }
        // Bloques que necesita el barrido (más margen); luego solo se espera al análisis.
        let probe = LatencyProbe(sampleRate: fs)
        let needed = (probe.captureFrames + probe.maxLatencyFrames) / sim.format.bufferFrames + 16
        var n = 0, idle = 0
        while box.lock.withLock({ box.value }) == nil {
            guard box.lock.withLock({ box.started }) else {
                try await Task.sleep(for: .milliseconds(1))
                continue
            }
            if n < needed || idle >= 50 {
                step(sim)
                n += 1
                idle = 0
                // Pausa en cada bloque: sin ella el vaciado acapara `consumerLock` y `calibrateLatency` no llega a
                // leer su progreso.
                try await Task.sleep(for: .milliseconds(1))
            } else {
                try await Task.sleep(for: .milliseconds(2))
                idle += 1
            }
            if n > 400_000 { throw CLIError("La calibración simulada no termina.") }
        }
        return try box.lock.withLock({ box.value })!.get()
    }

    /// Deja pasar `seconds` alimentando el mapa. Simulado: bombea bloques y adelanta la cámara a la hora de host
    /// del audio (más rápido que el tiempo real). Real: espera.
    func advance(seconds: Double, feeder: MapFeeder?) async throws {
        if let sim {
            let begin = sim.sampleTime
            var blocks = 0
            while sim.sampleTime - begin < Int64(seconds * fs), sim.isRunning {
                step(sim)
                blocks += 1
                // La app consultaría el reloj cada pocos ms: aquí, cada 8 bloques (85 ms a 48 kHz).
                if blocks % 8 == 0 { feeder?.feed() }
            }
            return
        }
        let start = Date()
        while Date().timeIntervalSince(start) < seconds, session.interruption == nil {
            feeder?.feed()
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Espera al ancla del reproductor (simulado: un bloque).
    func waitForAnchor(_ feeder: MapFeeder) async throws {
        for _ in 0..<400 {
            if let sim { step(sim) }
            if feeder.feed() { return }
            if sim == nil { try await Task.sleep(for: .milliseconds(5)) }
        }
        throw CLIError("El reproductor no publicó su ancla.")
    }
}

/// Recibe los fotogramas antes de que exista el grabador (la cámara arranca antes que el escritor).
final class FrameRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var target: VideoTakeRecorder?
    func set(_ r: VideoTakeRecorder?) { lock.withLock { target = r } }
    func handle(_ f: CameraFrame) { lock.withLock { target }?.handle(f) }
}

/// WAV float32 sencillo (el de las tomas es interno de AudioKit).
enum WavFile {
    static func write(_ channels: [[Float]], sampleRate: Double, to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        #if !canImport(AVFoundation)
        try NativeAudioFile.write(url, channels: channels, sampleRate: sampleRate, format: .float32)
        #else
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: channels.count,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames = channels.first?.count ?? 0
        let chunk = 65_536
        let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(chunk))!
        var at = 0
        while at < frames {
            let n = min(chunk, frames - at)
            buf.frameLength = AVAudioFrameCount(n)
            for (c, ch) in channels.enumerated() {
                ch.withUnsafeBufferPointer { buf.floatChannelData![c].update(from: $0.baseAddress! + at, count: n) }
            }
            try file.write(from: buf)
            at += n
        }
        #endif
    }
}
