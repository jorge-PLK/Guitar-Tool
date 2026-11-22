import XCTest
@testable import Store

/// Huella de `stems/guitar.wav` (tamaño + fecha + SHA-256): copiar el proyecto a otra máquina cambia la fecha y no debe
/// rehacer las guitarras; un contenido distinto sí.
final class GuitarFingerprintTests: XCTestCase {
    /// Canción separada con las guitarras ya hechas una vez (separación estéreo).
    private func split(_ env: Env) async throws -> (UUID, URL) {
        let id = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "a.mp3"))
        await env.library.waitForSeparations()
        _ = try await env.library.saveGuitarStereoSplit(id: id, true)
        await env.library.waitForSeparations()
        let calls = await env.splitter.calls
        XCTAssertEqual(calls, 1)
        return (id, try env.folder(id))
    }

    private func guitarStem(_ folder: URL) -> URL { ProjectLayout(folder: folder).stemURL(.guitar) }

    /// Simula la copia: misma ruta y contenido, otra fecha de modificación.
    private func touch(_ url: URL, by seconds: TimeInterval = 86_400) throws {
        let a = try FileManager.default.attributesOfItem(atPath: url.path)
        let old = try XCTUnwrap(a[.modificationDate] as? Date)
        try FileManager.default.setAttributes([.modificationDate: old.addingTimeInterval(seconds)], ofItemAtPath: url.path)
    }

    /// Deja `guitarApplied` como en un proyecto anterior a este cambio (sin hash).
    private func dropHash(_ folder: URL, separationFinishedAt: Date? = nil) throws {
        var p = try ProjectFile.load(folder: folder)
        p.guitarApplied?.inputSHA256 = nil
        if let separationFinishedAt { p.separation.finishedAt = separationFinishedAt }
        try ProjectFile.save(p, to: folder)
    }

    private func reopen(_ env: Env, _ id: UUID) async throws -> Int {
        _ = try await env.library.ensureAnalysis(id: id)
        await env.library.waitForSeparations()
        return await env.splitter.calls
    }

    func testSplitStoresContentHash() async throws {
        let env = try await Env(withMeter: true, withAnalyzer: true, withGuitars: true)
        let (_, folder) = try await split(env)
        let p = try ProjectFile.load(folder: folder)
        XCTAssertEqual(p.guitarApplied?.inputSHA256, try Library.sha256(of: guitarStem(folder)))
    }

    func testSameDateDoesNotRedo() async throws {
        let env = try await Env(withMeter: true, withAnalyzer: true, withGuitars: true)
        let (id, _) = try await split(env)
        let calls = try await reopen(env, id)
        XCTAssertEqual(calls, 1)
    }

    func testDateChangedSameContentDoesNotRedoAndStoresNewDate() async throws {
        let env = try await Env(withMeter: true, withAnalyzer: true, withGuitars: true)
        let (id, folder) = try await split(env)
        let before = try ProjectFile.load(folder: folder)
        try touch(guitarStem(folder))
        let now = ProjectLayout(folder: folder).guitarInputFingerprint
        XCTAssertNotEqual(before.guitarApplied?.inputFingerprint, now)
        let calls = try await reopen(env, id)
        XCTAssertEqual(calls, 1)
        let after = try ProjectFile.load(folder: folder)
        XCTAssertEqual(after.guitarApplied?.inputFingerprint, now)            // fecha nueva guardada: no se rehashea
        XCTAssertEqual(after.guitarApplied?.inputSHA256, before.guitarApplied?.inputSHA256)
        XCTAssertEqual(after.guitarApplied?.options, before.guitarApplied?.options)
        XCTAssertEqual(after.guitarTracks, before.guitarTracks)
        let again = try await reopen(env, id)
        XCTAssertEqual(again, 1)
    }

    func testSameSizeDifferentContentRedoes() async throws {
        let env = try await Env(withMeter: true, withAnalyzer: true, withGuitars: true)
        let (id, folder) = try await split(env)
        let url = guitarStem(folder)
        var data = try Data(contentsOf: url)
        data[data.count - 1] ^= 0xFF
        try data.write(to: url)
        try touch(url, by: 60)
        let calls = try await reopen(env, id)
        XCTAssertEqual(calls, 2)
        let p = try ProjectFile.load(folder: folder)
        XCTAssertEqual(p.guitarApplied?.inputSHA256, try Library.sha256(of: url))
        XCTAssertEqual(p.guitarApplied?.inputFingerprint, ProjectLayout(folder: folder).guitarInputFingerprint)
    }

    func testDifferentSizeRedoes() async throws {
        let env = try await Env(withMeter: true, withAnalyzer: true, withGuitars: true)
        let (id, folder) = try await split(env)
        try Data("mucho más largo que el stem falso de guitarra".utf8).write(to: guitarStem(folder))
        let calls = try await reopen(env, id)
        XCTAssertEqual(calls, 2)
    }

    // MARK: Proyectos anteriores (huella sin hash)

    func testLegacySameFingerprintDoesNotRedoAndBackfillsHash() async throws {
        let env = try await Env(withMeter: true, withAnalyzer: true, withGuitars: true)
        let (id, folder) = try await split(env)
        try dropHash(folder)
        let updatedAt = try ProjectFile.load(folder: folder).updatedAt
        let calls = try await reopen(env, id)
        XCTAssertEqual(calls, 1)
        let p = try ProjectFile.load(folder: folder)
        XCTAssertEqual(p.guitarApplied?.inputSHA256, try Library.sha256(of: guitarStem(folder)))
        XCTAssertEqual(p.updatedAt, updatedAt)   // apunte interno: no cuenta como edición
        // Ya con hash, una copia posterior tampoco rehace.
        try touch(guitarStem(folder))
        let after = try await reopen(env, id)
        XCTAssertEqual(after, 1)
    }

    func testLegacyDateChangedWithSeparationBeforeGuitarsDoesNotRedo() async throws {
        let env = try await Env(withMeter: true, withAnalyzer: true, withGuitars: true)
        let (id, folder) = try await split(env)
        try dropHash(folder)
        let applied = try XCTUnwrap(ProjectFile.load(folder: folder).guitarApplied)
        XCTAssertLessThanOrEqual(try XCTUnwrap(ProjectFile.load(folder: folder).separation.finishedAt), applied.finishedAt)
        try touch(guitarStem(folder))
        let calls = try await reopen(env, id)
        XCTAssertEqual(calls, 1)
        let p = try ProjectFile.load(folder: folder)
        XCTAssertEqual(p.guitarApplied?.inputFingerprint, ProjectLayout(folder: folder).guitarInputFingerprint)
        XCTAssertEqual(p.guitarApplied?.inputSHA256, try Library.sha256(of: guitarStem(folder)))
    }

    func testLegacyReseparatedAfterGuitarsRedoes() async throws {
        // Una reseparación del mismo audio deja el mismo tamaño: sin hash, la fecha de la separación decide.
        let env = try await Env(withMeter: true, withAnalyzer: true, withGuitars: true)
        let (id, folder) = try await split(env)
        let applied = try XCTUnwrap(ProjectFile.load(folder: folder).guitarApplied)
        try dropHash(folder, separationFinishedAt: applied.finishedAt.addingTimeInterval(60))
        let url = guitarStem(folder)
        var data = try Data(contentsOf: url)
        data[0] ^= 0xFF
        try data.write(to: url)
        try touch(url, by: 60)
        let calls = try await reopen(env, id)
        XCTAssertEqual(calls, 2)
    }

    func testOldJSONWithoutHashDecodesAndNilIsNotWritten() throws {
        // Sin hash no se escribe la clave: es exactamente el JSON de antes, y se lee igual.
        let legacy = GuitarAppliedState(inputFingerprint: "12-1.000000", options: GuitarOptions())
        let encoded = String(decoding: try JSONEncoder().encode(legacy), as: UTF8.self)
        XCTAssertFalse(encoded.contains("inputSHA256"))
        let back = try JSONDecoder().decode(GuitarAppliedState.self, from: Data(encoded.utf8))
        XCTAssertEqual(back, legacy)
    }

    func testFingerprintSizeParsing() {
        XCTAssertEqual(ProjectLayout.fingerprintSize("92160044-1732300000.123456"), 92_160_044)
        XCTAssertNil(ProjectLayout.fingerprintSize("a"))
    }

    /// Coste del hash para un stem de ~4 min (estéreo, float32, 48 kHz ≈ 92 MB). Se imprime; la cota es holgada.
    func testHashCostForFourMinuteStem() throws {
        let dir = try makeTempDir("hashcost")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("guitar.wav")
        let bytes = 4 * 60 * 48_000 * 2 * 4
        var data = Data(count: bytes)
        data.withUnsafeMutableBytes { raw in
            let words = raw.bindMemory(to: UInt64.self)
            var x: UInt64 = 0x9E37_79B9_7F4A_7C15
            for i in words.indices { x ^= x << 13; x ^= x >> 7; x ^= x << 17; words[i] = x }
        }
        try data.write(to: url)
        let t0 = Date()
        _ = try Library.sha256(of: url)
        let ms = Date().timeIntervalSince(t0) * 1000
        print("SHA-256 de \(bytes / 1_000_000) MB: \(Int(ms)) ms")
        XCTAssertLessThan(ms, 5000)
    }
}
