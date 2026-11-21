import XCTest
@testable import AudioKit

/// Lo que los tests piden a un reproductor: la costura pública más los ganchos internos de render offline. Lo cumplen
/// el `StudyPlayer` de AVAudioEngine (Mac) y `PortableStudyPlayer` (en Windows es `StudyPlayer`). Así los mismos casos
/// prueban los dos motores en el Mac (plan, «Corte del paso 7», parte 7.6).
@MainActor
protocol PlayerUnderTest: StudyPlaybackEngine, Sendable {
    func renderOffline(frames: Int) throws -> (start: Int64, channels: [[Float]])
    var runStartFrame: Double { get }
    var modelLatencyFrames: Double { get }
    var halfFadeFrames: Int64 { get }
    func songTime(atOutputFrame y: Double) -> Double
    var appliedRoute: OutputRoute? { get }
    var feedUnderrunFrames: Int { get }
}

extension PortableStudyPlayer: PlayerUnderTest {}
#if canImport(AVFoundation)
extension StudyPlayer: PlayerUnderTest {}
#endif

/// Qué motor se prueba: el de la plataforma (`StudyPlayer`) o el portátil (en Windows, el mismo).
enum PlayerKind: String, Sendable {
    case platform, portable

    /// En el Mac, los dos; en Windows solo hay uno.
    static var all: [PlayerKind] {
        #if canImport(AVFoundation)
        [.platform, .portable]
        #else
        [.platform]
        #endif
    }

    @MainActor
    func offline(devices: (any AudioDeviceProviding)? = nil) -> any PlayerUnderTest {
        switch self {
        case .platform: StudyPlayer(offlineWith: devices)
        case .portable: PortableStudyPlayer(offlineWith: devices)
        }
    }

    @MainActor
    func realtime(devices: any AudioDeviceProviding) -> any PlayerUnderTest {
        switch self {
        case .platform: StudyPlayer(devices: devices)
        case .portable: PortableStudyPlayer(devices: devices)
        }
    }
}
