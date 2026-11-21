import Synchronization
import XCTest
@testable import StemKit

/// MemoryGuard y SeparationRunner contra ejecutables reales del paquete: tf-memhog y tf-separate --simulate.
final class RunnerTests: XCTestCase {
    var separateURL: URL { builtProduct("tf-separate") }
    var memhogURL: URL { builtProduct("tf-memhog") }

    private func collect(_ stream: AsyncThrowingStream<SeparationEvent, Error>)
        async -> (events: [SeparationEvent], error: Error?) {
        var events: [SeparationEvent] = []
        do {
            for try await e in stream { events.append(e) }
            return (events, nil)
        } catch {
            return (events, error)
        }
    }

    private func toneWav(_ name: String, frames n: Int, rate: Double = 44_100) throws -> URL {
        let dir = try makeTempDir(name)
        let url = dir.appendingPathComponent("mix.wav")
        try writeStereo(StereoAudio(left: ToneMix.standard(rate: rate, channel: 0).render(n),
                                    right: ToneMix.standard(rate: rate, channel: 1).render(n),
                                    sampleRate: rate), to: url)
        return url
    }

    /// MemoryGuard solo: tf-memhog toca 400 MB con límite de 200 MB → SIGKILL y pico > 200 MB.
    func testMemoryGuardKillsProcessOverLimit() throws {
        let p = Process()
        p.executableURL = memhogURL
        p.arguments = ["400"]
        // Tubería que se vacía, no `FileHandle.nullDevice`: en Windows tf-memhog salía con código 29 a los
        // ~70 MB escribiendo en el dispositivo nulo (medido en la VM).
        let sink = Pipe()
        sink.fileHandleForReading.readabilityHandler = { h in
            if h.availableData.isEmpty { h.readabilityHandler = nil }
        }
        p.standardOutput = sink
        try p.run()
        let killed = expectation(description: "SIGKILL")
        let g = MemoryGuard(pid: p.processIdentifier, limitBytes: 200_000_000) { _ in killed.fulfill() }
        g.start()
        wait(for: [killed], timeout: 20)
        p.waitUntilExit()
        #if os(Windows)
        // TerminateProcess con 128 + SIGKILL (ChildProcess.killedExitCode).
        XCTAssertEqual(p.terminationStatus, 137)
        #else
        XCTAssertEqual(p.terminationReason, .uncaughtSignal)
        XCTAssertEqual(p.terminationStatus, SIGKILL)
        #endif
        XCTAssertTrue(g.limitExceeded)
        XCTAssertGreaterThan(g.peakBytes, 200_000_000)
        print("MemoryGuard: pico \(g.peakBytes / 1_000_000) MB con límite 200 MB")
    }

    func testRunnerMemoryLimitExceeded() async throws {
        let runner = SeparationRunner(helperURL: memhogURL, memoryLimitBytes: 200_000_000)
        let (events, error) = await collect(runner.launch(arguments: ["400"]))
        XCTAssertEqual(events.first, .loading)
        guard case SeparationError.memoryLimitExceeded(let peak)? = error as? SeparationError else {
            return XCTFail("se esperaba memoryLimitExceeded y llegó \(String(describing: error))")
        }
        XCTAssertGreaterThan(peak, 200_000_000)
    }

    /// tf-separate --simulate: JSON de progreso → loading, progreso monótono hasta 1, finished; stems escritos.
    func testRunnerParsesProgressAndFinishes() async throws {
        let n = 3 * 51_200 + 99
        let input = try toneWav("runner-ok", frames: n)
        let out = input.deletingLastPathComponent().appendingPathComponent("stems")
        let runner = SeparationRunner(helperURL: separateURL)
        let (events, error) = await collect(runner.launch(arguments: [
            "--simulate", "--sim-frames", "101", "--input", input.path, "--out", out.path]))
        XCTAssertNil(error)
        XCTAssertEqual(events.first, .loading)
        let fractions = events.compactMap { if case .progress(let f) = $0 { f } else { nil } }
        let expectedChunks = ChunkPlan(inputLength: n, chunk: 51_200).count
        XCTAssertEqual(fractions, (0...expectedChunks).map { Double($0) / Double(expectedChunks) })
        guard case .finished(let seconds, _)? = events.last else { return XCTFail("falta finished: \(events)") }
        XCTAssertGreaterThan(seconds, 0)
        for s in Stem.allCases {
            let st = try AudioIO.readStereo(out.appendingPathComponent(s.fileName))
            XCTAssertEqual(st.frameCount, n)
        }
    }

