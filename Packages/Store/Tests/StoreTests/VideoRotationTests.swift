import Foundation
import XCTest
@testable import Store

/// Giro del vídeo (decisión de Jorge del 17/11/2026): por toma (`Take.videoRotation`) y por cámara
/// (`VideoSettings.rotations`), aditivo y con `schemaVersion` 2.
final class VideoRotationTests: XCTestCase {
    func testTakeRotationRoundTripAndOldJSONIsZero() throws {
        var p = makeFullProject()
        p.takes = [Take(createdAt: whole(), videoFile: "takes/x/video.mov", videoRotation: 90), Take(createdAt: whole())]
        let data = try ProjectFile.makeEncoder().encode(p)
        let back = try ProjectFile.makeDecoder().decode(Project.self, from: data)
        XCTAssertEqual(back.schemaVersion, 2)
        XCTAssertEqual(back.takes.map(\.videoRotation), [90, nil])
        XCTAssertEqual(back.takes.map(\.rotationDegrees), [90, 0])
        // Una toma sin el campo (JSON anterior) no lo escribe y se lee como 0°.
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let takes = try XCTUnwrap(json["takes"] as? [[String: Any]])
        XCTAssertNil(takes[1]["videoRotation"])
        let old = #"{"id":"6F9619FF-8B86-D011-B42D-00CF4FC964FF","discarded":false,"createdAt":"2026-01-01T00:00:00Z","videoFile":"v.mov"}"#
        let t = try ProjectFile.makeDecoder().decode(Take.self, from: Data(old.utf8))
        XCTAssertNil(t.videoRotation)
        XCTAssertEqual(t.rotationDegrees, 0)
    }

    func testCameraRotationRoundTripNormalizationAndOldProfile() throws {
        var v = VideoSettings()
        v.setDefaultRotation(450, for: "cam")
        v.setDefaultRotation(-90, for: "iphone")
        XCTAssertEqual(v.defaultRotation(for: "cam"), 90)
        XCTAssertEqual(v.defaultRotation(for: "iphone"), 270)
        XCTAssertEqual(v.defaultRotation(for: "otra"), 0)
        let back = try JSONDecoder().decode(VideoSettings.self, from: try JSONEncoder().encode(v))
        XCTAssertEqual(back, v)
        let old = try JSONDecoder().decode(VideoSettings.self, from: Data(#"{"fps":30,"offsets":{"cam":0.05}}"#.utf8))
        XCTAssertEqual(old.rotations, [:])
        XCTAssertEqual(old.defaultRotation(for: "cam"), 0)
        XCTAssertEqual([0, 89, 180, 271, 360, -180].map(VideoSettings.normalizedRotation), [0, 90, 180, 270, 0, 180])
    }

    /// Un cuarto de vuelta: la caja de la mitad izquierda de la imagen pasa a la mitad de arriba; cuatro, la misma.
    func testFramingRotatesWithImage() {
        let f = TakeFraming(mode: .fixed, manualBox: NormalizedRect(x: 0, y: 0, width: 0.5, height: 1), followZoom: 1.5,
                            followOffset: FramingOffset(x: 0.1, y: 0.2))
        let r = f.rotatedClockwise(quarterTurns: 1)
        XCTAssertEqual(r.manualBox, NormalizedRect(x: 0, y: 0, width: 1, height: 0.5))
        XCTAssertEqual(r.followOffset, FramingOffset(x: -0.2, y: 0.1))
        XCTAssertEqual(r.followZoom, 1.5)
        XCTAssertEqual(f.rotatedClockwise(quarterTurns: 4), f)
        let corner = TakeFraming(manualBox: NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)).rotatedClockwise(quarterTurns: 1)
        let b = corner.manualBox!
        XCTAssertEqual(b.x, 0.4, accuracy: 1e-12)
        XCTAssertEqual(b.y, 0.1, accuracy: 1e-12)
        XCTAssertEqual(b.width, 0.4, accuracy: 1e-12)
        XCTAssertEqual(b.height, 0.3, accuracy: 1e-12)
    }
}
