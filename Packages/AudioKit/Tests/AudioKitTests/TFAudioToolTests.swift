import XCTest
@testable import AudioKit
@testable import tf_audio

/// `tf-audio` (mini-spec Fase 3, «Demostración con hardware» y «Código»): la lógica del ejecutable, sin lanzar el
/// proceso ni tocar hardware. `verify` simulado pasa (0) y con una latencia mal aplicada a propósito no pasa (1).
final class TFAudioToolTests: XCTestCase {
    final class Lines: @unchecked Sendable {
        private let lock = NSLock()
        private var list: [String] = []
        func add(_ s: String) { lock.withLock { list.append(s) } }
        var all: [String] { lock.withLock { list } }
    }

    func env() throws -> (Env, Lines, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tf-audio-tests-\(UUID().uuidString)")
        let lines = Lines()
        return (Env(dir: dir, emit: { lines.add($0) }), lines, dir)
    }

    // MARK: verify

    @MainActor
    func testSimulatedVerifyPasses() async throws {
        let (e, lines, dir) = try env()
        defer { try? FileManager.default.removeItem(at: dir) }
        let code = await CLI.run(["verify", "--simulated", "2400.81", "--seconds", "20"], env: e)
        XCTAssertEqual(code, 0, lines.all.joined(separator: "\n"))
        XCTAssertEqual(lines.all.last, "PASA")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("verify.wav").path))
        XCTAssertNotNil(StoredCalibration.load(from: e.calibrationURL))
        // Error por clic en CSV (cabecera + una fila por clic) y diagnóstico del render alojado en el resumen.
        let csv = try String(contentsOf: dir.appendingPathComponent("verify-clicks.csv"), encoding: .utf8)
        XCTAssertEqual(csv.split(separator: "\n").count, 1 + 40)
        XCTAssertTrue(lines.all.contains { $0.hasPrefix("Vacíos de StemFeed: ") })
        XCTAssertTrue(lines.all.contains { $0.hasPrefix("Latencia del TimePitch en esta sesión: ") })
        XCTAssertFalse(lines.all.contains { $0.hasPrefix("AVISO: tono sostenido") })
    }

    @MainActor
    func testSimulatedVerifyWithRigAndStereoPasses() async throws {
        let (e, lines, dir) = try env()
        defer { try? FileManager.default.removeItem(at: dir) }
        let code = await CLI.run(["verify", "--simulated", "2205.37", "--rate", "44100", "--sim-rig", "151.37", "--guitar", "1,2",
                                  "--seconds", "10"], env: e)
        XCTAssertEqual(code, 0, lines.all.joined(separator: "\n"))
        XCTAssertTrue(lines.all.contains { $0.hasPrefix("Retardo del rig en la toma") })
    }

    @MainActor
    func testVerifyWithWronglyAppliedLatencyFails() async throws {
        let (e, lines, dir) = try env()
        defer { try? FileManager.default.removeItem(at: dir) }
        let code = await CLI.run(["verify", "--simulated", "2400.81", "--seconds", "10", "--sim-miscalibrate", "60"], env: e)
        XCTAssertEqual(code, 1, lines.all.joined(separator: "\n"))
        XCTAssertEqual(lines.all.last, "NO PASA")
    }

    @MainActor
    func testLatencySavesCalibrationAndVerifyReusesIt() async throws {
        let (e, lines, dir) = try env()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = await CLI.run(["latency", "--simulated", "2400.81"], env: e)
        XCTAssertEqual(a, 0, lines.all.joined(separator: "\n"))
        let saved = try XCTUnwrap(StoredCalibration.load(from: e.calibrationURL))
        XCTAssertEqual(saved.latencySamples, 2400.81, accuracy: 0.05)
        let b = await CLI.run(["verify", "--simulated", "2400.81", "--seconds", "10"], env: e)
        XCTAssertEqual(b, 0)
        XCTAssertTrue(lines.all.contains { $0.hasPrefix("Calibración guardada del") })
        // Otra latencia simulada es otra clave: no reutiliza la guardada.
        let c = await CLI.run(["verify", "--simulated", "2000.25", "--seconds", "10"], env: e)
        XCTAssertEqual(c, 0)
        XCTAssertTrue(lines.all.contains { $0.contains("es de otra configuración") })
    }

    @MainActor
    func testLatencyRestartsReportVariation() async throws {
        let (e, lines, dir) = try env()
        defer { try? FileManager.default.removeItem(at: dir) }
        let code = await CLI.run(["latency", "--simulated", "2400.81", "--restarts", "2"], env: e)
        XCTAssertEqual(code, 0, lines.all.joined(separator: "\n"))
        XCTAssertTrue(lines.all.contains { $0.hasPrefix("Variación entre reinicios: 0,00 muestras") })
    }

    @MainActor
    func testSimulatedRecordReportsMetadata() async throws {
        let (e, lines, dir) = try env()
        defer { try? FileManager.default.removeItem(at: dir) }
        let code = await CLI.run(["record", "--simulated", "2400.81", "--seconds", "3"], env: e)
        XCTAssertEqual(code, 0, lines.all.joined(separator: "\n"))
        XCTAssertTrue(lines.all.contains { $0.hasPrefix("Calibrada: no") })
        XCTAssertTrue(lines.all.contains { $0.hasPrefix("Latencia usada: 1200,40") })
    }

    @MainActor
    func testUsageErrorsExitWithTwo() async throws {
        let (e, lines, _) = try env()
        let a = await CLI.run(["verify", "--guitar", "1"], env: e)
        XCTAssertEqual(a, 2)
        let b = await CLI.run(["record", "--simulated", "2400"], env: e)
        XCTAssertEqual(b, 2)
        let c = await CLI.run(["nada"], env: e)
        XCTAssertEqual(c, 2)
        XCTAssertTrue(lines.all.contains { $0.hasPrefix("Error:") })
        let h = await CLI.run(["--help"], env: e)
        XCTAssertEqual(h, 0)
    }

    // MARK: Argumentos

    func testChannelParsing() throws {
        XCTAssertEqual(try Parse.channels("1"), [1])
        XCTAssertEqual(try Parse.channels("3, 4"), [3, 4])
        XCTAssertThrowsError(try Parse.channels("1,1"))
        XCTAssertThrowsError(try Parse.channels("0"))
        XCTAssertThrowsError(try Parse.channels("1,2,3"))
        XCTAssertThrowsError(try Parse.channels("a"))
        XCTAssertThrowsError(try Parse.channels(""))
    }

    func testPairParsing() throws {
        XCTAssertEqual(try Parse.pair("3,4"), [3, 4])
        XCTAssertThrowsError(try Parse.pair("1"))
        XCTAssertThrowsError(try Parse.pair("2,2"))
    }

    func testOptionsParsing() throws {
        let o = try Parse.options(["latency", "--in", "uno", "--out", "dos", "--guitar", "1,2", "--backing", "3,4", "--rate", "44100",
                                   "--restarts", "5"])
        XCTAssertEqual(o.command, .latency)
        XCTAssertEqual(o.input, "uno")
        XCTAssertEqual(o.guitar, [1, 2])
        XCTAssertEqual(o.backing, [3, 4])
        XCTAssertEqual(o.rate, 44_100)
        XCTAssertEqual(o.restarts, 5)
        XCTAssertEqual(try Parse.options(["verify"]).backing, [1, 2])
        XCTAssertThrowsError(try Parse.options(["verify", "--rate", "96000"]))
        XCTAssertThrowsError(try Parse.options(["verify", "--sim-rig", "10"]))
        XCTAssertThrowsError(try Parse.options(["verify", "--wat"]))
        XCTAssertThrowsError(try Parse.options(["record"]))
    }

    func testDeviceMatching() throws {
        let devices = [
            AudioDevice(id: 1, uid: "AAA-1", name: "Interfaz Uno", inputChannels: 2),
            AudioDevice(id: 2, uid: "BBB-2", name: "Interfaz Dos", inputChannels: 2),
            AudioDevice(id: 3, uid: "CCC-3", name: "Pedalera", inputChannels: 4)
        ]
        XCTAssertEqual(try Parse.device("BBB-2", in: devices, role: "entrada").id, 2)
        XCTAssertEqual(try Parse.device("pedal", in: devices, role: "entrada").id, 3)
        XCTAssertEqual(try Parse.device("INTERFAZ DOS", in: devices, role: "entrada").id, 2)
        XCTAssertThrowsError(try Parse.device("interfaz", in: devices, role: "entrada")) { e in
            let text = (e as? CLIError)?.description ?? ""
            XCTAssertTrue(text.contains("Interfaz Uno") && text.contains("Interfaz Dos") && !text.contains("Pedalera"), text)
        }
        XCTAssertThrowsError(try Parse.device("zzz", in: devices, role: "entrada")) { e in
            XCTAssertTrue(((e as? CLIError)?.description ?? "").contains("Pedalera"))
        }
    }
}
