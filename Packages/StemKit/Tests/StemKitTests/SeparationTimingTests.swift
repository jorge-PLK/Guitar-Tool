import XCTest
import NativePlatform
@testable import StemKit

/// `TF_SEPARATE_TIMING` (Fase 7c, arreglo F3): tiempos exclusivos que suman el total de reloj, recuentos por trozo,
/// el `Run` simulado medido con su retardo y salida idéntica bit a bit con la medida encendida o apagada.
final class SeparationTimingTests: XCTestCase {
    /// Margen del `Run` simulado: `Thread.sleep` puede pasarse, nunca quedarse corto; 15 ms por trozo de holgura.
    static let sleepSlackPerChunk = 0.015
    /// Coste de la contabilidad de una medida anidada (dos cerrojos y dos lecturas del reloj): < 0,5 ms.
    static let bookkeepingTolerance = 0.0005

    override func tearDown() {
        SeparationTiming.setEnabledForTesting(false)
        super.tearDown()
    }

    private func spin(_ seconds: Double) {
        let end = HostClock.now() + HostClock.ticks(seconds: seconds)
        while HostClock.now() < end {}
    }

    private func report() throws -> SeparationTiming.Report {
        try XCTUnwrap(SeparationTiming.snapshot(end: HostClock.now()))
    }

    private func seconds(_ r: SeparationTiming.Report, _ s: SeparationTiming.Stage) -> Double { r.seconds[s.rawValue] }
    private func count(_ r: SeparationTiming.Report, _ s: SeparationTiming.Stage) -> Int { r.counts[s.rawValue] }

    /// Apagado: ningún estado (el informe no existe) y el cuerpo corre igual.
    func testDisabledRecordsNothing() {
        SeparationTiming.setEnabledForTesting(false)
        SeparationTiming.start()
        var ran = false
        SeparationTiming.measure(.stft) { ran = true }
        XCTAssertTrue(ran)
        XCTAssertNil(SeparationTiming.snapshot(end: HostClock.now()))
    }

    /// 20 ms en el padre y 30 ms en el hijo: el padre cuenta solo los suyos y padre + hijo = pared de fuera.
    func testNestedMeasuresAreExclusive() throws {
        SeparationTiming.setEnabledForTesting(true)
        SeparationTiming.start()
        let t0 = HostClock.now()
        SeparationTiming.measure(.overlapAdd) {
            spin(0.020)
            SeparationTiming.measure(.write) { spin(0.030) }
        }
        let wall = HostClock.seconds(ticks: HostClock.now() - t0)
        let r = try report()
        let parent = seconds(r, .overlapAdd), child = seconds(r, .write)
        print(String(format: "[F3] anidado: padre %.3f ms (20), hijo %.3f ms (30), pared %.3f ms, padre+hijo-pared %.4f ms",
                     1000 * parent, 1000 * child, 1000 * wall, 1000 * (parent + child - wall)))
        XCTAssertGreaterThanOrEqual(parent, 0.020)
        XCTAssertLessThan(parent, 0.020 + 0.005)
        XCTAssertGreaterThanOrEqual(child, 0.030)
        XCTAssertLessThan(child, 0.030 + 0.005)
        XCTAssertEqual(parent + child, wall, accuracy: Self.bookkeepingTolerance)
        XCTAssertEqual(count(r, .overlapAdd), 1)
        XCTAssertEqual(count(r, .write), 1)
    }

