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
