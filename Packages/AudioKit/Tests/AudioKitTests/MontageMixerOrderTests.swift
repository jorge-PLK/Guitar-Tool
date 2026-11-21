#if canImport(AVFoundation)
import AVFoundation
#endif
import XCTest
@testable import AudioKit

/// La mezcla del montaje no depende del orden de un diccionario: los grupos se suman en un orden fijo
/// (`MontageMixer.summationOrder`), así que `mezcla.wav` sale idéntica byte a byte entre procesos.
final class MontageMixerOrderTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws { dir = try SynthWAV.tempDir() }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    /// Tres grupos cuya suma en coma flotante NO es asociativa: +64, −64 y 2^-19. Si el pequeño se suma
    /// antes que uno de los grandes se pierde (medio ulp de 64 es 2^-18); si va el último sobrevive y en
    /// 24 bits vale 16 LSB. Con el orden de un diccionario el resultado cambiaba de una ejecución a otra.
    func testMixIsByteIdenticalWhateverTheInsertionOrderOfGroups() async throws {
        let rate = 48_000.0
        let n = 4_800
        let big: Float = 0.5
        let tiny = Float(pow(2.0, -19.0))
        let bigGainDB = 20 * log10(128.0)   // 0,5 · 128 = 64
        func wav(_ name: String, _ v: Float) throws -> URL {
            let url = dir.appendingPathComponent("\(name).wav")
            try SynthWAV.write([[Float](repeating: v, count: n)], rate: rate, to: url)
            return url
        }
        let tracks: [MontageTrack] = [
            .init(id: "plus", url: try wav("plus", big), gainDB: bigGainDB, group: .backing),
            .init(id: "minus", url: try wav("minus", -big), gainDB: bigGainDB, group: .part("A")),
            .init(id: "tiny", url: try wav("tiny", tiny), group: .part("B")),
        ]
        let permutations = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
        var files: [Data] = []
        var values: [Float] = []
        // Varias vueltas por orden: cada diccionario nuevo puede recorrerse en otro orden.
        for round in 0..<4 {
            for (k, p) in permutations.enumerated() {
                let out = dir.appendingPathComponent("out-\(round)-\(k).wav")
                let job = MontageMixJob(start: 0, end: Double(n) / rate, sampleRate: rate, tracks: p.map { tracks[$0] },
                                        normalization: .none, mixURL: out)
                let r = try await MontageMixer.mix(job)
                files.append(try Data(contentsOf: r.mixURL))
                values.append(try AudioSamples.read(r.mixURL)[0][n / 2])
            }
        }
        let distinct = Set(files).count
        let distinctValues = Set(values).sorted()
        print("F7 orden de suma: \(files.count) mezclas, \(distinct) ficheros distintos, valores \(distinctValues)")
        XCTAssertEqual(distinct, 1, "mezcla.wav depende del orden de inserción de los grupos")
        // Orden fijo documentado: fondo, luego partes por nombre → (+64 − 64) + 2^-19 = 2^-19 exacto.
        XCTAssertEqual(distinctValues, [tiny])
    }

    func testSummationOrderPutsBackingFirstThenPartsByName() {
        let order = MontageMixer.summationOrder([.part("Solo"), .part("Bajo"), .backing, .part("Rítmica")])
        XCTAssertEqual(order, [.backing, .part("Bajo"), .part("Rítmica"), .part("Solo")])
    }
}