    /// Separación completa a 48 kHz (remuestreo de ida y vuelta) con el modelo simulado y 20 ms de `Run` por trozo.
    func testSimulatedSeparationBreakdown() throws {
        let rate = 48_000.0, n = 4 * 51_200 + 333, delay = 0.020
        let audio = StereoAudio(left: ToneMix.standard(rate: rate, channel: 0).render(n),
                                right: ToneMix.standard(rate: rate, channel: 1).render(n), sampleRate: rate)
        let dir = try makeTempDir("timing")
        let input = dir.appendingPathComponent("mix.wav")
        try writeStereo(audio, to: input)

        func run(_ name: String) throws -> (stems: [Stem: StereoAudio], chunks: Int) {
            let out = dir.appendingPathComponent(name)
            var total = 0
            try RoformerSeparator(model: ConstantMaskModel(frames: 101, delay: delay))
                .separate(input: input, outputDirectory: out, progress: { _, t in total = t })
            var stems: [Stem: StereoAudio] = [:]
            for s in Stem.allCases { stems[s] = try AudioIO.readStereo(out.appendingPathComponent(s.fileName)) }
            return (stems, total)
        }

        SeparationTiming.setEnabledForTesting(false)
        let off = try run("off")
        SeparationTiming.setEnabledForTesting(true)
        SeparationTiming.start()
        let on = try run("on")
        let r = try report()
        print(r.render())

        // Salida idéntica bit a bit con la medida encendida (dos pasadas paralelas en vez de una).
        for s in Stem.allCases {
            XCTAssertEqual(on.stems[s]!.left, off.stems[s]!.left, "\(s.rawValue) L")
            XCTAssertEqual(on.stems[s]!.right, off.stems[s]!.right, "\(s.rawValue) R")
        }

        let chunks = on.chunks
        XCTAssertGreaterThan(chunks, 2)
        XCTAssertEqual(r.chunks, chunks)
        XCTAssertEqual(count(r, .runFirst), 1)
        XCTAssertEqual(count(r, .run), chunks - 1)
        for stage: SeparationTiming.Stage in [.chunking, .stft, .readOutput, .applyMask, .istft, .overlapAdd] {
            XCTAssertEqual(count(r, stage), chunks, stage.label)
        }
        // El solape solo entrega (y escribe) cuando el tramo cae dentro de la canción: no en el borde de relleno.
        XCTAssertGreaterThan(count(r, .write), 0)
        XCTAssertLessThanOrEqual(count(r, .write), chunks)
        XCTAssertEqual(count(r, .prepareInput), 0, "el simulado no prepara tensores")
        XCTAssertEqual(count(r, .decode), 1)
        XCTAssertEqual(count(r, .resampleIn), 1)
        XCTAssertEqual(count(r, .resampleOut), Stem.allCases.count)
        XCTAssertEqual(count(r, .finalize), 1)

        // El Run simulado: chunks · 20 ms, con la holgura de Thread.sleep.
        let runTotal = seconds(r, .runFirst) + seconds(r, .run)
        print(String(format: "[F3] Run simulado: %.1f ms para %d trozos (esperado %.1f ms, holgura %.0f ms)",
                     1000 * runTotal, chunks, 1000 * delay * Double(chunks), 1000 * Self.sleepSlackPerChunk * Double(chunks)))
        XCTAssertGreaterThanOrEqual(runTotal, delay * Double(chunks))
        XCTAssertLessThan(runTotal, (delay + Self.sleepSlackPerChunk) * Double(chunks))

        // Exclusivos: ninguna etapa negativa, la suma no pasa del total y suma + resto = total.
        XCTAssertTrue(r.seconds.allSatisfy { $0 >= 0 })
        XCTAssertGreaterThanOrEqual(r.restSeconds, 0, "doble cuenta: la suma de etapas pasa del total")
        XCTAssertEqual(r.measuredSeconds + r.restSeconds, r.totalSeconds, accuracy: 1e-12)
        for stage: SeparationTiming.Stage in [.decode, .resampleIn, .stft, .istft, .overlapAdd, .write, .resampleOut] {
            XCTAssertGreaterThan(seconds(r, stage), 0, stage.label)
        }
    }

    /// Tabla: solo ASCII, una fila por etapa más resto y total, y medias por trozo con su regla.
    func testReportRendering() {
        var secs = [Double](repeating: 0, count: SeparationTiming.Stage.allCases.count)
        var counts = [Int](repeating: 0, count: secs.count)
        secs[SeparationTiming.Stage.load.rawValue] = 2; counts[SeparationTiming.Stage.load.rawValue] = 1
        secs[SeparationTiming.Stage.runFirst.rawValue] = 3; counts[SeparationTiming.Stage.runFirst.rawValue] = 1
        secs[SeparationTiming.Stage.run.rawValue] = 20; counts[SeparationTiming.Stage.run.rawValue] = 4
        secs[SeparationTiming.Stage.istft.rawValue] = 1; counts[SeparationTiming.Stage.istft.rawValue] = 5
        let r = SeparationTiming.Report(totalSeconds: 30, seconds: secs, counts: counts, engine: "prueba", processors: 4)
        XCTAssertEqual(r.chunks, 5)
        XCTAssertEqual(r.restSeconds, 4, accuracy: 1e-12)
        XCTAssertEqual(r.meanMilliseconds(.run)!, 5000, accuracy: 1e-9)       // 20 s / 4 llamadas
        XCTAssertEqual(r.meanMilliseconds(.runFirst)!, 3000, accuracy: 1e-9)  // una llamada
        XCTAssertEqual(r.meanMilliseconds(.load)!, 400, accuracy: 1e-9)       // 2 s amortizados en 5 trozos
        XCTAssertEqual(r.meanMilliseconds(.istft)!, 200, accuracy: 1e-9)
        XCTAssertNil(r.meanMilliseconds(.stft))
        let text = r.render()
        print(text)
        XCTAssertTrue(text.unicodeScalars.allSatisfy { $0.isASCII }, "tabla con caracteres no ASCII")
        for stage in SeparationTiming.Stage.allCases { XCTAssertTrue(text.contains(stage.label), stage.label) }
        let rest = text.split(separator: "\n").first { $0.hasPrefix("resto") }.map(String.init) ?? ""
        XCTAssertTrue(rest.contains("4.000") && rest.contains("800.0") && rest.contains("13.3"), rest)
        let total = text.split(separator: "\n").first { $0.hasPrefix("total de reloj") }.map(String.init) ?? ""
        XCTAssertTrue(total.contains("30.000") && total.contains("6000.0") && total.contains("100.0"), total)
    }
}
