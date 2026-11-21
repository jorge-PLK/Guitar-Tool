// tf-audio mide con el dispositivo y el reproductor. En Windows, dispositivos WASAPI (parte 7.10b) o `--simulated`; el
// reproductor es el portátil (parte 7.6).
import AudioKit
#if canImport(AVFoundation)
import AVFoundation
#else
import NativeAudioFile
#endif
import Foundation

/// Dónde escribe la herramienta y por dónde habla.
struct Env: Sendable {
    var dir: URL
    var emit: @Sendable (String) -> Void

    func line(_ text: String) { emit(text) }

    var calibrationURL: URL { dir.appendingPathComponent("calibration.json") }

    /// `Temp/tf-audio/` de la raíz del repo (se sube desde el directorio actual hasta dar con `Packages/AudioKit`).
    static func standard() -> Env {
        var root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let start = root
        while !FileManager.default.fileExists(atPath: root.appendingPathComponent("Packages/AudioKit/Package.swift").path) {
            let up = root.deletingLastPathComponent()
            if up == root { root = start; break }
            root = up
        }
        return Env(dir: root.appendingPathComponent("Temp/tf-audio"), emit: { print($0); fflush(stdout) })
    }
}

/// Calibración guardada en `Temp/tf-audio/calibration.json` para que `verify` y `record` la usen.
struct StoredCalibration: Codable {
    struct Channel: Codable {
        var channel: Int
        var lagsSamples: [Double]
        var latencySamples: Double
        var spreadSamples: Double
        var peakToFloorDB: Double
        var inputPeak: Float
        var failure: LatencyFailure?
    }
    var key: LatencyCalibrationKey
    var date: Date
    var guitarIn: [Int]
    var channels: [Channel]
    var reference: ReferenceInput?

    init(_ r: LatencyCalibrationResult) {
        key = r.key
        date = r.date
        guitarIn = r.guitarIn
        reference = r.reference
        channels = r.channels.map {
            Channel(channel: $0.channel, lagsSamples: $0.lagsSamples, latencySamples: $0.latencySamples,
                    spreadSamples: $0.spreadSamples, peakToFloorDB: $0.peakToFloorDB, inputPeak: $0.inputPeak, failure: $0.failure)
        }
    }

    var result: LatencyCalibrationResult {
        LatencyCalibrationResult(
            key: key, date: date, guitarIn: guitarIn,
            channels: channels.map {
                LatencyChannelMeasurement(channel: $0.channel, lagsSamples: $0.lagsSamples, latencySamples: $0.latencySamples,
                                          spreadSamples: $0.spreadSamples, peakToFloorDB: $0.peakToFloorDB,
                                          inputPeak: $0.inputPeak, failure: $0.failure)
            },
            reference: reference)
    }

    static func save(_ r: LatencyCalibrationResult, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(StoredCalibration(r)).write(to: url)
    }

    static func load(from url: URL) -> LatencyCalibrationResult? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode(StoredCalibration.self, from: data))?.result
    }
}

/// WAV float32 sencillo (el de las tomas es interno de AudioKit).
enum WavFile {
    static func write(_ channels: [[Float]], sampleRate: Double, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
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

    /// Primer canal del WAV y su frecuencia.
    static func readFirstChannel(_ url: URL) throws -> (samples: [Float], sampleRate: Double) {
        #if !canImport(AVFoundation)
        let d = try NativeAudioFile.read(url)
        return (d.channels.first ?? [], d.sampleRate)
        #else
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        var out: [Float] = []
        out.reserveCapacity(Int(file.length))
        let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 65_536)!
        while file.framePosition < file.length {
            try file.read(into: buf, frameCount: 65_536)
            if buf.frameLength == 0 { break }
            out.append(contentsOf: UnsafeBufferPointer(start: buf.floatChannelData![0], count: Int(buf.frameLength)))
        }
        return (out, file.processingFormat.sampleRate)
        #endif
    }

    static func sampleRate(of url: URL) throws -> Double {
        #if !canImport(AVFoundation)
        try AudioFileReader(url: url).sampleRate
        #else
        try AVAudioFile(forReading: url).processingFormat.sampleRate
        #endif
    }
}

final class IOBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: (any AudioIO)?
    func set(_ io: any AudioIO) { lock.withLock { value = io } }
    func get() -> (any AudioIO)? { lock.withLock { value } }
    func clear() { lock.withLock { value = nil } }
}

final class ResultBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T?
    func set(_ v: T) { lock.withLock { value = v } }
    func get() -> T? { lock.withLock { value } }
}

/// Una sesión de audio con su dispositivo (real o simulado) y la forma de hacerla avanzar: el hardware corre
/// solo; el simulador se conduce a mano (`pump`), más rápido que el tiempo real.
@MainActor
final class Rig {
    let session: AudioSession
    let sim: SimulatedAudioIO?
    let ioBox: IOBox
    let setup: AudioSetup
    let inputName: String
    let outputName: String
    /// Modo WASAPI (solo Windows con dispositivos reales; `nil` en el Mac y con `--simulated`).
    private(set) var mode: WASAPIShareMode?
    /// Avisos sobre los dispositivos elegidos, para escribirlos tras «Entrada»/«Salida».
    private(set) var notes: [String] = []

