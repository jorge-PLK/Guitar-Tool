import Foundation
import Store
import XCTest
@testable import AppCore

final class ContractFixturesHostTests: XCTestCase {
    func testHostArea() async throws {
        let rig = try FixtureRig(area: "host")
        defer { rig.cleanup() }
        let song = rig.dir.appendingPathComponent("Song.mp3")
        let other = rig.dir.appendingPathComponent("Other.wav")
        rig.bridge.host = FixtureHost(file: song, many: [song, other])
        try await rig.run("host.pickAudioFile")
        try await rig.run("host.pickAudioFiles")
        try await rig.run("host.openURL", params: "{\"urls\":[\"https://example.com/x\",\"spotify:track:abc\"]}")
        try await rig.run("host.preview.show",
                          params: "{\"url\":\"https://www.songsterr.com/a/wsa/x-tab-s1\",\"x\":10,\"y\":20.5,\"width\":640,\"height\":360}")
        try await rig.run("host.preview.hide")
        // `host.chooseFolder`: el selector se simula con la variable de pruebas (sin abrir diálogo); ruta neutra y estable.
        rig.bridge.environment = { [Bridge.testPickFolderVariable: "/Users/example/Music/ToneForge"] }
        try await rig.run("host.chooseFolder")
        rig.bridge.environment = { [:] }
        // `host.pickProjectsFolder` abre un selector nativo y guarda el perfil: solo params.
        try await rig.run("host.pickProjectsFolder", paramsOnly: true)
        // Sin anfitrión, todos dan `unsupported`.
        rig.bridge.host = nil
        try await rig.runExpectingError("host.pickAudioFile", params: "{}")
    }
}
