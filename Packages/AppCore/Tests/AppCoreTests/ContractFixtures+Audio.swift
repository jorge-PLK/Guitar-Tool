import AudioKit
import Foundation
import Store
import XCTest
@testable import AppCore

// Ola 3, parte 3.2: fixtures de `audio.*` en `Contract/fixtures/audio/`.
//
// Convención de variantes: el fichero es `<método|evento>[.<variante>].<params|result|error|event>.json`. Sin variante es el
// caso normal; la variante (minúsculas, sin guiones) nombra la situación: `audio.settings.ratemismatch.result.json`.
// Todo va con E/S simulada y perfil temporal; nunca se abre un dispositivo real.

/// Llama al Router (propio, con un servicio concreto) y vuelca params y result/error con nombre de variante.
struct FixtureCalls {
    let rig: FixtureRig
    let router: Router

    static func name(_ base: String, _ variant: String?) -> String { variant.map { "\(base).\($0)" } ?? base }

    /// Fechas de texto del Mac («3 feb 2026») fijas, para que el día de hoy no mueva el fichero.
    static let spanishDate = try! NSRegularExpression(pattern: "\\d{1,2} [a-zñ]{3,4}\\.? \\d{4}")

    func scrub(_ text: String) -> String {
        Self.spanishDate.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "3 feb 2026")
    }

    /// Los floats de la calibración simulada tienen jitter entre pasadas: se normalizan por clave antes de volcar.
    /// `latencyMS`/`latencySamples` a 2 decimales; `spreadMS`/`spreadSamples` a un valor representativo
    /// (0.0 en éxito, 3.0 bajo `failure`). Las filas de texto (`rows[].value`) ya salen estables.
    static let spreadSuccess = 0.0
    static let spreadFailure = 3.0

    static func normalize(_ any: Any, inFailure: Bool = false) -> Any {
        if let dict = any as? [String: Any] {
            var out: [String: Any] = [:]
            for (k, v) in dict {
                let fail = inFailure || k == "failure"
                if let n = v as? NSNumber, String(cString: n.objCType) != "c" {  // "c" = Bool (sin CoreFoundation: en Windows no hay CFBooleanGetTypeID)
                    switch k {
                    case "latencyMS", "latencySamples": out[k] = (n.doubleValue * 100).rounded() / 100
                    case "spreadMS", "spreadSamples": out[k] = fail ? spreadFailure : spreadSuccess
                    default: out[k] = v
                    }
                } else {
                    out[k] = normalize(v, inFailure: fail)
                }
            }
            return out
        }
        if let arr = any as? [Any] { return arr.map { normalize($0, inFailure: inFailure) } }
        return any
    }

    @discardableResult
    func call(_ method: String, variant: String? = nil, params: String = "{}",
              file: StaticString = #filePath, line: UInt = #line) async throws -> [String: Any] {
        let name = Self.name(method, variant)
        try rig.golden(name, .params, params, file: file, line: line)
        let r = await router.handle("{\"id\":1,\"method\":\"\(method)\",\"params\":\(params)}")
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(r.utf8)) as? [String: Any])
        if let e = o["error"] {
            try rig.golden(name, .error, scrub(try FixtureRig.text(e)), file: file, line: line)
        } else {
            try rig.golden(name, .result, scrub(try FixtureRig.text(Self.normalize(try XCTUnwrap(o["result"])))), file: file, line: line)
        }
        return o
    }

    func event<T: Encodable>(_ name: String, variant: String? = nil, _ payload: T,
                             file: StaticString = #filePath, line: UInt = #line) throws {
        let m = try XCTUnwrap(Router.eventMessage(name, payload))
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(m.utf8)) as? [String: Any])
        XCTAssertEqual(o["event"] as? String, name)
        try rig.golden(Self.name(name, variant), .event, scrub(try FixtureRig.text(Self.normalize(try XCTUnwrap(o["payload"])))), file: file, line: line)
    }
}