    /// Cancelar el Task que consume el stream termina el helper (SIGTERM; SIGKILL si no sale en 5 s).
    func testCancelTerminatesHelper() async throws {
        let input = try toneWav("runner-cancel", frames: 5 * 44_100)
        let out = input.deletingLastPathComponent().appendingPathComponent("stems")
        let pidBox = Mutex<Int32>(0)
        var runner = SeparationRunner(helperURL: separateURL)
        runner.onLaunch = { pid in pidBox.withLock { $0 = pid } }
        let started = expectation(description: "primer trozo")
        let stream = runner.launch(arguments: ["--simulate", "--sim-frames", "51", "--sim-delay-ms", "400",
                                               "--input", input.path, "--out", out.path])
        let task = Task {
            var fulfilled = false
            for try await e in stream {
                if case .progress(let f) = e, f > 0, !fulfilled { fulfilled = true; started.fulfill() }
            }
        }
        await fulfillment(of: [started], timeout: 30)
        let pid = pidBox.withLock { $0 }
        XCTAssertTrue(pid > 0 && processAlive(pid))
        let t0 = Date()
        task.cancel()
        var alive = true
        while alive && Date().timeIntervalSince(t0) < 8 {
            try await Task.sleep(for: .milliseconds(50))
            alive = processAlive(pid)
        }
        let elapsed = Date().timeIntervalSince(t0)
        print("cancelación: helper terminado en \(String(format: "%.2f", elapsed)) s")
        XCTAssertFalse(alive, "el helper sigue vivo tras \(elapsed) s")
        XCTAssertLessThan(elapsed, SeparationRunner.terminateGrace + 1)
        // Windows: el evento de parada (parte 7.8) deja salir al helper por su camino ordenado, que borra la carpeta.
        let left = (try? FileManager.default.contentsOfDirectory(atPath: out.path)) ?? []
        XCTAssertTrue(left.allSatisfy { !$0.hasSuffix(".wav") && !$0.hasPrefix(".tf-separate") }, "\(left)")
    }

    /// Código de salida ≠ 0 → helperFailed con la cola de stderr.
    func testHelperFailureCarriesStderrTail() async throws {
        let dir = try makeTempDir("runner-fail")
        let runner = SeparationRunner(helperURL: separateURL)
        let (_, error) = await collect(runner.launch(arguments: [
            "--simulate", "--input", dir.appendingPathComponent("no-existe.wav").path, "--out", dir.path]))
        guard case SeparationError.helperFailed(let code, let tail)? = error as? SeparationError else {
            return XCTFail("se esperaba helperFailed y llegó \(String(describing: error))")
        }
        XCTAssertEqual(code, 1)
        XCTAssertTrue(tail.contains("tf-separate:") && tail.contains("no-existe.wav"), tail)
    }

    func testRunnerRejectsMissingInput() async throws {
        let dir = try makeTempDir("runner-missing")
        let runner = SeparationRunner(helperURL: separateURL)
        let (_, error) = await collect(runner.run(model: dir, input: dir.appendingPathComponent("x.wav"),
                                                  outputDirectory: dir))
        guard case SeparationError.invalidInput? = error as? SeparationError else {
            return XCTFail("\(String(describing: error))")
        }
    }

    func testHelperUsageErrorExitCode2() async throws {
        let (_, error) = await collect(SeparationRunner(helperURL: separateURL).launch(arguments: ["--bogus"]))
        guard case SeparationError.helperFailed(let code, _)? = error as? SeparationError else {
            return XCTFail("\(String(describing: error))")
        }
        XCTAssertEqual(code, 2)
    }
}
