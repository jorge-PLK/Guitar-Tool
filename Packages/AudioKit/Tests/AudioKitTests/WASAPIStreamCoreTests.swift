import XCTest
@testable import AudioKit

/// `WASAPIStreamCore`: el bombeo de `WASAPIAudioIO` probado en el Mac con un dispositivo WASAPI simulado (mismo reloj
/// en render y captura, por eventos, marcas QPC con temblor, la captura arrancada antes que el render, como en P8).
///
/// Lo que decide (plan, «Fase 7c», «Audio»: marcas QPC por búfer «para conservar la medida de latencia y el alineado»):
/// un clic escrito en la muestra `y` de la salida vuelve por la entrada en la muestra `n` con `n − y` = latencia física
/// del bucle, igual en cada arranque. Umbrales: variación entre arranques < 0,2 ms (plan, «Pruebas de Jorge en un PC»,
/// `tf-audio latency --restarts 10`) y error < 1 ms (`AlignmentCheck.passThresholdSeconds`).
final class WASAPIStreamCoreTests: XCTestCase {
    static let fs = 48_000.0

    // MARK: Dispositivo simulado

    /// Generador con semilla (LCG de Knuth).
    struct RNG {
        var state: UInt64
        mutating func uniform() -> Double {   // [-1, 1)
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53) * 2 - 1
        }
        mutating func gaussian() -> Double {  // Box-Muller, σ = 1
            let u1 = max(1e-12, (uniform() + 1) / 2), u2 = (uniform() + 1) / 2
            return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
        }
    }

    enum Jitter {
        case uniform(render: Double, capture: Double)
        case gaussian(render: Double, capture: Double)
    }

    struct Config {
        var seed: UInt64 = 1
        /// P8 (VM, «Altavoces» con IAudioClient3): periodo 128, búfer 280; IAudioClock en bytes/s (48 kHz · 2 ch · 4 B).
        var renderPeriod = 128
        var renderBuffer = 280
        var clockFrequency: UInt64 = 384_000
        /// P8 «Línea de entrada»: paquetes de ~10 ms.
        var capturePeriod = 480
        /// Latencia física del bucle (DAC → ADC), en fotogramas.
        var latencyFrames = 237
        /// La captura arranca estos fotogramas antes que el render (Start de los dos clientes no es simultáneo).
        var captureLeadFrames = 400
        var jitter = Jitter.uniform(render: 0.0005, capture: 0.0005)
        var seconds = 3.5
        var chunkFrames = WASAPIStreamCore.defaultChunkFrames
        /// Discontinuidad en el paquete `packet`: se pierden `lostFrames` fotogramas de captura.
        var discontinuity: (packet: Int, lostFrames: Int)?
        /// Cada cuántos paquetes llega uno con `AUDCLNT_BUFFERFLAGS_TIMESTAMP_ERROR` y la marca 50 ms desviada (0 = nunca).
        var timestampErrorEvery = 37
        /// Clics en la salida (muestras de la línea común).
        var clicks: [Int64] = (0..<6).map { 96_000 + Int64($0) * 12_000 }
    }

    struct Result {
        /// `n − y − latencia` de cada clic, en muestras.
        var errors: [Int64] = []
        var clicksFound: [Int64] = []
        var renderHostErrorMax = 0.0
        var captureHostErrorMax = 0.0
        var renderBlocks: [(start: Int64, count: Int)] = []
        var captureBlocks: [(start: Int64, count: Int)] = []
        var channelSwaps = 0
        var unwrittenReads = 0
        var maxBlock = 0
    }

    /// Lo que tocan los manejadores (los llama el test, en su hilo).
    final class Box: @unchecked Sendable {
        var r = Result()
    }

    static func run(_ cfg: Config) -> (Result, WASAPIStreamCore) {
        let fs = Self.fs
        let core = WASAPIStreamCore(sampleRate: fs, inputChannels: 2, outputChannels: 2, shared: true,
                                    chunkFrames: cfg.chunkFrames)
        let box = Box()
        let clicks = cfg.clicks
        let lead = cfg.captureLeadFrames
        let tR0 = 86_400.0 + Double(cfg.seed)          // QPC tras un día encendido
        let tC0 = tR0 - Double(cfg.captureLeadFrames) / fs
        let warm = 1.2                                   // s de render antes de mirar las marcas de host
        core.prepare(render: { b in
            for y in clicks where y >= b.sampleTime && y < b.sampleTime + Int64(b.frameCount) {
                b[0][Int(y - b.sampleTime)] = 1
            }
            for i in 0..<b.frameCount { b[1][i] = 0.25 }
            box.r.renderBlocks.append((b.sampleTime, b.frameCount))
            box.r.maxBlock = max(box.r.maxBlock, b.frameCount)
            if b.hostSeconds > 0, Double(b.sampleTime) / fs > warm {
                box.r.renderHostErrorMax = max(box.r.renderHostErrorMax, abs(b.hostSeconds - (tR0 + Double(b.sampleTime) / fs)))
            }
        }, capture: { b in
            for i in 0..<b.frameCount {
                if b[0][i] > 0.5 { box.r.clicksFound.append(b.sampleTime + Int64(i)) }
                if b[0][i] == 0.25 || b[1][i] > 0.5 { box.r.channelSwaps += 1 }
            }
            box.r.captureBlocks.append((b.sampleTime, b.frameCount))
            box.r.maxBlock = max(box.r.maxBlock, b.frameCount)
            // Verdad: el fotograma de captura c se tomó en tC0 + c/fs, y c = n + adelanto (offset verdadero = −adelanto).
            if b.hostSeconds > 0 {
                let truth = tC0 + Double(b.sampleTime + Int64(lead)) / fs
                box.r.captureHostErrorMax = max(box.r.captureHostErrorMax, abs(b.hostSeconds - truth))
            }
        })

        var rng = RNG(state: cfg.seed &* 0x9E37_79B9_7F4A_7C15 | 1)
        func jitter(_ capture: Bool) -> Double {
            switch cfg.jitter {
            case let .uniform(r, c): return (capture ? c : r) * rng.uniform()
            case let .gaussian(r, c): return (capture ? c : r) * rng.gaussian()
            }
        }
        // Lo que suena: cinta por canal, indexada por fotograma escrito (el silencio previo al arranque cuenta).
        var tape0 = [Float](repeating: 0, count: cfg.renderBuffer)
        var tape1 = [Float](repeating: 0, count: cfg.renderBuffer)
        var framesWritten = UInt64(cfg.renderBuffer)
        let out = UnsafeMutablePointer<Float>.allocate(capacity: cfg.renderBuffer * 2)
        let inp = UnsafeMutablePointer<Float>.allocate(capacity: cfg.capturePeriod * 2)
        defer { out.deallocate(); inp.deallocate() }

        var m = 1, j = 0, lost = 0
        let end = tR0 + cfg.seconds
        while true {
            let tr = tR0 + Double(m * cfg.renderPeriod) / fs
            // Los fotogramas perdidos también pasan en el tiempo: el paquete llega cuando termina su último fotograma.
            let pending = cfg.discontinuity.map { $0.packet == j ? $0.lostFrames : 0 } ?? 0
            let tc = tC0 + Double((j + 1) * cfg.capturePeriod + lost + pending) / fs
            if min(tr, tc) > end { break }
            if tr <= tc {
                // Despertar de render: el motor ha consumido m·periodo fotogramas.
                let played = UInt64(m * cfg.renderPeriod)
                let padding = framesWritten > played ? framesWritten - played : 0
                let avail = cfg.renderBuffer - Int(padding)
                out.update(repeating: 0, count: avail * 2)
                let marks = WASAPIRenderMarks(framesWritten: framesWritten,
                                              clockPosition: played * cfg.clockFrequency / UInt64(fs),
                                              clockQPC100ns: UInt64(((tr + jitter(false)) * 1e7).rounded()),
                                              clockFrequency: cfg.clockFrequency, paddingFrames: UInt32(padding))
                core.render(interleaved: out, frames: avail, channels: 2, marks: marks)
                for i in 0..<avail {
                    tape0.append(out[i * 2])
                    tape1.append(out[i * 2 + 1])
                }
                framesWritten += UInt64(avail)
                m += 1
            } else {
                // Paquete de captura: fotogramas de dispositivo [c, c + periodo).
                var flags: UInt32 = j == 0 ? WASAPICaptureMarks.discontinuity : 0   // P8: el primero la trae
                if let d = cfg.discontinuity, d.packet == j {
                    lost += d.lostFrames
                    flags |= WASAPICaptureMarks.discontinuity
                }
                let c = j * cfg.capturePeriod + lost
                for i in 0..<cfg.capturePeriod {
                    let k = c + i - cfg.captureLeadFrames - cfg.latencyFrames
                    if k >= tape0.count { box.r.unwrittenReads += 1 }
                    inp[i * 2] = k >= 0 && k < tape0.count ? tape0[k] : 0
                    inp[i * 2 + 1] = k >= 0 && k < tape1.count ? tape1[k] : 0
                }
                var qpcTime = tC0 + Double(c) / fs + jitter(true)
                if cfg.timestampErrorEvery > 0, j > 0, j % cfg.timestampErrorEvery == 0 {
                    flags |= WASAPICaptureMarks.timestampError
                    qpcTime += 0.05
                }
                let marks = WASAPICaptureMarks(streamPosition: UInt64(c), qpc100ns: UInt64((qpcTime * 1e7).rounded()),
                                               flags: flags)
                core.capture(interleaved: inp, frames: cfg.capturePeriod, channels: 2, marks: marks)
                j += 1
            }
        }
        var r = box.r
        // Cada clic encontrado frente al suyo: n − y − latencia.
        for (y, n) in zip(clicks, r.clicksFound) { r.errors.append(n - y - Int64(cfg.latencyFrames)) }
        return (r, core)
    }

    static func ms(_ samples: Double) -> Double { samples / fs * 1000 }

    static func assertConsecutive(_ blocks: [(start: Int64, count: Int)], allowJumps: Int = 0, _ what: String,
                                  file: StaticString = #filePath, line: UInt = #line) {
        var jumps = 0
        for (a, b) in zip(blocks, blocks.dropFirst()) where a.start + Int64(a.count) != b.start { jumps += 1 }
        XCTAssertEqual(jumps, allowJumps, "\(what): bloques no consecutivos", file: file, line: line)
    }

    // MARK: El punto fino

    func testRoundTripClickLandsOnPhysicalLatencyEveryRestart() throws {
        // 20 arranques con adelanto de captura y latencia distintos, temblor ±0,5 ms en las dos marcas y un paquete de
        // cada 37 con marca errónea.
        var all: [Int64] = [], hostR = 0.0, hostC = 0.0
        for seed in 1...20 {
            var cfg = Config()
            cfg.seed = UInt64(seed)
            cfg.captureLeadFrames = 37 * seed % 960          // 0-20 ms
            cfg.latencyFrames = 200 + 13 * seed               // 4,4-9,6 ms
            let (r, core) = Self.run(cfg)
            XCTAssertEqual(r.clicksFound.count, cfg.clicks.count, "semilla \(seed)")
            XCTAssertEqual(r.unwrittenReads, 0)
            XCTAssertEqual(r.channelSwaps, 0, "canales cruzados al entrelazar o desentrelazar")
            Self.assertConsecutive(r.renderBlocks, "salida, semilla \(seed)")
            Self.assertConsecutive(r.captureBlocks, "entrada, semilla \(seed)")
            let d = core.counters.diagnostics
            XCTAssertEqual(d.inputJumps, 0, "la discontinuidad del primer paquete no es un salto")
            XCTAssertEqual(d.outputJumps, 0)
            XCTAssertEqual(d.overloads, 0)
            XCTAssertEqual(core.captureResets, 0)
            XCTAssertGreaterThan(core.droppedCaptureFrames, 0, "el arranque se descarta hasta fijar el offset")
            XCTAssertEqual(core.hostLog.snapshot().count, r.captureBlocks.count)
            all += r.errors
            hostR = max(hostR, r.renderHostErrorMax)
            hostC = max(hostC, r.captureHostErrorMax)
        }
        let worst = Double(all.map { abs($0) }.max() ?? 0)
        let spread = Double((all.max() ?? 0) - (all.min() ?? 0))
        print("WASAPIStreamCore ±0,5 ms: n − y − latencia en 20 arranques: peor \(worst) muestras (\(Self.ms(worst)) ms), "
              + "máx − mín \(spread) muestras (\(Self.ms(spread)) ms); hostSeconds salida peor \(hostR * 1e3) ms, "
              + "captura \(hostC * 1e3) ms")
        // Variación entre arranques < 0,2 ms (plan); error < una quinta parte de 1 ms (como `DuplexClockSyncTests`).
        XCTAssertLessThan(Self.ms(spread), 0.2)
        XCTAssertLessThan(Self.ms(worst), AlignmentCheck.passThresholdSeconds * 1000 / 5)
        // Instantes de host (sincronía con la cámara, mini-spec Fase 6): sobre la recta, muy por debajo del temblor.
        XCTAssertLessThan(hostR, 0.0002)
        XCTAssertLessThan(hostC, 0.0002)
    }

    func testVMLikeJitterStaysInsideAlignmentTolerance() throws {
        // Temblor medido en la VM (P8: σ 1,3 ms salida, 2,7 ms captura), gaussiano. No es un PC: solo se exige el alineado.
        var all: [Int64] = []
        for seed in 1...20 {
            var cfg = Config()
            cfg.seed = UInt64(seed)
            cfg.captureLeadFrames = 37 * seed % 960
            cfg.jitter = .gaussian(render: 0.0013, capture: 0.0027)
            let (r, _) = Self.run(cfg)
            XCTAssertEqual(r.clicksFound.count, cfg.clicks.count, "semilla \(seed)")
            all += r.errors
        }
        let worst = Double(all.map { abs($0) }.max() ?? 0)
        let spread = Double((all.max() ?? 0) - (all.min() ?? 0))
        print("WASAPIStreamCore temblor de VM: peor \(worst) muestras (\(Self.ms(worst)) ms), máx − mín \(spread) muestras "
              + "(\(Self.ms(spread)) ms)")
        XCTAssertLessThan(Self.ms(worst), AlignmentCheck.passThresholdSeconds * 1000)
    }

    func testCaptureDiscontinuityRefitsOffsetAndKeepsLatency() throws {
        // A 1,5 s se pierden 1000 fotogramas de captura: el offset se vuelve a estimar (otro segundo de paquetes
        // descartados) y los clics posteriores siguen en la latencia física.
        var cfg = Config()
        cfg.seed = 7
        cfg.seconds = 5.0
        cfg.discontinuity = (packet: 150, lostFrames: 1000)
        cfg.clicks = (0..<6).map { 168_000 + Int64($0) * 9_600 }   // 3,5-4,5 s, tras volver a fijar
        let (r, core) = Self.run(cfg)
        XCTAssertEqual(r.clicksFound.count, cfg.clicks.count)
        XCTAssertEqual(core.captureResets, 1)
        XCTAssertEqual(core.counters.diagnostics.inputJumps, 1, "una discontinuidad, un salto")
        Self.assertConsecutive(r.captureBlocks, allowJumps: 1, "entrada")
        let worst = Double(r.errors.map { abs($0) }.max() ?? .max)
        print("WASAPIStreamCore tras discontinuidad: peor \(worst) muestras (\(Self.ms(worst)) ms)")
        XCTAssertLessThan(Self.ms(worst), AlignmentCheck.passThresholdSeconds * 1000 / 5)
    }

    func testChunkingDoesNotMoveAnySample() throws {
        // Trozos de 100 (menores que el periodo de render y que el paquete de captura): mismos clics, bloques ≤ 100.
        var small = Config()
        small.chunkFrames = 100
        let (a, _) = Self.run(Config())
        let (b, _) = Self.run(small)
        XCTAssertEqual(b.maxBlock, 100)
        XCTAssertGreaterThan(a.maxBlock, 100)
        XCTAssertEqual(a.clicksFound, b.clicksFound)
        XCTAssertEqual(b.channelSwaps, 0)
        Self.assertConsecutive(b.renderBlocks, "salida en trozos")
        Self.assertConsecutive(b.captureBlocks, "entrada en trozos")
    }

    // MARK: Contadores

    func testEmptySharedBufferCountsAsOverloadOnlyInSharedMode() {
        let buf = UnsafeMutablePointer<Float>.allocate(capacity: 256)
        defer { buf.deallocate() }
        for shared in [true, false] {
            let core = WASAPIStreamCore(sampleRate: Self.fs, inputChannels: 1, outputChannels: 2, shared: shared)
            core.prepare(render: { _ in }, capture: { _ in })
            let marks = WASAPIRenderMarks(framesWritten: 280, clockPosition: 0, clockQPC100ns: 0, clockFrequency: 384_000,
                                          paddingFrames: 0)
            core.render(interleaved: buf, frames: 128, channels: 2, marks: marks)
            // Fotogramas escritos que no siguen al búfer anterior: salto de salida.
            var next = marks
            next.framesWritten = 280 + 128 + 64
            next.paddingFrames = 100
            core.render(interleaved: buf, frames: 128, channels: 2, marks: next)
            let d = core.counters.diagnostics
            XCTAssertEqual(d.overloads, shared ? 1 : 0)
            XCTAssertEqual(d.outputJumps, 1)
            XCTAssertEqual(d.outputJumpMaxFrames, 64)
            XCTAssertEqual(d.callbacks, 2)
        }
    }

    func testHostTicksFromQPC100ns() {
        // HostClock en Windows es QPC (10 MHz típicos → 100 ns por tic); en el Mac, mach. Ida y vuelta en segundos.
        let q: UInt64 = 864_000_000_000 + 12_345
        XCTAssertEqual(HostTimeLog.seconds(WASAPIStreamCore.ticks(qpc100ns: q)), DuplexClockSync.seconds(qpc100ns: q),
                       accuracy: 1e-7)
        XCTAssertEqual(WASAPIStreamCore.ticks(qpc100ns: 0), 0)
    }
}
