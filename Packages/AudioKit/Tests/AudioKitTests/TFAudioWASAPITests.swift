import XCTest
@testable import AudioKit
@testable import tf_audio

/// `tf-audio` en Windows (parte 7.10b), la parte portátil: argumentos `--mode`/`--period`, listado WASAPI con driver y
/// periodos, búsqueda de endpoints y la variación entre reinicios frente a la tolerancia de cada plataforma. Corre en el
/// Mac y en Windows sin abrir dispositivos.
final class TFAudioWASAPITests: XCTestCase {
    static let mix48 = WASAPIFormat(sampleRate: 48_000, channels: 2, bits: 32, validBits: 32, isFloat: true)
    static let usb2 = WASAPIDriverInfo(adapterInstance: "USB\\VID_1234&PID_5678&MI_00\\7&1A2B3C&0&0000", adapterName: "Flex Prime",
                                       service: "usbaudio2", provider: "Microsoft", version: "10.0.22621.2506",
                                       description: "Dispositivo de audio USB", infPath: "usbaudio2.inf")
    /// P8 (VM): IAudioClient3 mínimo 128, paso 32, máximo 480; GetDevicePeriod 10 ms / 2,667 ms.
    static let engine = WASAPIEnginePeriods(defaultFrames: 480, fundamentalFrames: 32, minimumFrames: 128, maximumFrames: 480)

    static func flexOut(driver: WASAPIDriverInfo = usb2) -> WASAPIDeviceInfo {
        WASAPIDeviceInfo(id: "{0.0.0.00000000}.{out}", name: "Altavoces (Flex Prime)", flow: .render, isDefault: false, mix: mix48,
                         defaultPeriod100ns: 100_000, minimumPeriod100ns: 26_667, engine: engine, exclusiveFloat: false,
                         driver: driver, containerID: "{5A1B2C3D-0000-1111-2222-333344445555}")
    }

    static func flexIn(driver: WASAPIDriverInfo = usb2) -> WASAPIDeviceInfo {
        WASAPIDeviceInfo(id: "{0.0.1.00000000}.{in}", name: "Micrófono (Flex Prime)", flow: .capture, isDefault: false, mix: mix48,
                         defaultPeriod100ns: 100_000, minimumPeriod100ns: 26_667, engine: engine, exclusiveFloat: true,
                         driver: driver)
    }

    static let hda = WASAPIDeviceInfo(id: "{0.0.0.00000000}.{hda}", name: "Altavoces (High Definition Audio Device)", flow: .render,
                                      isDefault: true, mix: mix48, defaultPeriod100ns: 100_000, minimumPeriod100ns: 30_000,
                                      engine: nil, exclusiveFloat: true,
                                      driver: WASAPIDriverInfo(adapterInstance: "HDAUDIO\\FUNC_01&VEN_8086", service: "HdAudAddService",
                                                               provider: "Microsoft", infPath: "hdaudio.inf"))

    // MARK: Variación entre reinicios (el umbral que decide la prueba de Jorge en el PC)

    func testRestartToleranceIsTheSameOnWindowsAndMac() {
        XCTAssertEqual(CLI.windowsRestartToleranceMs, 0.25)
        XCTAssertEqual(CLI.restartToleranceMs, 0.25, "Mac sin cambios")
        XCTAssertEqual(CLI.platformRestartToleranceMs, 0.25)
    }

    func testRestartSpreadAt48kHzAgainstPointTwoMs() throws {
        // 0,2 ms a 48 kHz = 9,6 muestras.
        let ok = try XCTUnwrap(CLI.RestartSpread([2400.81, 2405.00, 2410.31], sampleRate: 48_000, toleranceMs: 0.2))
        XCTAssertEqual(ok.spreadSamples, 9.5, accuracy: 1e-9)
        XCTAssertEqual(ok.spreadMs, 0.19792, accuracy: 1e-5)
        XCTAssertTrue(ok.passes)
        XCTAssertEqual(ok.lines, ["Variación entre reinicios: 9,50 muestras (0,198 ms) en 3 reinicios válidos",
                                  "No supera 0,20 ms: la calibración vale entre reinicios."])
        let bad = try XCTUnwrap(CLI.RestartSpread([2400.81, 2410.51], sampleRate: 48_000, toleranceMs: 0.2))
        XCTAssertEqual(bad.spreadMs, 0.20208, accuracy: 1e-5)
        XCTAssertFalse(bad.passes, "9,7 muestras = 0,202 ms supera 0,2 ms")
        XCTAssertEqual(bad.lines.last, "Supera 0,20 ms: la regla pasa a calibrar por sesión.")
    }

    func testRestartSpreadAt44kHz() throws {
        // 0,2 ms a 44,1 kHz = 8,82 muestras.
        XCTAssertTrue(try XCTUnwrap(CLI.RestartSpread([1000, 1008.8], sampleRate: 44_100, toleranceMs: 0.2)).passes)
        XCTAssertFalse(try XCTUnwrap(CLI.RestartSpread([1000, 1008.85], sampleRate: 44_100, toleranceMs: 0.2)).passes)
    }

