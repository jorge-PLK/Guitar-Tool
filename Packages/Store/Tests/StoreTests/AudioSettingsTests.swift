import XCTest
@testable import Store

final class AudioSettingsTests: XCTestCase {
    private let key = CalibrationKey(inputUID: "In", outputUID: "Out", sampleRate: 48000, bufferFrames: 512,
                                     inputChannel: 1, outputChannel: 1)

    private func fullAudio() -> AudioSettings {
        let lat = LatencyCalibration(latencySamples: 2412.37, spreadSamples: 0.8, date: whole(), key: key,
                                     referenceIn: ReferenceChannel(channel: 3, latencySamples: 2390.5))
        return AudioSettings(outputDeviceUID: "Out", inputDeviceUID: "In", backingOut: ChannelPair(left: 3, right: 4),
                             guitarIn: [1, 2], latency: lat)
    }

    func testAudioRoundTripInProfile() throws {
        let dir = try makeTempDir("audio")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProfileStore(url: dir.appendingPathComponent("profile.json"))
        var p = EquipmentProfile()
        p.audio = fullAudio()
        try store.save(p)
        XCTAssertEqual(try store.load().audio, fullAudio())
    }

    func testOldProfileWithoutAudioLoads() throws {
        let dir = try makeTempDir("audio-old")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("profile.json")
        try Data(#"{"workingSampleRate":48000,"guitars":[],"masterGainDB":-3}"#.utf8).write(to: url)
        let p = try ProfileStore(url: url).load()
        XCTAssertNil(p.audio)
        XCTAssertEqual(p.workingSampleRate, 48000)
    }

    func testPartialAudioGetsDefaults() throws {
        let a = try ProjectFile.makeDecoder().decode(AudioSettings.self, from: Data(#"{"outputDeviceUID":"X"}"#.utf8))
        XCTAssertEqual(a.backingOut, ChannelPair(left: 1, right: 2))
        XCTAssertEqual(a.bufferFrames, 512)
        XCTAssertNil(a.guitarIn)
        XCTAssertNil(a.latency)
        XCTAssertFalse(a.canRecord)
    }

    func testTakeFieldsRoundTripAndOldProjectLoads() throws {
        let dir = try makeTempDir("take-audio")
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        let take = Take(id: id, processedFile: ProjectLayout.processedRelativePath(takeId: id), createdAt: whole(),
                        songStart: 12.5, sampleRate: 48000, latencySamples: 2412.37, rigDelaySamples: 31,
                        rigDelayReliable: false, latencyCalibrated: true, calibrationKey: key, clock: .aggregate)
        var old = Take(createdAt: whole())
        old.processedFile = "takes/x.wav"
        try ProjectFile.save(Project(song: makeSong(), takes: [take, old]), to: dir)
        let loaded = try ProjectFile.load(folder: dir)
        XCTAssertEqual(loaded.takes[0], take)
        XCTAssertEqual(loaded.schemaVersion, 2)
        XCTAssertNil(loaded.takes[1].clock)
        XCTAssertNil(loaded.takes[1].latencyCalibrated)
        let json = try String(contentsOf: ProjectLayout(folder: dir).projectFile, encoding: .utf8)
        XCTAssertTrue(json.contains("\"clock\" : \"aggregate\""))
        XCTAssertEqual(json.components(separatedBy: "\"songStart\"").count - 1, 1, "sin valor no se escribe")
    }

    func testProcessedPath() {
        let id = UUID()
        let layout = ProjectLayout(folder: URL(fileURLWithPath: "/tmp/p"))
        XCTAssertEqual(ProjectLayout.processedRelativePath(takeId: id), "takes/\(id.uuidString)/processed.wav")
        XCTAssertEqual(layout.processedURL(takeId: id).path, "/tmp/p/takes/\(id.uuidString)/processed.wav")
    }

    func testValidation() throws {
        XCTAssertNoThrow(try AudioSettings().validate())
        XCTAssertNoThrow(try fullAudio().validate())
        XCTAssertThrowsError(try AudioSettings(backingOut: ChannelPair(left: 2, right: 2)).validate()) {
            XCTAssertEqual($0 as? AudioSettingsError, .invalidBackingPair)
        }
        XCTAssertThrowsError(try AudioSettings(backingOut: ChannelPair(left: 0, right: 1)).validate())
        for bad in [[1, 1], [], [1, 2, 3], [0]] {
            XCTAssertThrowsError(try AudioSettings(guitarIn: bad).validate()) {
                XCTAssertEqual($0 as? AudioSettingsError, .invalidGuitarChannels)
            }
        }
        var a = fullAudio()
        a.guitarIn = [3]
        XCTAssertThrowsError(try a.validate()) { XCTAssertEqual($0 as? AudioSettingsError, .referenceOverlapsGuitar) }
    }

    func testCalibrationExpiresWhenKeyChanges() {
        var a = fullAudio()
        XCTAssertEqual(a.calibrationKey(sampleRate: 48000), key.with(outputChannel: 3))
        let current = a.calibrationKey(sampleRate: 48000)!
        a.latency?.key = current
        XCTAssertNotNil(a.validLatency(sampleRate: 48000))
        XCTAssertNil(a.validLatency(sampleRate: 44100))
        a.bufferFrames = 256
        XCTAssertNil(a.validLatency(sampleRate: 48000))
    }

    // MARK: Clave de Windows (paso 8, F2)

    /// `profile.json` del Mac de antes de F2, tal cual lo escribía `ProfileStore` (claves ordenadas, sin campo `wasapi`).
    private static let oldMacProfile = #"""
    {
      "audio" : {
        "backingOut" : {
          "left" : 1,
          "right" : 2
        },
        "bufferFrames" : 512,
        "guitarIn" : [
          1
        ],
        "inputDeviceUID" : "AppleUSBAudioEngine:HeadRush:FLEX PRIME:000001:2",
        "latency" : {
          "date" : "2026-10-02T18:30:00Z",
          "key" : {
            "bufferFrames" : 512,
            "inputChannel" : 1,
            "inputUID" : "AppleUSBAudioEngine:HeadRush:FLEX PRIME:000001:2",
            "outputChannel" : 1,
            "outputUID" : "AppleUSBAudioEngine:HeadRush:FLEX PRIME:000001:2",
            "sampleRate" : 48000
          },
          "latencySamples" : 2412.37,
          "spreadSamples" : 0.8
        },
        "outputDeviceUID" : "AppleUSBAudioEngine:HeadRush:FLEX PRIME:000001:2"
      },
      "guitars" : [],
      "masterGainDB" : -3,
      "workingSampleRate" : 48000
    }
    """#

    /// La clave guardada en el perfil de antes, codificada sola (el mismo codificador que `ProfileStore`).
    private static let oldMacKeyJSON = #"""
    {
      "bufferFrames" : 512,
      "inputChannel" : 1,
      "inputUID" : "AppleUSBAudioEngine:HeadRush:FLEX PRIME:000001:2",
      "outputChannel" : 1,
      "outputUID" : "AppleUSBAudioEngine:HeadRush:FLEX PRIME:000001:2",
      "sampleRate" : 48000
    }
    """#

    func testOldMacProfileCalibrationStaysValidByteForByte() throws {
        let dir = try makeTempDir("audio-mac-f2")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("profile.json")
        try Data(Self.oldMacProfile.utf8).write(to: url)
        let store = ProfileStore(url: url)
        let p = try store.load()
        let audio = try XCTUnwrap(p.audio)
        let saved = try XCTUnwrap(audio.latency)
        XCTAssertNil(saved.key.wasapi, "un perfil de antes no trae parte de Windows")
        // La clave que forma el Mac hoy (sin contexto WASAPI) es la guardada: la calibración sigue valiendo.
        XCTAssertEqual(audio.calibrationKey(sampleRate: 48000), saved.key)
        XCTAssertEqual(audio.validLatency(sampleRate: 48000), saved)
        // Codificada otra vez, la clave es byte a byte la de antes.
        let keyData = try ProjectFile.makeEncoder().encode(saved.key)
        XCTAssertEqual(String(decoding: keyData, as: UTF8.self), Self.oldMacKeyJSON)
        // Y el perfil guardado de nuevo no gana campos: mismo JSON que el de antes.
        try store.save(p)
        let rewritten = try Data(contentsOf: url)
        XCTAssertFalse(String(decoding: rewritten, as: UTF8.self).contains("wasapi"))
        let before = try JSONSerialization.jsonObject(with: Data(Self.oldMacProfile.utf8)) as? NSDictionary
        let after = try JSONSerialization.jsonObject(with: rewritten) as? NSDictionary
        XCTAssertEqual(before?["audio"] as? NSDictionary, after?["audio"] as? NSDictionary)
    }

    /// Pedalera de prueba en Windows: un contenedor, un endpoint de captura y dos de render (dos pares de salidas).
    private enum Win {
        static let container = "{8C2A1F3E-0000-4B1D-9C6E-48454144525E}"
        static let capture = "{0.0.1.00000000}.{aaaaaaaa-0000-0000-0000-000000000001}"
        static let render12 = "{0.0.0.00000000}.{bbbbbbbb-0000-0000-0000-000000000012}"
        static let render34 = "{0.0.0.00000000}.{bbbbbbbb-0000-0000-0000-000000000034}"
        static func context(_ mode: String) -> WASAPIKeyContext {
            WASAPIKeyContext(mode: mode, inputContainer: container, outputContainer: container)
        }
        static func audio(output: String = render12) -> AudioSettings {
            AudioSettings(outputDeviceUID: output, inputDeviceUID: capture, guitarIn: [1])
        }
    }

    func testWindowsKeyDiffersByMode() throws {
        var a = Win.audio()
        let shared = try XCTUnwrap(a.calibrationKey(sampleRate: 48000, wasapi: Win.context("shared")))
        let exclusive = try XCTUnwrap(a.calibrationKey(sampleRate: 48000, wasapi: Win.context("exclusive")))
        XCTAssertNotEqual(shared, exclusive)
        XCTAssertEqual(shared.wasapi?.mode, "shared")
        a.latency = LatencyCalibration(latencySamples: 1500, spreadSamples: 0.5, key: shared)
        XCTAssertNotNil(a.validLatency(sampleRate: 48000, wasapi: Win.context("shared")))
        XCTAssertNil(a.validLatency(sampleRate: 48000, wasapi: Win.context("exclusive")),
                     "una calibración en compartido no vale en exclusivo")
        XCTAssertNil(a.validLatency(sampleRate: 48000), "ni con la clave sin modo")
        // La clave de Windows sí lleva su parte al guardarse.
        let json = String(decoding: try ProjectFile.makeEncoder().encode(shared), as: UTF8.self)
        XCTAssertTrue(json.contains("\"mode\" : \"shared\""), json)
    }

    func testWindowsKeySameDeviceIdentityAcrossEndpointsOfOneContainer() throws {
        let k12 = try XCTUnwrap(Win.audio().calibrationKey(sampleRate: 48000, wasapi: Win.context("shared")))
        let k34 = try XCTUnwrap(Win.audio(output: Win.render34).calibrationKey(sampleRate: 48000, wasapi: Win.context("shared")))
        // Misma identidad de aparato: entrada y salida (endpoints distintos) dan el contenedor, como un solo UID en el Mac.
        XCTAssertEqual(k12.inputUID, Win.container)
        XCTAssertEqual(k12.outputUID, Win.container)
        XCTAssertEqual(k12.inputUID, k12.outputUID)
        XCTAssertEqual(k34.outputUID, k12.outputUID, "los dos pares de salidas son el mismo aparato")
        // Pero otro endpoint es otro camino: la calibración de 1-2 no vale para 3-4.
        XCTAssertNotEqual(k12, k34)
        XCTAssertEqual(k12.wasapi?.outputEndpoint, Win.render12)
        XCTAssertEqual(k34.wasapi?.outputEndpoint, Win.render34)
        var a = Win.audio(output: Win.render34)
        a.latency = LatencyCalibration(latencySamples: 1500, spreadSamples: 0.5, key: k12)
        XCTAssertNil(a.validLatency(sampleRate: 48000, wasapi: Win.context("shared")))
    }

    func testWindowsKeyFallsBackToEndpointWithoutContainer() throws {
        let k = try XCTUnwrap(Win.audio().calibrationKey(sampleRate: 48000, wasapi: WASAPIKeyContext(mode: "shared")))
        XCTAssertEqual(k.inputUID, Win.capture)
        XCTAssertEqual(k.outputUID, Win.render12)
        let empty = try XCTUnwrap(Win.audio().calibrationKey(
            sampleRate: 48000, wasapi: WASAPIKeyContext(mode: "shared", inputContainer: "", outputContainer: "")))
        XCTAssertEqual(empty, k, "contenedor vacío = sin contenedor")
        // Salida por defecto del sistema (nil en el perfil): UID y endpoint vacíos, como en el Mac.
        var a = Win.audio()
        a.outputDeviceUID = nil
        let d = try XCTUnwrap(a.calibrationKey(sampleRate: 48000, wasapi: Win.context("shared")))
        XCTAssertEqual(d.outputUID, "")
        XCTAssertEqual(d.wasapi?.outputEndpoint, "")
    }

    func testChoosingDeviceResetsRoles() {
        var a = fullAudio()
        a.chooseOutput("Other")
        XCTAssertEqual(a.backingOut, .default)
        a.chooseInput("Other")
        XCTAssertNil(a.guitarIn)
    }
}

private extension CalibrationKey {
    func with(outputChannel: Int) -> CalibrationKey {
        var k = self
        k.outputChannel = outputChannel
        return k
    }
}