    /// La calibración exclusiva va aparte: `LatencyCalibrationKey` no lleva el modo, y compartido y exclusivo pueden
    /// dar el mismo periodo con latencias distintas (cómo lo guarda la app se decide en el paso 8).
    func calibrationURL(_ env: Env) -> URL {
        mode == .exclusive ? env.dir.appendingPathComponent("calibration-exclusive.json") : env.calibrationURL
    }

    /// Mínimo que admite `SimulatedAudioIO` (semianchura del sinc, 32, más 1).
    static let minLoopSamples = 33.0

    /// Un canal de entrada por la salida del backing, rig y referencia opcionales, como en los tests de la fachada.
    static func simulatedIO(latency: Double, rig: Double?, guitar: [Int], sampleRate fs: Double) throws -> SimulatedAudioIO {
        let rigOn = rig != nil
        let rigDelay = rig ?? 0
        let base = latency - rigDelay
        guard base >= minLoopSamples else {
            throw CLIError("--simulated \(latency.fixed(2)) menos --sim-rig \(rigDelay.fixed(2)) deja menos de \(Int(minLoopSamples)) muestras.")
        }
        let n = max(guitar.max() ?? 1, 2)
        var inputs: [SimulatedInput] = (1...n).map { ch in
            if let pos = guitar.firstIndex(of: ch) {
                return SimulatedInput(source: pos + 1, extraDelaySamples: rigDelay, drive: rigOn ? 2 : 0, gain: rigOn ? 0.5 : 1,
                                      noiseDBFS: -60)
            }
            return SimulatedInput(source: nil, noiseDBFS: -60)
        }
        if rigOn { inputs.append(SimulatedInput(source: 1, noiseDBFS: -60)) }
        // La clave de calibración lleva los UID: con la latencia dentro, una calibración simulada no vale para otra.
        let tag = String(format: "%.2f-%.2f", latency, rigDelay)
        return SimulatedAudioIO(sampleRate: fs, inputs: inputs, latencySamples: base, declaredLatencySamples: latency / 2,
                                inputDeviceUID: "sim-in-" + tag, outputDeviceUID: "sim-out-" + tag)
    }