    /// El escalón conocido de la Flex Prime en el Mac (12 muestras = 0,25 ms a 48 kHz; plan, Fase 3) pasa en el Mac
    /// (0,25, no lo supera) y también en Windows (mismo umbral, decisión de Jorge del 21/11/2026); 13 muestras ya no.
    func testFlexPrimeTwelveSampleStepPassesOnBothPlatforms() throws {
        let lat = [2400.0, 2412.0, 2400.0]
        XCTAssertTrue(try XCTUnwrap(CLI.RestartSpread(lat, sampleRate: 48_000, toleranceMs: CLI.restartToleranceMs)).passes)
        XCTAssertTrue(try XCTUnwrap(CLI.RestartSpread(lat, sampleRate: 48_000, toleranceMs: CLI.windowsRestartToleranceMs)).passes)
        let over = [2400.0, 2413.0]
        XCTAssertFalse(try XCTUnwrap(CLI.RestartSpread(over, sampleRate: 48_000, toleranceMs: CLI.windowsRestartToleranceMs)).passes)
    }

    func testRestartSpreadNeedsTwoValidRuns() {
        XCTAssertNil(CLI.RestartSpread([2400], sampleRate: 48_000, toleranceMs: 0.2))
        XCTAssertNil(CLI.RestartSpread([], sampleRate: 48_000, toleranceMs: 0.2))
    }

    // MARK: Argumentos

    func testModeAndPeriodParsing() throws {
        let o = try Parse.options(["latency", "--in", "flex", "--out", "flex", "--guitar", "1,2", "--mode", "exclusive",
                                   "--period", "0", "--restarts", "10"])
        XCTAssertEqual(o.mode, .exclusive)
        XCTAssertEqual(o.period, 0)
        XCTAssertEqual(o.restarts, 10)
        XCTAssertEqual(try Parse.options(["verify", "--mode", "Compartido"]).mode, .shared)
        XCTAssertEqual(try Parse.options(["verify", "--mode", "exclusivo", "--period", "128"]).period, 128)
        XCTAssertNil(try Parse.options(["verify"]).mode, "por defecto, nada: Rig usa compartido")
        XCTAssertNil(try Parse.options(["verify"]).period, "por defecto, nada: AudioSetup.bufferFrames (512)")
        XCTAssertThrowsError(try Parse.options(["verify", "--mode", "asio"]))
        XCTAssertThrowsError(try Parse.options(["verify", "--period", "-1"]))
        XCTAssertThrowsError(try Parse.options(["verify", "--period", "4801"]))
        XCTAssertThrowsError(try Parse.options(["verify", "--period", "abc"]))
        XCTAssertThrowsError(try Parse.options(["verify", "--simulated", "2400", "--mode", "exclusive"]))
        XCTAssertThrowsError(try Parse.options(["verify", "--simulated", "2400", "--period", "128"]))
    }

    #if !os(Windows)
    /// En el Mac `--mode`/`--period` no existen con dispositivos reales: error de uso (2) sin tocar el HAL.
    @MainActor
    func testMacRejectsWASAPIFlags() async throws {
        final class Lines: @unchecked Sendable {
            private let lock = NSLock()
            private var list: [String] = []
            func add(_ s: String) { lock.withLock { list.append(s) } }
            var all: [String] { lock.withLock { list } }
        }
        let lines = Lines()
        let env = Env(dir: FileManager.default.temporaryDirectory.appendingPathComponent("tf-audio-wasapi-\(UUID().uuidString)"),
                      emit: { lines.add($0) })
        let code = await CLI.run(["latency", "--in", "x", "--out", "y", "--guitar", "1", "--mode", "exclusive"], env: env)
        XCTAssertEqual(code, Exit.error)
        XCTAssertTrue(lines.all.contains { $0.contains("solo existen en Windows") }, lines.all.joined(separator: "\n"))
    }
    #endif

    // MARK: Listado

