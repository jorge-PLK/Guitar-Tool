import XCTest
@testable import AudioKit

/// Clave de calibración con WASAPI (plan, «Fase 7c», paso 8, F2): modo y contenedor, con E/S simulada que los declara.
final class WASAPICalibrationKeyTests: XCTestCase {
    static let container = "{8C2A1F3E-0000-4B1D-9C6E-48454144525E}"
    static let capture = "{0.0.1.00000000}.{aaaaaaaa-0000-0000-0000-000000000001}"
    static let render12 = "{0.0.0.00000000}.{bbbbbbbb-0000-0000-0000-000000000012}"
    static let render34 = "{0.0.0.00000000}.{bbbbbbbb-0000-0000-0000-000000000034}"
    static let fs = 48_000.0
    static let latency = 2_400.81

    static func io(mode: WASAPIShareMode?, output: String = render12, container: String? = container) -> SimulatedAudioIO {
        SimulatedAudioIO(sampleRate: fs, inputs: [SimulatedInput(source: 1, noiseDBFS: -60)], latencySamples: latency,
                         declaredLatencySamples: 1_000, inputDeviceUID: capture, outputDeviceUID: output,
                         initialSampleTime: LatencyCalibratorTests.t0,
                         wasapiIdentity: mode.map { WASAPIIdentity(mode: $0, inputContainer: container, outputContainer: container) })
    }

    /// Clave de la sesión abierta sobre `io` (`AudioSession.calibrationKey`).
    static func sessionKey(_ io: SimulatedAudioIO) throws -> LatencyCalibrationKey {
        let s = AudioSessionTests.session(io, guitarIn: [1])
        try s.open()
        defer { s.close() }
        return try XCTUnwrap(s.calibrationKey)
    }

    func testSessionKeyCarriesModeAndContainer() throws {
        let k = try Self.sessionKey(Self.io(mode: .shared))
        XCTAssertEqual(k.inputUID, Self.container, "entrada: el aparato, no el endpoint")
        XCTAssertEqual(k.outputUID, Self.container, "salida: el mismo aparato")
        XCTAssertEqual(k.wasapi, WASAPICalibrationPath(mode: .shared, inputEndpoint: Self.capture, outputEndpoint: Self.render12))
        XCTAssertEqual(k.bufferFrames, 512)
        let json = String(decoding: try JSONEncoder().encode(k), as: UTF8.self)
        XCTAssertTrue(json.contains("\"mode\":\"shared\""), json)
    }

    func testCalibrationInOneModeDoesNotApplyInTheOther() throws {
        let sharedIO = Self.io(mode: .shared)
        let r = try LatencyCalibratorTests.calibrate(sharedIO)
        XCTAssertTrue(r.isValid)
        XCTAssertEqual(r.latencySamples, Self.latency, accuracy: 0.05)
        XCTAssertEqual(r.key, try Self.sessionKey(sharedIO), "calibrador y sesión forman la misma clave")
        XCTAssertTrue(r.applies(to: try Self.sessionKey(Self.io(mode: .shared))))
        XCTAssertFalse(r.applies(to: try Self.sessionKey(Self.io(mode: .exclusive))), "compartido -> exclusivo: no vale")
        XCTAssertFalse(r.applies(to: try Self.sessionKey(Self.io(mode: nil))), "ni sin modo")
        XCTAssertFalse(r.applies(to: try Self.sessionKey(Self.io(mode: .shared, output: Self.render34))),
                       "otro endpoint del mismo aparato es otro camino")
    }

    func testWithoutContainerFallsBackToEndpoint() throws {
        let k = try Self.sessionKey(Self.io(mode: .exclusive, container: nil))
        XCTAssertEqual(k.inputUID, Self.capture)
        XCTAssertEqual(k.outputUID, Self.render12)
        XCTAssertEqual(k.wasapi?.mode, .exclusive)
    }

    func testCoreAudioKeyUnchanged() throws {
        let k = try Self.sessionKey(Self.io(mode: nil))
        XCTAssertNil(k.wasapi)
        XCTAssertEqual(k.inputUID, Self.capture)
        XCTAssertEqual(k.outputUID, Self.render12)
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let json = String(decoding: try enc.encode(k.inProfileTerms(outputDeviceUID: nil)), as: UTF8.self)
        XCTAssertEqual(json, #"{"bufferFrames":512,"inputChannel":1,"inputUID":"\#(Self.capture)","outputChannel":1,"#
                       + #""outputUID":"","sampleRate":48000}"#)
    }

    func testProfileTermsRoundTripWithDefaultOutput() throws {
        let session = try Self.sessionKey(Self.io(mode: .shared))
        // Sin salida elegida en el perfil: UID y endpoint de salida vacíos.
        let saved = session.inProfileTerms(outputDeviceUID: nil)
        XCTAssertEqual(saved.outputUID, "")
        XCTAssertEqual(saved.wasapi?.outputEndpoint, "")
        XCTAssertEqual(saved.inputUID, Self.container)
        XCTAssertEqual(saved.resolvingDefaultOutput(to: session.outputUID, endpoint: session.wasapi?.outputEndpoint), session)
        // Con salida elegida: el UID de la sesión (contenedor) se conserva.
        XCTAssertEqual(session.inProfileTerms(outputDeviceUID: Self.render12), session)
    }

    func testProviderExposesContainer() {
        func info(_ id: String, _ flow: WASAPIFlow, container: String?) -> WASAPIDeviceInfo {
            WASAPIDeviceInfo(id: id, name: id, flow: flow, isDefault: false,
                             mix: WASAPIFormat(sampleRate: Self.fs, channels: 2, bits: 32, validBits: 32, isFloat: true),
                             defaultPeriod100ns: 100_000, minimumPeriod100ns: 30_000, engine: nil, exclusiveFloat: true,
                             containerID: container)
        }
        let list = [info(Self.render12, .render, container: Self.container), info(Self.render34, .render, container: Self.container),
                    info(Self.capture, .capture, container: Self.container), info("hdmi", .render, container: nil)]
        let p = WASAPIDeviceProvider(enumerate: { list })
        XCTAssertEqual(p.outputDevices().map(\.containerID), [Self.container, Self.container, nil])
        XCTAssertEqual(p.inputDevices().first?.containerID, Self.container)
        XCTAssertEqual(Set(p.outputDevices().prefix(2).map(\.uid)).count, 2, "dos endpoints, un aparato")
    }
}
