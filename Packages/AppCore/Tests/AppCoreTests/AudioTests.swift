import AudioKit
import Foundation
import Store
import XCTest
@testable import AppCore

/// W2-C: `AudioController` y `audio.*` con E/S simulada (nunca se abre un dispositivo real) y perfiles temporales.
@MainActor
final class AudioTests: XCTestCase {
    final class Events: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [(name: String, payload: [String: Any])] = []
        func add(_ json: String) {
            guard let o = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any],
                  let name = o["event"] as? String else { return }
            lock.withLock { items.append((name, o["payload"] as? [String: Any] ?? [:])) }
        }
        func all(_ name: String) -> [[String: Any]] { lock.withLock { items.filter { $0.name == name }.map(\.payload) } }
    }

    func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("audio-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: d) }
        return d
    }

    func makeController(provider: SimulatedDeviceProvider? = nil, automatic: Bool = true,
                        profile: EquipmentProfile? = nil) throws -> (AudioController, ProfileStore) {
        let store = ProfileStore(url: try tempDir().appendingPathComponent("profile.json"))
        if let profile { try store.save(profile) }
        let c = AudioController(provider: provider ?? AudioController.simulatedProvider(), store: store,
                                makeIO: AudioController.simulatedIO(automatic: automatic))
        c.start()
        return (c, store)
    }

    func guitarSetup(_ c: AudioController) throws {
        try c.updateAudio { $0.chooseInput(AudioController.simulatedInputUID); $0.guitarIn = [1] }
    }

    func sleep(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9)) }

    // MARK: Proveedor WASAPI (mapeo puro; el enumerador real es solo de Windows)

    func testWASAPIProviderMapsEndpoints() {
        func info(_ id: String, _ flow: WASAPIFlow, ch: Int, rate: Double, def: Bool = false) -> WASAPIDeviceInfo {
            WASAPIDeviceInfo(id: id, name: "N-\(id)", flow: flow, isDefault: def,
                             mix: WASAPIFormat(sampleRate: rate, channels: ch, bits: 32, validBits: 32, isFloat: true),
                             defaultPeriod100ns: 100_000, minimumPeriod100ns: 30_000, engine: nil, exclusiveFloat: true)
        }
        let list = [info("out1", .render, ch: 2, rate: 48000, def: true), info("in1", .capture, ch: 4, rate: 44100)]
        let p = WASAPIDeviceProvider(enumerate: { list })
        XCTAssertEqual(p.outputDevices().map(\.uid), ["out1"])
        XCTAssertEqual(p.inputDevices().map(\.uid), ["in1"])
        XCTAssertEqual(p.inputDevices().first?.inputChannels, 4)
        XCTAssertEqual(p.inputDevices().first?.outputChannels, 0)
        XCTAssertEqual(p.defaultOutputDevice()?.uid, "out1")
        XCTAssertEqual(p.outputDevices().first?.sampleRates, [48000])
        XCTAssertTrue(p.requestSampleRate(48000, deviceUID: "out1"))
        XCTAssertFalse(p.requestSampleRate(44100, deviceUID: "out1"), "Windows no cambia la frecuencia del dispositivo")
        XCTAssertFalse(p.requestSampleRate(44100, deviceUID: "nope"))
    }

    func testWASAPIProviderPollsChanges() async throws {
        final class Box: @unchecked Sendable { var list: [WASAPIDeviceInfo] = []; let lock = NSLock(); var fired = 0 }
        let box = Box()
        let dev = WASAPIDeviceInfo(id: "a", name: "A", flow: .render, isDefault: true,
                                   mix: WASAPIFormat(sampleRate: 48000, channels: 2, bits: 32, validBits: 32, isFloat: true),
                                   defaultPeriod100ns: 100_000, minimumPeriod100ns: 30_000, engine: nil, exclusiveFloat: true)
        box.list = [dev]
        let p = WASAPIDeviceProvider(pollInterval: 0.05, enumerate: { box.lock.withLock { box.list } })
        p.setChangeHandler { box.lock.withLock { box.fired += 1 } }
        await sleep(0.2)
        XCTAssertEqual(box.lock.withLock { box.fired }, 0, "sin cambios no avisa")
        box.lock.withLock { box.list = [] }
        await sleep(0.3)
        XCTAssertEqual(box.lock.withLock { box.fired }, 1, "avisa una vez al desaparecer el dispositivo")
        p.setChangeHandler(nil)
    }

    // MARK: Abrir y cerrar

    func testOpensAndClosesWithSettings() async throws {
        let (c, store) = try makeController()
        XCTAssertNil(c.session, "sin ajustes no hay sesión")
        XCTAssertEqual(c.deviceBlock?.message, "Elige un dispositivo de entrada en Ajustes · Audio.")
        try guitarSetup(c)
        XCTAssertEqual(c.session?.isOpen, true)
        XCTAssertNil(c.sessionError)
        XCTAssertEqual(try store.load().audio?.guitarIn, [1], "se guarda en el perfil")
        XCTAssertNil(c.deviceBlock)
        try c.updateAudio { $0.guitarIn = nil }
        XCTAssertNil(c.session, "sin guitarra y sin medidores la sesión se cierra")
        c.metersVisible = true
        XCTAssertEqual(c.session?.isOpen, true, "con los medidores a la vista se abre sin guitarra")
        c.metersVisible = false
        XCTAssertNil(c.session)
    }

    func testSettingsChangeReopensAtNewRate() throws {
        let (c, _) = try makeController()
        try guitarSetup(c)
        XCTAssertEqual(c.session?.sampleRate, 44100)
        try c.updateAudio(workingRate: 48000) { _ in }
        XCTAssertEqual(c.workingRate, 48000)
        XCTAssertEqual(c.session?.sampleRate, 48000, "el proveedor aceptó 48 kHz y la sesión se rehízo")
    }

    func testRateMismatchBlocksSession() throws {
        let provider = AudioController.simulatedProvider(rate: 44100)
        let fixed = SimulatedDeviceProvider(devices: provider.inputDevices() + provider.outputDevices(), defaultID: 2,
                                            fixedRateUIDs: [AudioController.simulatedInputUID])
        let (c, _) = try makeController(provider: fixed, profile: EquipmentProfile(workingSampleRate: 48000))
        try guitarSetup(c)
        XCTAssertEqual(c.mismatchedRate, 44100)
        XCTAssertNil(c.session)
        let s = AudioService.settingsResult(c)
        XCTAssertEqual(s.rateMismatch?.canUseDeviceRate, true)
        XCTAssertEqual(s.rateMismatch?.useLabel, "Usar 44,1 kHz como frecuencia de trabajo")
        XCTAssertEqual(s.rateMismatch?.message, "El dispositivo está a 44,1 kHz y la frecuencia de trabajo es 48 kHz")
        XCTAssertNotNil(s.calibrateBlock)
    }

    func testDisconnectedDeviceKeepsItsName() throws {
        let (c, _) = try makeController()
        try guitarSetup(c)
        try c.modifyProfile { $0.audio?.inputDeviceUID = "ya-no-esta" }
        let d = AudioService.devicesResult(c)
        XCTAssertEqual(d.inputs.map(\.label), ["Entrada simulada · 2 can.", "Dispositivo elegido · desconectado"])
        XCTAssertEqual(d.inputs.last?.connected, false)
        XCTAssertNil(c.session)
    }

    /// M-3a: sin dispositivo presente no hay canales elegibles; con él, el número de canales y las opciones.
    func testChannelsOnlyOfferedWithPresentDevice() throws {
        let (c, _) = try makeController()
        var s = AudioService.settingsResult(c)
        XCTAssertEqual(s.inputChannelCount, 0, "sin entrada elegida")
        XCTAssertTrue(s.guitarChoices.isEmpty)
        XCTAssertEqual(s.outputChannelCount, 2, "sin salida elegida suena la del sistema")
        try guitarSetup(c)
        s = AudioService.settingsResult(c)
        XCTAssertEqual(s.inputChannelCount, 2)
        XCTAssertFalse(s.guitarChoices.isEmpty)
        try c.modifyProfile { $0.audio?.inputDeviceUID = "ya-no-esta"; $0.audio?.outputDeviceUID = "ya-no-esta" }
        s = AudioService.settingsResult(c)
        XCTAssertEqual(s.inputChannelCount, 0, "elegida pero desconectada")
        XCTAssertEqual(s.outputChannelCount, 0)
        XCTAssertTrue(s.guitarChoices.isEmpty)
        XCTAssertTrue(s.backingChoices.isEmpty)
    }

    /// M-3a: los canales se recuerdan por dispositivo y se restauran al volver a elegirlo.
    func testChannelsAreRestoredPerDevice() throws {
        let (c, store) = try makeController()
        try guitarSetup(c)
        try c.updateAudio { $0.setGuitar([2]) }
        try c.updateAudio { $0.chooseInput("otro") }
        XCTAssertNil(c.settings?.guitarIn, "dispositivo nuevo: sin asignar")
        try c.updateAudio { $0.chooseInput(AudioController.simulatedInputUID) }
        XCTAssertEqual(try store.load().audio?.guitarIn, [2])
        XCTAssertEqual(try store.load().audio?.guitarByDevice[AudioController.simulatedInputUID], [2])
    }

    /// M-3c: los pares solo se ofrecen si caben en el dispositivo de entrada.
    func testGuitarChoicesOnlyOfferPairsThatFit() {
        let labels = { (n: Int, g: [Int]?) -> [String] in
            var a = AudioSettings(); a.guitarIn = g
            return ChannelChoices.guitar(channels: n, current: a).map(\.label)
        }
        XCTAssertEqual(labels(1, nil), ["Sin asignar", "Entrada 1"])
        XCTAssertEqual(labels(2, nil), ["Sin asignar", "Entrada 1", "Entrada 2", "Entradas 1 y 2"])
        XCTAssertEqual(labels(1, [1, 2]), ["Sin asignar", "Entrada 1"], "el actual [1, 2] no cabe en 1 canal")
    }

    /// M-3d: una salida de 1 canal solo ofrece «Salida 1 · mono»; con 2 o más, los pares estéreo de siempre.
    func testBackingChoicesMonoOutput() {
        let a = AudioSettings()
        XCTAssertEqual(ChannelChoices.backing(channels: 1, current: a).map(\.label), ["Salida 1 · mono"])
        XCTAssertEqual(ChannelChoices.backing(channels: 1, current: a).map(\.value), [ChannelPair(left: 1, right: 1)])
        XCTAssertEqual(ChannelChoices.backing(channels: 2, current: a).map(\.label), ["Salidas 1 y 2 · estéreo"])
        XCTAssertEqual(ChannelChoices.backing(channels: 4, current: a).map(\.label),
                       ["Salidas 1 y 2 · estéreo", "Salidas 3 y 4 · estéreo"])
    }

    /// M-3d: un dispositivo nuevo de 1 canal queda en mono (también un 1-2 recordado), y se recuerda por dispositivo.
    func testMonoOutputDeviceDefaultsToMono() throws {
        let mono = AudioDevice(id: 9, uid: "mono-out", name: "Altavoz mono", outputChannels: 1)
        let provider = SimulatedDeviceProvider(devices: [mono], defaultID: nil)
        let (c, store) = try makeController(provider: provider)
        try c.updateAudio { $0.chooseOutput("mono-out") }
        XCTAssertEqual(c.settings?.backingOut, .mono)
        XCTAssertEqual(try store.load().audio?.backingByDevice["mono-out"], .mono)
    }

    /// M-3c: con un dispositivo de 1 canal, una guitarra [1, 2] queda sin asignar (respuesta y perfil).
    func testGuitarPairIsDroppedOnMonoInput() throws {
        let mono = AudioDevice(id: 9, uid: "mono", name: "Micro mono", inputChannels: 1)
        let provider = SimulatedDeviceProvider(devices: [mono], defaultID: nil)
        let (c, store) = try makeController(provider: provider)
        try c.updateAudio { $0.chooseInput("mono"); $0.setGuitar([1, 2]) }
        XCTAssertNil(c.settings?.guitarIn)
        XCTAssertNil(try store.load().audio?.guitarIn)
        let s = AudioService.settingsResult(c)
        XCTAssertNil(s.guitarIn)
        XCTAssertEqual(s.guitarChoices.map(\.label), ["Sin asignar", "Entrada 1"])
    }

    // MARK: Niveles

    func testMeterLevelMapping() {
        XCTAssertEqual(AudioController.level(db: -60), 0)
        XCTAssertEqual(AudioController.level(db: -90), 0)
        XCTAssertEqual(AudioController.level(db: -30), 0.5, accuracy: 1e-6)
        XCTAssertEqual(AudioController.level(db: 3), 1)
    }

    func testInputLevelsAtMost30Hz() async throws {
        let (c, _) = try makeController()
        try c.updateAudio { $0.chooseInput(AudioController.simulatedInputUID) }
        final class Count: @unchecked Sendable { var n = 0; var last: [Float]? }
        let count = Count()
        c.onLevels = { levels, _ in count.n += 1; count.last = levels }
        c.metersVisible = true
        await sleep(1.0)
        c.metersVisible = false
        XCTAssertGreaterThan(count.n, 5, "los medidores corren")
        XCTAssertLessThanOrEqual(count.n, 31, "<= 30 Hz")
        XCTAssertNil(c.inputLevels)
        // Con la sesión simulada la entrada tiene 2 canales.
        c.metersVisible = true
        c.sampleMeters()
        XCTAssertEqual(c.inputLevels?.count, 2)
        XCTAssertTrue(c.inputLevels?.allSatisfy { (0...1).contains($0) } ?? false)
        c.metersVisible = false
    }

    // MARK: Calibración

    func testSimulatedCalibrationSavesAndRestores() async throws {
        let (c, store) = try makeController()
        try guitarSetup(c)
        final class Phases: @unchecked Sendable { var list: [AudioController.CalibrationPhase] = [] }
        let phases = Phases()
        c.onCalibration = { phases.list.append($0) }
        XCTAssertFalse(c.calibrationValid)
        await c.calibrate()
        guard case .finished(.success(let s)) = c.calibrationPhase else { return XCTFail("\(c.calibrationPhase)") }
        XCTAssertEqual(s.latencyMS, AudioController.simulatedLatencySamples / 44100 * 1000, accuracy: 0.1)
        XCTAssertLessThan(s.spreadMS, 0.1)
        XCTAssertTrue(phases.list.contains { if case .running = $0 { return true } else { return false } })
        XCTAssertTrue(c.calibrationValid)
        XCTAssertNotNil(try store.load().audio?.latency)
        let state = AudioService.calibrationState(c.calibrationPhase)
        XCTAssertEqual(state.outcome, "success")
        XCTAssertEqual(state.success?.rows.first?.label, "Latencia")
        XCTAssertTrue(AudioService.settingsResult(c).calibration.label.hasPrefix("Calibrada · 50,0"))
        // Reabrir la sesión reaplica la calibración guardada.
        try c.updateAudio { $0.guitarIn = nil }
        XCTAssertNil(c.session)
        try c.updateAudio { $0.guitarIn = [1] }
        XCTAssertEqual(c.session?.isCalibrated, true)
        c.dismissCalibration()
        XCTAssertEqual(c.calibrationPhase, .idle)
    }

    /// F2: en Windows la clave lleva el modo WASAPI y el contenedor; una calibración en compartido no se reaplica en exclusivo.
    func testWindowsCalibrationIsNotReappliedInTheOtherMode() async throws {
        let container = "{8C2A1F3E-0000-4B1D-9C6E-48454144525E}"
        let base = AudioController.simulatedProvider()
        let devices = (base.inputDevices() + base.outputDevices()).map { d -> AudioDevice in
            var d = d
            d.containerID = container
            return d
        }
        let provider = SimulatedDeviceProvider(devices: devices, defaultID: 2)
        let store = ProfileStore(url: try tempDir().appendingPathComponent("profile.json"))
        let c = AudioController(provider: provider, store: store, makeIO: { setup in
            SimulatedAudioIO(sampleRate: setup.sampleRate,
                             inputs: [SimulatedInput(source: 1, drive: 2, gain: 0.5, noiseDBFS: -60),
                                      SimulatedInput(source: 2, drive: 2, gain: 0.5, noiseDBFS: -60)],
                             latencySamples: AudioController.simulatedLatencySamples, declaredLatencySamples: 1_100,
                             bufferFrames: setup.bufferFrames, inputDeviceUID: AudioController.simulatedInputUID,
                             outputDeviceUID: AudioController.simulatedOutputUID, automatic: true,
                             wasapiIdentity: setup.wasapiMode.map {
                                 WASAPIIdentity(mode: $0, inputContainer: container, outputContainer: container)
                             })
        })
        c.wasapiMode = .shared
        c.start()
        try c.updateAudio {
            $0.chooseOutput(AudioController.simulatedOutputUID)
            $0.chooseInput(AudioController.simulatedInputUID)
            $0.guitarIn = [1]
        }
        XCTAssertEqual(c.wasapiKeyContext, WASAPIKeyContext(mode: "shared", inputContainer: container, outputContainer: container))
        await c.calibrate()
        guard case .finished(.success) = c.calibrationPhase else { return XCTFail("\(c.calibrationPhase)") }
        let key = try XCTUnwrap(try store.load().audio?.latency?.key)
        XCTAssertEqual(key.inputUID, container, "la clave guarda el aparato")
        XCTAssertEqual(key.outputUID, container)
        XCTAssertEqual(key.wasapi, CalibrationKey.WASAPIPath(mode: "shared", inputEndpoint: AudioController.simulatedInputUID,
                                                             outputEndpoint: AudioController.simulatedOutputUID))
        XCTAssertTrue(c.calibrationValid)

        func reopen() throws {
            try c.updateAudio { $0.guitarIn = nil }
            try c.updateAudio { $0.guitarIn = [1] }
        }
        c.wasapiMode = .exclusive
        try reopen()
        XCTAssertEqual(c.session?.isOpen, true)
        XCTAssertEqual(c.session?.isCalibrated, false, "la calibración en compartido no se reaplica en exclusivo")
        XCTAssertFalse(c.calibrationValid)
        XCTAssertEqual(AudioService.settingsResult(c).calibration.label, "Sin calibrar")

        c.wasapiMode = .shared
        try reopen()
        XCTAssertEqual(c.session?.isCalibrated, true, "de vuelta en compartido vale otra vez")
        XCTAssertTrue(c.calibrationValid)
    }

    /// Ronda 7c, Parte C (HeadRush por WASAPI compartido): el perfil pide 512 fotogramas y WASAPI concede su periodo
    /// (480 a 48 kHz). La clave guardada lleva el concedido; `calibrationValid` y Ajustes deben compararla con la clave de
    /// la sesión, no con la del perfil, o se queda en «Sin calibrar» justo después de calibrar.
    func testWindowsCalibrationStaysValidWhenWASAPIGrantsAnotherPeriod() async throws {
        let container = "{1C58EB37-3116-595C-8F20-EC98F026FD5E}"
        let grantedFrames = 480   // periodo de WASAPI compartido a 48 kHz (10 ms)
        let base = AudioController.simulatedProvider()
        let devices = (base.inputDevices() + base.outputDevices()).map { d -> AudioDevice in
            var d = d
            d.containerID = container
            return d
        }
        let provider = SimulatedDeviceProvider(devices: devices, defaultID: 2)
        let store = ProfileStore(url: try tempDir().appendingPathComponent("profile.json"))
        let c = AudioController(provider: provider, store: store, makeIO: { setup in
            SimulatedAudioIO(sampleRate: setup.sampleRate,
                             inputs: [SimulatedInput(source: 1, drive: 2, gain: 0.5, noiseDBFS: -60),
                                      SimulatedInput(source: 2, drive: 2, gain: 0.5, noiseDBFS: -60)],
                             latencySamples: AudioController.simulatedLatencySamples, declaredLatencySamples: 1_100,
                             bufferFrames: grantedFrames, inputDeviceUID: AudioController.simulatedInputUID,
                             outputDeviceUID: AudioController.simulatedOutputUID, automatic: true,
                             wasapiIdentity: setup.wasapiMode.map {
                                 WASAPIIdentity(mode: $0, inputContainer: container, outputContainer: container)
                             })
        })
        c.wasapiMode = .shared
        c.start()
        try c.updateAudio {
            $0.chooseOutput(AudioController.simulatedOutputUID)
            $0.chooseInput(AudioController.simulatedInputUID)
            $0.guitarIn = [1, 2]
        }
        XCTAssertEqual(c.settings?.bufferFrames, AudioSettings.defaultBufferFrames)
        await c.calibrate()
        guard case .finished(.success) = c.calibrationPhase else { return XCTFail("\(c.calibrationPhase)") }
        let saved = try XCTUnwrap(try store.load().audio?.latency)
        XCTAssertEqual(saved.key.bufferFrames, grantedFrames, "la clave guarda el periodo concedido")
        XCTAssertEqual(c.session?.isCalibrated, true)
        XCTAssertTrue(c.calibrationValid, "recién calibrada no puede salir «Sin calibrar»")
        XCTAssertTrue(AudioService.stateResult(c).calibrationValid)
        XCTAssertTrue(AudioService.settingsResult(c).calibration.calibrated)
        XCTAssertTrue(AudioService.settingsResult(c).calibration.label.hasPrefix("Calibrada · "))

        // Reabrir (o relanzar la app) reaplica la calibración y sigue valiendo.
        try c.updateAudio { $0.guitarIn = nil }
        try c.updateAudio { $0.guitarIn = [1, 2] }
        XCTAssertEqual(c.session?.isCalibrated, true)
        XCTAssertTrue(c.calibrationValid)

        // Caducidad intacta: otro canal de guitarra es otra clave.
        try c.updateAudio { $0.guitarIn = [2] }
        XCTAssertEqual(c.session?.isCalibrated, false)
        XCTAssertFalse(c.calibrationValid)
        XCTAssertEqual(AudioService.settingsResult(c).calibration.label, "Sin calibrar")
    }

    func testCalibrationWithoutSignalReportsFailure() async throws {
        let store = ProfileStore(url: try tempDir().appendingPathComponent("profile.json"))
        // Entradas sin cable: nada llega.
        let c = AudioController(provider: AudioController.simulatedProvider(), store: store, makeIO: { setup in
            SimulatedAudioIO(sampleRate: setup.sampleRate, inputs: [SimulatedInput(source: nil, noiseDBFS: -70),
                                                                    SimulatedInput(source: nil, noiseDBFS: -70)],
                             latencySamples: AudioController.simulatedLatencySamples, declaredLatencySamples: 1_000,
                             inputDeviceUID: AudioController.simulatedInputUID, outputDeviceUID: AudioController.simulatedOutputUID,
                             automatic: true)
        })
        c.start()
        try guitarSetup(c)
        await c.calibrate()
        guard case .finished(.failure(let f, _)) = c.calibrationPhase else { return XCTFail("\(c.calibrationPhase)") }
        XCTAssertEqual(f, .noSignal)
        let st = AudioService.calibrationState(c.calibrationPhase)
        XCTAssertEqual(st.failure?.title, "No llegó la señal de prueba")
        XCTAssertNil(try store.load().audio?.latency)
    }

    func testCalibrationBlockedShowsMessage() async throws {
        let (c, _) = try makeController()
        try c.updateAudio { $0.chooseInput(AudioController.simulatedInputUID) }
        c.metersVisible = true   // sesión abierta sin guitarra asignada
        await c.calibrate()
        guard case .finished(.error(let m)) = c.calibrationPhase else { return XCTFail("\(c.calibrationPhase)") }
        XCTAssertEqual(m, "Asigna la entrada de guitarra en Ajustes · Audio.")
        c.metersVisible = false
    }

    func testCancelledCalibrationIsDiscarded() async throws {
        let (c, store) = try makeController(automatic: false)
        try guitarSetup(c)
        let run = Task { await c.calibrate() }
        await sleep(0.5)
        c.cancelCalibration()
        XCTAssertEqual(c.calibrationPhase, .idle)
        let cancelledAt = Date()
        await run.value
        XCTAssertLessThan(Date().timeIntervalSince(cancelledAt), 1.0, "la medida se corta, no espera a que acabe")
        XCTAssertEqual(c.calibrationPhase, .idle)
        XCTAssertNil(try store.load().audio?.latency)
        XCTAssertEqual(c.session?.isCalibrated, false)
        XCTAssertFalse(c.calibrationIsRunning)
    }

    // MARK: Puente audio.* y enganche del reproductor de estudio

    struct Rig {
        var bridge: Bridge
        var events: Events
        var support: URL
        var project: Project
        var service: AudioService
    }

    func makeRig() throws -> Rig {
        let base = try tempDir()
        let root = base.appendingPathComponent("projects", isDirectory: true)
        let support = base.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let rate = StudyTests.sampleRate
        let p = Project(song: Song(title: "Tema", artist: "Banda", source: "source/original.wav", sourceSHA256: "abc",
                                   sourceFormat: "wav", sourceSampleRate: rate, sourceChannels: 2, sampleRate: rate,
                                   duration: StudyTests.seconds))
        var project = p
        project.separation = SeparationState(state: .done, model: "m", finishedAt: Date(timeIntervalSince1970: 1_700_000_000))
        project.stems = [Stem(kind: .bass, file: "stems/bass.wav")]
        let folder = root.appendingPathComponent("Banda - Tema", isDirectory: true)
        let layout = ProjectLayout(folder: folder)
        try layout.createSkeleton()
        try StudyTests.writeSine(layout.stemURL(.bass), frequency: 110)
        try ProjectFile.save(project, to: folder)
        let events = Events()
        let services = JobServices(importer: EditsImporter(), separator: EditsSeparator(), levelMeter: nil,
                                   analyzer: nil, guitarSplitter: nil)
        let bridge = try Bridge(options: LaunchOptions(projectsFolder: root, supportDir: support, audio: .simulated),
                                mediaBase: "https://tf.media/", reveal: nil, services: services)
        bridge.send = { events.add($0) }
        return Rig(bridge: bridge, events: events, support: support, project: project,
                   service: try XCTUnwrap(bridge.studyService.audioService))
    }

    func call(_ r: Rig, _ method: String, _ params: String = "{}") async -> [String: Any] {
        let out = await r.bridge.router.handle("{\"id\":1,\"method\":\"\(method)\",\"params\":\(params)}")
        return (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: Any] ?? [:]
    }

    /// `result` de la respuesta (falla el test si hay error).
    func res(_ r: Rig, _ method: String, _ params: String = "{}") async throws -> [String: Any] {
        let out = await call(r, method, params)
        return try XCTUnwrap(out["result"] as? [String: Any], "\(out)")
    }

    func testBridgeSettingsRoundTrip() async throws {
        let r = try makeRig()
        let d = try await res(r, "audio.devices")
        XCTAssertEqual((d["inputs"] as? [[String: Any]])?.first?["uid"] as? String, "sim-in")
        XCTAssertEqual((d["systemDefault"] as? [String: Any])?["name"] as? String, "Salida simulada")

        var s = try await res(r, "audio.settings")
        XCTAssertNil(s["inputDeviceUID"] as? String)
        XCTAssertEqual((s["calibration"] as? [String: Any])?["label"] as? String, "Sin calibrar")
        XCTAssertEqual(s["workingSampleRate"] as? Double, 44100)

        s = try await res(r, "audio.setSettings",
                                     "{\"inputDeviceUID\":\"sim-in\",\"guitarIn\":[1,2],\"backingOut\":{\"left\":1,\"right\":2}}")
        XCTAssertEqual(s["inputDeviceUID"] as? String, "sim-in")
        XCTAssertEqual(s["guitarIn"] as? [Int], [1, 2])
        let labels = (s["guitarChoices"] as? [[String: Any]])?.compactMap { $0["label"] as? String }
        XCTAssertEqual(labels, ["Sin asignar", "Entrada 1", "Entrada 2", "Entradas 1 y 2"])
        let profile = try ProfileStore(url: r.support.appendingPathComponent("profile.json")).load()
        XCTAssertEqual(profile.audio?.guitarIn, [1, 2])

        // `null` explícito = sin asignar; ausente = no se toca.
        s = try await res(r, "audio.setSettings", "{\"guitarIn\":null}")
        XCTAssertNil(s["guitarIn"] as? [Int])
        XCTAssertEqual(s["inputDeviceUID"] as? String, "sim-in")

        let bad = await call(r, "audio.setSettings", "{\"guitarIn\":[1,1]}")
        XCTAssertEqual((bad["error"] as? [String: Any])?["code"] as? String, "bad-params")
        let badRate = await call(r, "audio.setSettings", "{\"workingSampleRate\":96000}")
        XCTAssertEqual((badRate["error"] as? [String: Any])?["code"] as? String, "bad-params")

        let st = try await res(r, "audio.state")
        XCTAssertEqual(st["sessionOpen"] as? Bool, false)
        XCTAssertEqual(st["calibrateBlock"] as? String, "Asigna la entrada de guitarra en Ajustes · Audio.")
    }

    func testBridgeEvents() async throws {
        let r = try makeRig()
        _ = await call(r, "audio.setSettings", "{\"inputDeviceUID\":\"sim-in\",\"guitarIn\":[1]}")
        await sleep(0.1)
        let states = r.events.all("audio.state")
        XCTAssertFalse(states.isEmpty, "audio.state al cambiar los ajustes")
        XCTAssertEqual(states.last?["sessionOpen"] as? Bool, true)

        _ = await call(r, "audio.setMeters", "{\"visible\":true}")
        await sleep(0.5)
        _ = await call(r, "audio.setMeters", "{\"visible\":false}")
        let levels = r.events.all("audio.levels")
        XCTAssertGreaterThan(levels.count, 3)
        XCTAssertEqual((levels.first?["levels"] as? [Double])?.count, 2)

        // Calibración en tiempo real (unos 5 s): progreso por evento y resultado en la respuesta.
        let c = await call(r, "audio.calibrate")
        let res = try XCTUnwrap(c["result"] as? [String: Any], "\(c)")
        XCTAssertEqual(res["phase"] as? String, "finished")
        XCTAssertEqual(res["outcome"] as? String, "success", "\(res)")
        let cal = r.events.all("audio.calibration")
        XCTAssertTrue(cal.contains { $0["phase"] as? String == "running" })
        XCTAssertEqual(cal.last?["outcome"] as? String, "success")
    }

    func testStudyPlayerAttachesToSessionAndBack() async throws {
        let r = try makeRig()
        _ = await call(r, "audio.setSettings", "{\"inputDeviceUID\":\"sim-in\",\"guitarIn\":[1]}")
        let controller = await r.service.controller()
        XCTAssertEqual(controller.session?.isOpen, true)

        let open = await call(r, "study.open", "{\"projectId\":\"\(r.project.id.uuidString)\"}")
        XCTAssertNotNil(open["result"], "\(open)")
        XCTAssertTrue(controller.isHostingPlayer, "el reproductor de estudio suena por la sesión")
        XCTAssertNil(controller.hostError)
        var st = try await res(r, "audio.state")
        XCTAssertEqual(st["hosting"] as? Bool, true)

        let play = await call(r, "study.play")
        XCTAssertNotNil(play["result"], "\(play)")
        await sleep(0.4)
        let t = try await res(r, "study.pause")
        XCTAssertGreaterThan(t["position"] as? Double ?? 0, 0.1, "avanza alojado en la sesión")

        // Sin guitarra asignada la sesión se cierra y el reproductor vuelve a su salida propia.
        _ = await call(r, "audio.setSettings", "{\"guitarIn\":null}")
        XCTAssertNil(controller.session)
        XCTAssertFalse(controller.isHostingPlayer)
        XCTAssertTrue(r.bridge.studyService.current?.controller.player.isHosted == true, "simulado: salida simulada propia")
        _ = await call(r, "study.play")
        let p0 = r.bridge.studyService.current?.controller.player.currentTime ?? 0
        await sleep(0.4)
        XCTAssertGreaterThan(r.bridge.studyService.current?.controller.player.currentTime ?? 0, p0 + 0.1)
        _ = await call(r, "study.pause")

        // Y vuelve a engancharse al reasignar la guitarra.
        _ = await call(r, "audio.setSettings", "{\"guitarIn\":[1]}")
        XCTAssertTrue(controller.isHostingPlayer)

        _ = await call(r, "study.close")
        st = try await res(r, "audio.state")
        XCTAssertEqual(st["hosting"] as? Bool, false)
        XCTAssertEqual(st["sessionOpen"] as? Bool, true, "la sesión sigue abierta sin tema")
    }

    func testStudyWithoutSessionKeepsOwnOutput() async throws {
        let r = try makeRig()
        let open = await call(r, "study.open", "{\"projectId\":\"\(r.project.id.uuidString)\"}")
        XCTAssertNotNil(open["result"], "\(open)")
        let controller = await r.service.controller()
        XCTAssertNil(controller.session)
        XCTAssertFalse(controller.isHostingPlayer)
        XCTAssertEqual(r.bridge.studyService.current?.controller.player.isHosted, true, "salida simulada propia, como antes")
        _ = await call(r, "study.close")
    }
}
