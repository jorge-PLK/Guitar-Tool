import XCTest
@testable import AudioKit

/// Lógica sin vista de grabar y del A/B (la usa la app; mini-spec Fase 3).
final class AppLogicTests: XCTestCase {
    private func ready() -> RecordingGate.DeviceState {
        .init(hasInputDevice: true, hasGuitarIn: true)
    }

    func testRecordBlockReasonsInOrder() {
        var s = ready()
        XCTAssertNil(RecordingGate.recordBlock(s, playbackRate: 1, loopActive: false))

        XCTAssertEqual(RecordingGate.recordBlock(s, playbackRate: 0.75, loopActive: false), .speed(0.75))
        XCTAssertEqual(RecordingGate.recordBlock(s, playbackRate: 1, loopActive: true), .loop)
        XCTAssertEqual(RecordingGate.recordBlock(s, playbackRate: 1, loopActive: false, busy: true), .busy)
        XCTAssertEqual(RecordingGate.recordBlock(s, playbackRate: 0.5, loopActive: true), .speed(0.5), "primero la velocidad")

        s.hasGuitarIn = false
        XCTAssertEqual(RecordingGate.deviceBlock(s), .noGuitarInput)
        s.hasInputDevice = false
        XCTAssertEqual(RecordingGate.deviceBlock(s), .noInputDevice)

        s = ready()
        s.inputConnected = false
        XCTAssertEqual(RecordingGate.recordBlock(s, playbackRate: 0.5, loopActive: true), .inputDisconnected, "el dispositivo manda sobre el resto")
        s = ready()
        s.outputConnected = false
        XCTAssertEqual(RecordingGate.deviceBlock(s), .outputDisconnected)
        s = ready()
        s.validChannels = false
        XCTAssertEqual(RecordingGate.deviceBlock(s), .invalidChannels)
        s = ready()
        s.sessionError = "No se pudo abrir"
        XCTAssertEqual(RecordingGate.deviceBlock(s), .sessionUnavailable("No se pudo abrir"))
    }

    func testRateMismatchMessageUsesDeviceRateNotSupportedOnes() {
        var s = ready()
        s.mismatchedRate = 44_100
        s.workingRate = 48_000
        let b = RecordingGate.deviceBlock(s)
        XCTAssertEqual(b, .rateMismatch(device: 44_100, working: 48_000))
        XCTAssertEqual(b?.message, "El dispositivo está a 44,1 kHz y la frecuencia de trabajo es 48 kHz")
    }

    func testBlockMessagesNeverMentionDIOrDeviceNames() {
        let all: [RecordBlock] = [.noInputDevice, .noGuitarInput, .invalidChannels, .inputDisconnected, .outputDisconnected,
                                  .rateMismatch(device: 48_000, working: 44_100), .speed(0.5), .loop, .busy]
        for b in all {
            XCTAssertFalse(b.message.contains(" DI"), b.message)
            XCTAssertFalse(b.message.lowercased().contains("reamp"), b.message)
            XCTAssertFalse(b.message.lowercased().contains("flex"), b.message)
        }
    }

    func testCompareRestoresUserMuteWhenBackToA() {
        for userMuted in [false, true] {
            XCTAssertEqual(MixCompare.stemMuted(mode: .original, userMuted: userMuted), userMuted)
            XCTAssertTrue(MixCompare.stemMuted(mode: .live, userMuted: userMuted))
            XCTAssertTrue(MixCompare.stemMuted(mode: .lastTake, userMuted: userMuted))
        }
        // Secuencia A → B → A con el mute del usuario puesto: el valor del usuario no cambia en ningún paso.
        let userMuted = true
        var applied: [Bool] = []
        for mode in [CompareMode.original, .live, .lastTake, .original] {
            applied.append(MixCompare.stemMuted(mode: mode, userMuted: userMuted))
        }
        XCTAssertEqual(applied, [true, true, true, true])
        XCTAssertEqual(MixCompare.stemMuted(mode: .original, userMuted: false), false)
    }

