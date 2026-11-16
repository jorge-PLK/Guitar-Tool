import XCTest
@testable import TabKit

/// Huellas por pista (mini-spec Fase 5, «Desfase por pista» y «Pruebas»: cambiar el WAV de una pista marca solo esa).
final class TabFingerprintTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("TabFingerprintTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func write(_ name: String, bytes: Int) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data(repeating: 1, count: bytes).write(to: url)
        return url
    }

    func fingerprints(_ files: [(String, URL)], model: String = "bp-1") throws -> [(id: String, fingerprint: TrackSourceFingerprint)] {
        try files.map { ($0.0, try TrackSourceFingerprint.of(fileAt: $0.1, path: "stems/\($0.1.lastPathComponent)", modelVersion: model)) }
    }

    func testChangingOneWavMarksOnlyThatTrack() throws {
        let left = try write("guitar_L.wav", bytes: 1000)
        let right = try write("guitar_R.wav", bytes: 1000)
        let bass = try write("bass.wav", bytes: 1000)
        let files = [("guitar-L", left), ("guitar-R", right), ("bass", bass)]

        var score = try TabFingeringTests.score()
        for (id, fp) in try fingerprints(files) {
            score.upsert(TabTrackBuilder.pitchedTrack(id: id, name: id, kind: id == "bass" ? .bass : .guitar,
                                                      tuning: id == "bass" ? .bass(.standard) : .guitar(.standard),
                                                      source: fp, notes: TabFingeringTests.melody([45, 47]), in: score).track)
        }
        XCTAssertEqual(score.staleness(current: try fingerprints(files)), TabStaleness(needsTranscription: [], obsolete: []))

        // Se reescribe solo el WAV derecho (otro tamaño y otra fecha).
        try Data(repeating: 2, count: 1200).write(to: right)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: right.path)
        XCTAssertEqual(score.staleness(current: try fingerprints(files)).needsTranscription, ["guitar-R"])

        // Misma longitud, solo cambia la fecha: también desfasada.
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: left.path)
        XCTAssertEqual(score.staleness(current: try fingerprints(files)).needsTranscription, ["guitar-L", "guitar-R"])

        // Otra versión del modelo: todas.
        XCTAssertEqual(score.staleness(current: try fingerprints(files, model: "bp-2")).needsTranscription.count, 3)
    }

    func testTuningIsNotPartOfFingerprintAndTrackSetChanges() throws {
        let left = try write("guitar_L.wav", bytes: 500)
        let solo = try write("guitar_solo.wav", bytes: 500)
        var score = try TabFingeringTests.score()
        let fp = try fingerprints([("guitar-L", left)])[0].fingerprint
        score.upsert(TabTrackBuilder.pitchedTrack(id: "guitar-L", name: "L", kind: .guitar, tuning: .guitar(.standard),
                                                  source: fp, notes: TabFingeringTests.melody([40, 52]), in: score).track)
        score.upsert(TabTrack(id: "guitar-R", name: "R", kind: .guitar, tuning: .guitar(.standard), source: fp,
                              subdivisions: score.beats.map { _ in .sixteenths }))
        var editor = TabEditor(score: score)
        try editor.setTuning(.guitar(.dropD), trackID: "guitar-L")

        // Ya no hay pista derecha y aparece la solista: la R sobra, la solista hay que transcribirla; la L sigue al día.
        let status = editor.score.staleness(current: try fingerprints([("guitar-L", left), ("solo", solo)]))
        XCTAssertEqual(status, TabStaleness(needsTranscription: ["solo"], obsolete: ["guitar-R"]))
    }

    func testFingerprintSurvivesJSONWithAnyDateStrategy() throws {
        let url = try write("drums.wav", bytes: 321)
        let fp = try TrackSourceFingerprint.of(fileAt: url, path: "stems/drums.wav", modelVersion: "adtof-1")
        XCTAssertEqual(fp.size, 321)
        XCTAssertEqual(fp.parametersVersion, TabTrackBuilder.parametersVersion)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let back = try JSONDecoder().decode(TrackSourceFingerprint.self, from: try encoder.encode(fp))
        XCTAssertEqual(back, fp)
    }
}
