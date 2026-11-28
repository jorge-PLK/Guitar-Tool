import AudioKit
import Foundation
import XCTest
@testable import AppCore

/// Aviso de salida de audio: código estable para la UI y texto sin nombres de caso ni UID.
final class AudioErrorCodeTests: XCTestCase {
    func testCodePerCase() {
        XCTAssertEqual(audioErrorCode(AudioIOError.notConnected("uid")), "not-connected")
        XCTAssertEqual(audioErrorCode(AudioSessionError.notConnected("uid")), "not-connected")
        XCTAssertEqual(audioErrorCode(AudioSessionError.noInputDevice), "not-connected")
        XCTAssertEqual(audioErrorCode(AudioIOError.sampleRateMismatch(device: 44100, requested: 48000)), "sample-rate-mismatch")
        XCTAssertEqual(audioErrorCode(AudioSessionError.sampleRateMismatch(device: 44100, working: 48000)), "sample-rate-mismatch")
        XCTAssertEqual(audioErrorCode(AudioSessionError.busy), "busy")
        XCTAssertEqual(audioErrorCode(AudioIOError.alreadyRunning), "busy")
        XCTAssertEqual(audioErrorCode(AudioIOError.device("x")), "unavailable")
        XCTAssertEqual(audioErrorCode(AudioSessionError.notOpen), "unavailable")
        XCTAssertEqual(audioErrorCode(CancellationError()), "unavailable")
    }

    func testDescribeHidesCaseNameAndUID() {
        let text = AudioErrorText.describe(AudioIOError.notConnected("x-uid"))
        XCTAssertFalse(text.contains("notConnected"))
        XCTAssertFalse(text.contains("x-uid"))
        XCTAssertEqual(text, "El dispositivo no está conectado.")
        XCTAssertFalse(AudioErrorText.playMessage(AudioIOError.notConnected("x-uid")).contains("x-uid"))
    }

    func testPlayRPCErrorCarriesCode() {
        let e = AudioErrorText.playRPCError(AudioIOError.notConnected("u"), message: "m")
        XCTAssertEqual(e.code, "audio-unavailable")
        XCTAssertEqual(e.args["code"], .string("not-connected"))
    }
}