    func testLiveDifferenceIsLiveMinusStemWithFader() throws {
        let d = try XCTUnwrap(MixCompare.liveDifferenceDB(liveDB: -18, stemRMSDB: -20, faderDB: -0.1))
        XCTAssertEqual(d, 2.1, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(MixCompare.liveDifferenceDB(liveDB: -18, stemRMSDB: -20, faderDB: -6)), 8, accuracy: 1e-9)
        XCTAssertNil(MixCompare.liveDifferenceDB(liveDB: nil, stemRMSDB: -20, faderDB: 0))
        XCTAssertNil(MixCompare.liveDifferenceDB(liveDB: -18, stemRMSDB: nil, faderDB: 0))
    }

    func testDifferenceTexts() {
        XCTAssertEqual(MixCompare.differenceText(2.1), "+2,1 dB respecto al original")
        XCTAssertEqual(MixCompare.differenceText(-3.04), "−3,0 dB respecto al original")
        XCTAssertEqual(MixCompare.differenceText(0), "0,0 dB respecto al original")
        XCTAssertEqual(MixCompare.gainText(12), "+12,0 dB")
        XCTAssertEqual(MixCompare.gainText(-4.26), "−4,3 dB")
    }

    func testAudioSamplesReadSegmentAndRMS() throws {
        let fs = 48_000.0
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AppLogicTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        // 2 s: el primer segundo a 0,1 de amplitud (continua); el segundo, a 0,5.
        let x = (0..<Int(2 * fs)).map { Float($0 < Int(fs) ? 0.1 : 0.5) }
        let url = dir.appendingPathComponent("a.wav")
        try TakeFile.write([x, x], sampleRate: fs, to: url)
        XCTAssertEqual(try AudioSamples.sampleRate(of: url), fs)
        let seg = try AudioSamples.read(url, from: 1, seconds: 0.5)
        XCTAssertEqual(seg.count, 2)
        XCTAssertEqual(seg[0].count, Int(0.5 * fs))
        XCTAssertEqual(try XCTUnwrap(AudioSamples.rmsDB(seg)), 20 * log10(0.5), accuracy: 0.01)
        let tail = try AudioSamples.read(url, from: 1.8, seconds: 10)
        XCTAssertEqual(tail[0].count, Int(0.2 * fs), "recorta a lo que haya")
        XCTAssertNil(AudioSamples.rmsDB([[0, 0, 0]]))
        XCTAssertNil(AudioSamples.rmsDB([]))
        XCTAssertTrue(try AudioSamples.read(url, from: 5, seconds: 1)[0].isEmpty)
    }
}

final class StoredCalibrationTests: XCTestCase {
    func testProfileTermsAndResolvedKeysRoundTrip() {
        let session = LatencyCalibrationKey(inputUID: "in", outputUID: "speakers", sampleRate: 48_000, bufferFrames: 512,
                                            inputChannel: 1, outputChannel: 1)
        let stored = session.inProfileTerms(outputDeviceUID: nil)
        XCTAssertEqual(stored.outputUID, "")
        XCTAssertEqual(stored.resolvingDefaultOutput(to: "speakers"), session)
        XCTAssertEqual(session.inProfileTerms(outputDeviceUID: "speakers"), session, "salida elegida: no cambia")
        XCTAssertEqual(session.resolvingDefaultOutput(to: "otra"), session, "con salida explícita no se sustituye")
    }

    func testRestoredCalibrationAppliesAndKeepsReference() throws {
        let key = LatencyCalibrationKey(inputUID: "in", outputUID: "out", sampleRate: 44_100, bufferFrames: 512,
                                        inputChannel: 2, outputChannel: 1)
        let r = LatencyCalibrationResult.restored(key: key, date: Date(), guitarIn: [2], latencySamples: 2_205.37,
                                                  spreadSamples: 0.2, inputChannels: 4,
                                                  reference: ReferenceInput(channel: 4, latencySamples: 2_054))
        XCTAssertTrue(r.isValid)
        XCTAssertEqual(r.latencySamples, 2_205.37)
        XCTAssertEqual(r.spreadSamples, 0.2)
        XCTAssertEqual(r.channels.count, 4)
        XCTAssertTrue(r.applies(to: key))
        var other = key
        other.sampleRate = 48_000
        XCTAssertFalse(r.applies(to: other))
        XCTAssertEqual(try XCTUnwrap(r.rigDelayAtCalibration), 151.37, accuracy: 1e-9)
    }
}