@MainActor
final class ContractFixturesAudioTests: XCTestCase {
    private func make(_ rig: FixtureRig, provider: SimulatedDeviceProvider? = nil, profile: EquipmentProfile? = nil,
                      noCable: Bool = false) throws -> (FixtureCalls, AudioController, AudioService, ProfileStore) {
        let dir = rig.dir.appendingPathComponent("Audio-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = ProfileStore(url: dir.appendingPathComponent("profile.json"))
        if let profile { try store.save(profile) }
        var io = AudioController.simulatedIO(automatic: true)
        if noCable {
            io = { @Sendable setup in
                SimulatedAudioIO(sampleRate: setup.sampleRate, inputs: [SimulatedInput(source: nil, noiseDBFS: -70),
                                                                        SimulatedInput(source: nil, noiseDBFS: -70)],
                                 latencySamples: AudioController.simulatedLatencySamples, declaredLatencySamples: 1_000,
                                 inputDeviceUID: AudioController.simulatedInputUID,
                                 outputDeviceUID: AudioController.simulatedOutputUID, automatic: true)
            }
        }
        let c = AudioController(provider: provider ?? AudioController.simulatedProvider(), store: store, makeIO: io)
        let service = AudioService(options: LaunchOptions(projectsFolder: rig.projects, supportDir: dir, audio: .simulated),
                                   emit: { _ in })
        service.factory = { _ in c }
        _ = service.controller()   // cablea y arranca el controlador
        let router = Router()
        service.register(on: router)
        return (FixtureCalls(rig: rig, router: router), c, service, store)
    }

    private func guitar(_ c: AudioController) throws {
        try c.updateAudio { $0.chooseInput(AudioController.simulatedInputUID); $0.guitarIn = [1] }
    }

    func testAudioArea() async throws {
        let rig = try FixtureRig(area: "audio")
        defer { rig.cleanup() }

        // Sin entrada elegida.
        do {
            let (f, c, _, _) = try make(rig)
            try await f.call("audio.settings", variant: "noinput")
            try await f.call("audio.devices")
            try await f.call("audio.state", variant: "noinput")
            try f.event("audio.levels", variant: "nolevels", AudioLevelsEvent(levels: [], rmsDB: [], peakDB: []))
            _ = c
        }

        // Sin calibrar, con guitarra asignada; setSettings con `guitarIn` ausente y null (rechazado, M-7).
        do {
            let (f, c, _, _) = try make(rig)
            try await f.call("audio.setSettings", params: "{\"inputDeviceUID\":\"sim-in\",\"guitarIn\":[1]}")
            try await f.call("audio.setSettings", variant: "guitarabsent", params: "{\"workingSampleRate\":44100}")
            try await f.call("audio.setSettings", variant: "guitarnull", params: "{\"guitarIn\":null}")
            try await f.call("audio.setSettings", variant: "outputnull", params: "{\"outputDeviceUID\":null}")
            try await f.call("audio.setSettings", variant: "badrate", params: "{\"workingSampleRate\":96000}")
            try await f.call("audio.setSettings", variant: "badchannels", params: "{\"backingOut\":{\"left\":0,\"right\":2}}")
            try guitar(c)
            try await f.call("audio.settings")
            try await f.call("audio.setMeters", params: "{\"visible\":true}")
            try await f.call("audio.state")
            try f.event("audio.state", AudioService.stateResult(c))
            try f.event("audio.levels", AudioLevelsEvent(levels: [0.5, 0.25], rmsDB: [-30, -37.5], peakDB: [-24, -30]))
            try await f.call("audio.setMeters", variant: "hidden", params: "{\"visible\":false}")
            try f.event("audio.calibration", variant: "running", AudioService.calibrationState(.running(0.4)))
            try f.event("audio.calibration", variant: "idle", AudioService.calibrationState(.idle))
            try await f.call("audio.cancelCalibration")
            try await f.call("audio.dismissCalibration")

            // Calibrada (el éxito sale del bucle simulado, con fechas y latencia fijas).
            try await f.call("audio.calibrate")
            try await f.call("audio.settings", variant: "calibrated")
            try f.event("audio.calibration", variant: "success", AudioService.calibrationState(c.calibrationPhase))
            try await f.call("audio.state", variant: "calibrated")
        }

        // Fallo por falta de señal.
        do {
            let (f, c, _, _) = try make(rig, noCable: true)
            try guitar(c)
            try await f.call("audio.calibrate", variant: "failure")
            try f.event("audio.calibration", variant: "failure", AudioService.calibrationState(c.calibrationPhase))
        }

        // Frecuencia distinta: el dispositivo de entrada no cambia de frecuencia y el perfil trabaja a 48 kHz.
        do {
            let base = AudioController.simulatedProvider(rate: 44100)
            let fixed = SimulatedDeviceProvider(devices: base.inputDevices() + base.outputDevices(), defaultID: 2,
                                                fixedRateUIDs: [AudioController.simulatedInputUID])
            let (f, c, _, _) = try make(rig, provider: fixed, profile: EquipmentProfile(workingSampleRate: 48000))
            try guitar(c)
            try await f.call("audio.settings", variant: "ratemismatch")
            try await f.call("audio.state", variant: "ratemismatch")
        }

        // Dispositivo elegido desconectado.
        do {
            let (f, c, _, _) = try make(rig)
            try guitar(c)
            try c.modifyProfile { $0.audio?.inputDeviceUID = "ya-no-esta" }
            try await f.call("audio.settings", variant: "disconnected")
            try await f.call("audio.state", variant: "disconnected")
            try f.event("audio.devicesChanged", AudioService.devicesResult(c))
        }
    }
}
