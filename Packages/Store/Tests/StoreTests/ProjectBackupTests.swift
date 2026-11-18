import Foundation
import XCTest
@testable import Store

final class ProjectBackupTests: XCTestCase {
    private func names(_ dir: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasPrefix("project.json.") }.sorted()
    }

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Date(timeIntervalSince1970: 1_800_000_000))!
    }

    private func dayName(_ offset: Int) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd"
        return "project.json.bak-" + f.string(from: day(offset))
    }

    private func withTitle(_ p: Project, _ t: String) -> Project { var q = p; q.song.title = t; return q }

    func testFirstWriteOfDayKeepsPreviousContentAndSecondDoesNotOverwrite() throws {
        let dir = try makeTempDir()
        let p0 = makeFullProject()
        try ProjectFile.save(p0, to: dir, now: day(0))
        XCTAssertEqual(names(dir), [])   // primera creación: nada que copiar
        let original = try Data(contentsOf: dir.appendingPathComponent("project.json"))
        try ProjectFile.save(withTitle(p0, "B"), to: dir, now: day(0))
        let bak = dir.appendingPathComponent(dayName(0))
        XCTAssertEqual(try Data(contentsOf: bak), original)
        try ProjectFile.save(withTitle(p0, "C"), to: dir, now: day(0))
        XCTAssertEqual(try Data(contentsOf: bak), original)
        XCTAssertEqual(names(dir), [dayName(0)])
    }

    func testIdenticalWriteCreatesNothing() throws {
        let dir = try makeTempDir()
        let p = makeFullProject()
        try ProjectFile.save(p, to: dir, now: day(0))
        try ProjectFile.save(p, to: dir, now: day(0))
        XCTAssertEqual(names(dir), [])
    }

    func testRotationKeepsSevenMostRecentAndOnlyExactPattern() throws {
        let dir = try makeTempDir()
        let p = makeFullProject()
        try ProjectFile.save(p, to: dir, now: day(0))
        let other = dir.appendingPathComponent("project.json.bak-manual")
        try Data("x".utf8).write(to: other)
        for i in 1...10 { try ProjectFile.save(withTitle(p, "T\(i)"), to: dir, now: day(i)) }
        let daily = names(dir).filter { ProjectBackup.isDailyBackupName($0) }
        XCTAssertEqual(daily.count, 7)
        XCTAssertEqual(daily.last, dayName(10))
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path))
    }

    func testExistingManualBackupOfTodayIsRespected() throws {
        let dir = try makeTempDir()
        let p = makeFullProject()
        try ProjectFile.save(p, to: dir, now: day(0))
        let manual = dir.appendingPathComponent(dayName(0))
        try Data("manual".utf8).write(to: manual)
        try ProjectFile.save(withTitle(p, "B"), to: dir, now: day(0))
        XCTAssertEqual(try String(contentsOf: manual, encoding: .utf8), "manual")
    }

    func testWriteLosingRecordingCreatesLostCopyEvenIfDailyExists() throws {
        let dir = try makeTempDir()
        var p = makeFullProject()
        p.recording = RecordingState(parts: [RecordingPart(name: "A")])
        try ProjectFile.save(p, to: dir, now: day(0))
        try ProjectFile.save(withTitle(p, "B"), to: dir, now: day(0))   // crea el .bak del día
        let before = try Data(contentsOf: dir.appendingPathComponent("project.json"))
        var q = p
        q.recording = nil
        try ProjectFile.save(q, to: dir, now: day(0).addingTimeInterval(5))
        let lost = names(dir).filter { $0.hasPrefix("project.json.lost-") }
        XCTAssertEqual(lost.count, 1)
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent(lost[0])), before)
    }

    /// `tabSource` (Fase 5b, ADR-017) es una clave de primer nivel: perderla deja copia `.lost`, como `recording`.
    func testWriteLosingTabSourceCreatesLostCopy() throws {
        let dir = try makeTempDir()
        var p = makeFullProject()
        p.tabSource = .automatic
        try ProjectFile.save(p, to: dir, now: day(0))
        let before = try Data(contentsOf: dir.appendingPathComponent("project.json"))
        var q = p
        q.tabSource = nil
        XCTAssertTrue(ProjectBackup.losesData(old: before, new: try ProjectFile.makeEncoder().encode(q)))
        try ProjectFile.save(q, to: dir, now: day(0).addingTimeInterval(5))
        let lost = names(dir).filter { $0.hasPrefix("project.json.lost-") }
        XCTAssertEqual(lost.count, 1)
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent(lost[0])), before)
        // Escribirla de nuevo no pierde nada: sin otra copia.
        try ProjectFile.save(p, to: dir, now: day(0).addingTimeInterval(10))
        XCTAssertEqual(names(dir).filter { $0.hasPrefix("project.json.lost-") }.count, 1)
    }

    func testLosingVideoFileFromTakeIsDetected() throws {
        var p = makeFullProject()
        var t = Take(createdAt: whole())
        t.videoFile = "takes/x/video.mov"
        p.takes = [t]
        let old = try ProjectFile.makeEncoder().encode(p)
        p.takes[0].videoFile = nil
        let new = try ProjectFile.makeEncoder().encode(p)
        XCTAssertTrue(ProjectBackup.losesData(old: old, new: new))
        XCTAssertFalse(ProjectBackup.losesData(old: old, new: old))
    }

    // MARK: Proyecto degradado

    func testOrphanDetectionAndReconstruction() {
        var p = makeFullProject()
        p.recording = nil
        let a = UUID(), b = UUID()
        let t0 = Date(timeIntervalSince1970: 1000)
        p.takes = [
            Take(createdAt: t0.addingTimeInterval(20), partID: a, videoFile: "v1"),
            Take(createdAt: t0, partID: a, videoFile: "v0"),
            Take(createdAt: t0.addingTimeInterval(5), partID: b),
        ]
        XCTAssertTrue(p.hasOrphanedTakes)
        let r = p.reconstructedRecording()
        XCTAssertEqual(r?.parts.count, 2)
        XCTAssertEqual(r?.parts[0].id, a)
        XCTAssertEqual(r?.parts[0].name, "Parte recuperada 1")
        XCTAssertEqual(r?.parts[0].takeIDs, [p.takes[1].id, p.takes[0].id])
        XCTAssertEqual(r?.parts[0].bestTakeID, p.takes[0].id)
        XCTAssertEqual(r?.parts[1].id, b)
    }

    func testNoPartIDMeansNoReconstruction() {
        var p = makeFullProject()
        p.recording = nil
        p.takes = [Take(createdAt: whole(), videoFile: "v")]
        XCTAssertTrue(p.hasOrphanedTakes)
        XCTAssertNil(p.reconstructedRecording())
    }

    func testHealthyAndAudioOnlyProjectsAreNotOrphaned() {
        var p = makeFullProject()
        p.recording = nil
        p.takes = [Take(createdAt: whole())]
        XCTAssertFalse(p.hasOrphanedTakes)
        let part = UUID(), take = Take(createdAt: whole(), partID: part, videoFile: "v")
        p.takes = [take]
        p.recording = RecordingState(parts: [RecordingPart(id: part, name: "G", takeIDs: [take.id], bestTakeID: take.id)])
        XCTAssertFalse(p.hasOrphanedTakes)
        XCTAssertNil(p.reconstructedRecording())
    }
}