    init(_ o: Options) async throws {
        let guitar = o.guitar.isEmpty && o.simulated != nil ? [1] : o.guitar
        guard !guitar.isEmpty else { throw CLIError("Falta --guitar (canales de entrada con tu guitarra, p. ej. 1 o 1,2).") }
        let box = IOBox()
        ioBox = box
        if let latency = o.simulated {
            let fs = o.rate ?? 48_000
            let io = try Self.simulatedIO(latency: latency, rig: o.simRig, guitar: guitar, sampleRate: fs)
            sim = io
            setup = AudioSetup(inputDeviceUID: io.inputDeviceUID, outputDeviceUID: io.outputDeviceUID, sampleRate: fs,
                               backingLeft: o.backing[0], backingRight: o.backing[1], guitarIn: guitar)
            inputName = "simulado"
            outputName = "simulado"
            session = AudioSession(setup: setup, makeIO: { _ in io })
            box.set(io)
            return
        }
        guard let inQuery = o.input, let outQuery = o.output else {
            throw CLIError("Faltan --in y --out (UID o trozo del nombre; mira `tf-audio devices`).")
        }
        #if os(Windows)
        // En Windows entrada y salida del mismo aparato son endpoints con ids distintos: se reciben los dos y se asume
        // que son el mismo aparato (un reloj, `clock = .single`). Cómo lo marca `AudioSetup` en la app: paso 8.
        let list: [WASAPIDeviceInfo]
        do { list = try WASAPIAudioIO.devices() } catch {
            throw CLIError(((error as? LocalizedError)?.errorDescription ?? "\(error)"))
        }
        let captures = list.filter { $0.flow == .capture }
        let renders = list.filter { $0.flow == .render }
        let inMatch = try Parse.device(inQuery, in: captures.enumerated().map { WASAPIListing.audioDevice($1, index: $0) },
                                       role: "entrada")
        let outMatch = try Parse.device(outQuery, in: renders.enumerated().map { WASAPIListing.audioDevice($1, index: $0) },
                                        role: "salida")
        let inDev = captures[Int(inMatch.id)]
        let outDev = renders[Int(outMatch.id)]
        let wasapiMode = o.mode ?? .shared
        let fs = o.rate ?? outDev.mix.sampleRate
        sim = nil
        mode = wasapiMode
        inputName = "\(inDev.name) (\(inDev.id)) · driver \(WASAPIListing.driverText(inDev.driver))"
        outputName = "\(outDev.name) (\(outDev.id)) · driver \(WASAPIListing.driverText(outDev.driver))"
        var warnings: [String] = []
        if WASAPIListing.sameAdapter(inDev, outDev) == false {
            warnings.append("AVISO: entrada y salida en adaptadores distintos (\(inDev.driver.adapterInstance) y "
                            + "\(outDev.driver.adapterInstance)): dos relojes, WASAPI no corrige la deriva.")
        }
        if wasapiMode == .shared, abs(inDev.mix.sampleRate - fs) >= 0.5 || abs(outDev.mix.sampleRate - fs) >= 0.5 {
            warnings.append("En compartido la entrada (\(Int(inDev.mix.sampleRate)) Hz) y la salida (\(Int(outDev.mix.sampleRate)) Hz) "
                            + "tienen que estar a \(Int(fs)) Hz: cámbialo en Panel de sonido > Propiedades > Opciones avanzadas.")
        }
        notes = warnings
        let options = WASAPIAudioIO.Options(mode: wasapiMode, periodFrames: o.period)
        setup = AudioSetup(inputDeviceUID: inDev.id, outputDeviceUID: outDev.id, sampleRate: fs,
                           backingLeft: o.backing[0], backingRight: o.backing[1], guitarIn: guitar)
        session = AudioSession(setup: setup, makeIO: { s in
            let io = try WASAPIAudioIO(setup: s, options: options)
            box.set(io)
            return io
        })
        #elseif !canImport(AVFoundation)
        throw CLIError("Dispositivos reales (\(inQuery) → \(outQuery)): sin E/S de audio en esta plataforma. Usa --simulated.")
        #else
        guard o.mode == nil, o.period == nil else {
            throw CLIError("--mode y --period solo existen en Windows (WASAPI).")
        }
        guard await CoreAudioIO.ensureInputPermission() else {
            throw CLIError("Sin permiso de entrada de audio: concédelo a la terminal en Ajustes del Sistema > Privacidad > Micrófono.")
        }
        CoreAudioIO.removeOrphanAggregates()
        let provider = CoreAudioDeviceProvider()
        let inDev = try Parse.device(inQuery, in: provider.inputDevices(), role: "entrada")
        let outDev = try Parse.device(outQuery, in: provider.outputDevices(), role: "salida")
        let fs = o.rate ?? outDev.nominalSampleRate ?? inDev.nominalSampleRate ?? 48_000
        sim = nil
        inputName = "\(inDev.name) (\(inDev.uid))"
        outputName = "\(outDev.name) (\(outDev.uid))"
        setup = AudioSetup(inputDeviceUID: inDev.uid, outputDeviceUID: outDev.uid, sampleRate: fs,
                           backingLeft: o.backing[0], backingRight: o.backing[1], guitarIn: guitar)
        session = AudioSession(setup: setup, makeIO: { s in
            let io = try AudioSession.coreAudio(s)
            box.set(io)
            return io
        })
        #endif
    }

    func open() throws {
        do { try session.open() } catch { throw CLIError(((error as? LocalizedError)?.errorDescription ?? "\(error)")) }
        if let io = sim { ioBox.set(io) }
    }

    func close() {
        session.close()
        #if os(Windows)
        // Suelta también el flujo WASAPI (se cierra en su `deinit`): en exclusivo, el siguiente `--restarts` lo reabre.
        if sim == nil { ioBox.clear() }
        #endif
    }

    var fs: Double { setup.sampleRate }

    func makePlayer() -> StudyPlayer { sim != nil ? StudyPlayer(offlineWith: nil) : StudyPlayer() }

    func calibrate() async throws -> LatencyCalibrationResult {
        guard let sim else { return try await session.calibrateLatency() }
        let box = ResultBox<Result<LatencyCalibrationResult, any Error>>()
        let s = session
        Task.detached {
            do { box.set(.success(try await s.calibrateLatency())) } catch { box.set(.failure(error)) }
        }
        var n = 0
        while box.get() == nil {
            sim.pump()
            session.flushCapture()
            n += 1
            if n % 32 == 0 { try await Task.sleep(for: .milliseconds(1)) }
            if n > 400_000 { throw CLIError("La calibración simulada no termina.") }
        }
        do { return try box.get()!.get() } catch {
            throw CLIError(((error as? LocalizedError)?.errorDescription ?? "\(error)"))
        }
    }

    /// Deja pasar `seconds` de audio (con el simulador, sin esperar). Para antes si la sesión se corta.
    func advance(seconds: Double) async throws {
        if let sim {
            let begin = sim.sampleTime
            let end = Int64(seconds * fs)
            while sim.sampleTime - begin < end, sim.isRunning {
                sim.pump()
                session.flushCapture()
            }
            return
        }
        let start = Date()
        while Date().timeIntervalSince(start) < seconds, session.interruption == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Da tiempo al reproductor alojado a publicar su ancla antes de grabar.
    func settle() async throws {
        if let sim {
            sim.pump()
            session.flushCapture()
        } else {
            try await Task.sleep(for: .milliseconds(300))
        }
    }
}