    func testDeviceListingShowsDriverAndMinimumPeriods() {
        let lines = WASAPIListing.lines([Self.flexIn(), Self.hda, Self.flexOut()], requestedPeriod: 512)
        XCTAssertEqual(lines.first, "Modo por defecto: compartido; periodo pedido por defecto: 512 muestras (cámbialos con --mode y --period)")
        // Salidas primero, por nombre; luego entradas.
        let heads = lines.filter { $0.hasPrefix("Dispositivo:") }
        XCTAssertEqual(heads, ["Dispositivo: Altavoces (Flex Prime) · salida",
                               "Dispositivo: Altavoces (High Definition Audio Device) · salida (por defecto)",
                               "Dispositivo: Micrófono (Flex Prime) · entrada"])
        XCTAssertTrue(lines.contains("  Driver: USB Audio 2.0 genérico de Windows · servicio usbaudio2 · Microsoft · "
                                     + "versión 10.0.22621.2506 · usbaudio2.inf · «Dispositivo de audio USB»"), lines.joined(separator: "\n"))
        XCTAssertTrue(lines.contains("  Adaptador: Flex Prime · USB\\VID_1234&PID_5678&MI_00\\7&1A2B3C&0&0000"))
        XCTAssertTrue(lines.contains("  Compartido: IAudioClient3, mínimo 128 muestras (2,667 ms), paso 32, máximo 480; "
                                     + "con 512 pedidas: 480 (10,000 ms)"), lines.joined(separator: "\n"))
        XCTAssertTrue(lines.contains("  Exclusivo: mínimo 128 muestras (2,667 ms); float32 en exclusivo: no (el shim prueba enteros)"))
        XCTAssertTrue(lines.contains("  Compartido: IAudioClient, periodo fijo 480 muestras (10,000 ms)"), "sin IAudioClient3")
        XCTAssertTrue(lines.contains("  Exclusivo: mínimo 144 muestras (3,000 ms); float32 en exclusivo: sí"))
        XCTAssertTrue(lines.contains("  Driver: de Microsoft · servicio HdAudAddService · Microsoft · hdaudio.inf"))
        // W2-E2: contenedor del aparato (o aviso si Windows no lo da).
        XCTAssertTrue(lines.contains("  Contenedor: {5A1B2C3D-0000-1111-2222-333344445555}"), lines.joined(separator: "\n"))
        XCTAssertTrue(lines.contains("  Contenedor: no lo da Windows"))
        XCTAssertFalse(lines.contains { $0.contains("Error al consultar") })
        XCTAssertEqual(WASAPIListing.lines([], requestedPeriod: 512).last, "No hay dispositivos de audio.")
    }

    func testDriverTextForVendorUnknownAndFailedQuery() {
        XCTAssertEqual(WASAPIListing.driverText(WASAPIDriverInfo(service: "HRFlexAudio", provider: "HeadRush", version: "1.2.0",
                                                                 infPath: "oem42.inf")),
                       "propio del fabricante · servicio HRFlexAudio · HeadRush · versión 1.2.0 · oem42.inf")
        XCTAssertEqual(WASAPIListing.driverText(WASAPIDriverInfo(hresult: Int32(bitPattern: 0x8007_0490))),
                       "desconocido · consulta fallida 0x80070490")
        XCTAssertEqual(WASAPIListing.driverText(WASAPIDriverInfo()), "desconocido")
    }

    // MARK: Endpoints de entrada y salida del mismo aparato

    func testInAndOutMatchSeparateEndpointListsAndSameAdapter() throws {
        let captures = [Self.flexIn()]
        let renders = [Self.hda, Self.flexOut()]
        let i = try Parse.device("flex", in: captures.enumerated().map { WASAPIListing.audioDevice($1, index: $0) }, role: "entrada")
        let o = try Parse.device("flex", in: renders.enumerated().map { WASAPIListing.audioDevice($1, index: $0) }, role: "salida")
        XCTAssertEqual(i.uid, "{0.0.1.00000000}.{in}")
        XCTAssertEqual(o.uid, "{0.0.0.00000000}.{out}")
        XCTAssertEqual(Int(o.id), 1, "el índice en su lista")
        XCTAssertEqual(i.inputChannels, 2)
        XCTAssertEqual(i.outputChannels, 0)
        XCTAssertEqual(o.nominalSampleRate, 48_000)
        XCTAssertEqual(WASAPIListing.sameAdapter(Self.flexIn(), Self.flexOut()), true)
        XCTAssertEqual(WASAPIListing.sameAdapter(Self.flexIn(), Self.hda), false)
        XCTAssertNil(WASAPIListing.sameAdapter(Self.flexIn(driver: WASAPIDriverInfo()), Self.flexOut()), "sin adaptador: no se sabe")
    }

    // MARK: Lo que quedó abierto

    func testStreamLinesWarnOnInputResampling() {
        let i = WASAPIStreamInfo(mode: .shared, renderPath: .client3Shared, capturePath: .autoconvert, renderFormat: Self.mix48,
                                 captureFormat: Self.mix48, renderBufferFrames: 960, captureBufferFrames: 1056,
                                 renderPeriodFrames: 480, capturePeriodFrames: 480, renderLatency100ns: 100_000,
                                 captureLatency100ns: 100_000, captureDeviceRate: 44_100, renderName: "", captureName: "")
        XCTAssertEqual(WASAPIListing.streamLines(i), [
            "WASAPI: modo compartido",
            "  Salida: compartido (IAudioClient3) · 48000 Hz · 2 ch · float32 · periodo 480 (10,000 ms) · búfer 960 · latencia de flujo 10,000 ms",
            "  Entrada: compartido remuestreado (AUTOCONVERTPCM) · 48000 Hz · 2 ch · float32 · periodo 480 (10,000 ms) · búfer 1056 · "
                + "latencia de flujo 10,000 ms",
            "  AVISO: entrada remuestreada por Windows desde 44100 Hz (retardo sin medir)"
        ])
        let st = WASAPIStreamStatus(mmcss: true, renderBuffers: 100, renderStarved: 2, capturePackets: 99, clockFailures: 0, driftPPM: 1.26)
        XCTAssertEqual(WASAPIListing.statusLine(st), "WASAPI: MMCSS sí · 100 búferes de salida · 2 sin hueco · 99 paquetes de entrada · "
                       + "0 fallos de IAudioClock · deriva 1,3 ppm")
    }
}
