#if canImport(AVFoundation)
import AVFoundation
#endif
import NativeAudioFile
import NativeDSP
import XCTest
@testable import AudioKit

final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []
    func add(_ v: Double) { lock.lock(); values.append(v); lock.unlock() }
    var all: [Double] { lock.lock(); defer { lock.unlock() }; return values }
}

/// En el Mac corre con AVAudioConverter y, en `AudioImporterPortableTests`, con la conversión de Windows
/// (dr_* + r8brain, forzada); en Windows, con la de Windows.
class AudioImporterTests: XCTestCase {
    let importer = AudioImporter()
    var tmpDir: URL!

    /// La subclase del Mac lo pone a cierto para forzar `AudioImporter.portableConvert`.
    class var portable: Bool { false }

    /// Ejecuta `body` con el conversor de la clase.
    func converting<T>(_ body: () async throws -> T) async throws -> T {
        #if canImport(AVFoundation)
        return try await AudioImporter.$forcePortable.withValue(Self.portable) { try await body() }
        #else
        return try await body()
        #endif
    }

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("AudioKitTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func fixture(_ name: String) -> URL {
        Bundle.module.resourceURL!.appendingPathComponent("Fixtures").appendingPathComponent(name)
    }

    let tonal = ["sine1k_mono_48k_24bit.wav", "sine1k_stereo_96k.flac", "sine1k_stereo_44k.mp3"]
    let rates: [Double] = [44_100, 48_000]

    func out(_ name: String = "out.wav") -> URL { tmpDir.appendingPathComponent(name) }

    func importFile(_ name: String, rate: Double, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> (ImportedAudio, URL) {
        let dest = out("\(UUID().uuidString).wav")
        let r = try await converting {
            try await importer.importAudio(from: fixture(name), to: dest, sampleRate: rate, progress: progress)
        }
        return (r, dest)
    }

    /// Lee el canal `ch` entero.
    func samples(_ url: URL, channel ch: Int = 0) throws -> [Float] {
        let f = try AudioFileReader(url: url)
        return try f.read(maxFrames: f.frameCount)[ch]
    }

    /// Frecuencia del pico de FFT (ventana Hann de 16384 muestras del centro) y ancho de bin.
    func peak(_ x: [Float], rate: Double) -> (freq: Double, bin: Double) {
        let n = 16_384
        let start = (x.count - n) / 2
        // Hann periódica (`vDSP_HANN_NORM`), en pares e impares para la DFT real empaquetada.
        var even = [Float](repeating: 0, count: n / 2), odd = [Float](repeating: 0, count: n / 2)
        for i in 0..<n {
            let w = Float(0.5 * (1 - cos(2 * Double.pi * Double(i) / Double(n))))
            if i % 2 == 0 { even[i / 2] = x[start + i] * w } else { odd[i / 2] = x[start + i] * w }
        }
        var re = [Float](repeating: 0, count: n / 2), im = [Float](repeating: 0, count: n / 2)
        DSP.RealDFT(count: n, direction: .forward)!.execute(even, odd, &re, &im)
        var maxI = 0, maxV: Float = 0
        for k in 1..<(n / 2) {          // k = 0 lleva DC y Nyquist empaquetados
            let m = re[k] * re[k] + im[k] * im[k]
            if m > maxV { maxV = m; maxI = k }
        }
        let bin = rate / Double(n)
        return (Double(maxI) * bin, bin)
    }

    /// Etiqueta de formato (1 PCM, 3 float, 0xFFFE extensible) y bits por muestra del bloque `fmt ` de un WAV.
    func wavFormat(_ url: URL) throws -> (tag: Int, bits: Int) {
        let d = [UInt8](try Data(contentsOf: url))
        func u16(_ i: Int) -> Int { Int(d[i]) | Int(d[i + 1]) << 8 }
        func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
        var p = 12
        while p + 8 <= d.count {
            let size = u32(p + 4)
            if d[p..<(p + 4)].elementsEqual(Array("fmt ".utf8)) {
                var tag = u16(p + 8)
                if tag == 0xFFFE, size >= 40 { tag = u16(p + 8 + 24) }    // subformato de WAVE_FORMAT_EXTENSIBLE
                return (tag, u16(p + 8 + 14))
            }
            p += 8 + size + (size & 1)
        }
        throw AudioFileError.unreadable("sin bloque fmt")
    }

    func assertTone(_ url: URL, rate: Double, file: StaticString = #filePath, line: UInt = #line) throws {
        let p = peak(try samples(url), rate: rate)
        XCTAssertEqual(p.freq, 1000, accuracy: p.bin, file: file, line: line)
    }

    // MARK: - Formato y duración

    func testOutputIsStereoFloat32AtBothRates() async throws {
        for name in tonal {
            for rate in rates {
                let (_, dest) = try await importFile(name, rate: rate)
                #if canImport(AVFoundation)
                let f = try AVAudioFile(forReading: dest)
                XCTAssertEqual(f.fileFormat.channelCount, 2, "\(name) @\(rate)")
                XCTAssertEqual(f.fileFormat.sampleRate, rate, "\(name) @\(rate)")
                XCTAssertEqual(f.fileFormat.commonFormat, .pcmFormatFloat32, "\(name) @\(rate)")
                XCTAssertEqual(f.fileFormat.settings[AVLinearPCMBitDepthKey] as? Int, 32)
                #else
                let f = try AudioFileReader(url: dest)
                XCTAssertEqual(f.channelCount, 2, "\(name) @\(rate)")
                XCTAssertEqual(f.sampleRate, rate, "\(name) @\(rate)")
                #endif
                let fmt = try wavFormat(dest)
                XCTAssertEqual(fmt.tag, 3, "IEEE float, \(name) @\(rate)")
                XCTAssertEqual(fmt.bits, 32, "\(name) @\(rate)")
                XCTAssertEqual(dest.pathExtension, "wav")
            }
        }
    }

    func testDurationPreserved() async throws {
        for name in tonal {
            for rate in rates {
                let (r, dest) = try await importFile(name, rate: rate)
                let dur = Double(try AudioFileReader(url: dest).frameCount) / rate
                XCTAssertEqual(r.duration, dur, accuracy: 1e-9)
                if name.hasSuffix(".mp3") {
                    XCTAssertEqual(dur * rate, 1.5 * rate, accuracy: 2048, "\(name) @\(rate)")
                } else {
                    XCTAssertEqual(dur, 1.5, accuracy: 0.001, "\(name) @\(rate)")
                }
            }
        }
    }

    func testSourceInfo() async throws {
        let (a, _) = try await importFile("sine1k_mono_48k_24bit.wav", rate: 44_100)
        XCTAssertEqual([a.sourceFormat, "\(a.sourceSampleRate)", "\(a.sourceChannels)"], ["wav", "48000.0", "1"])
        let (b, _) = try await importFile("sine1k_stereo_96k.flac", rate: 48_000)
        XCTAssertEqual([b.sourceFormat, "\(b.sourceSampleRate)", "\(b.sourceChannels)"], ["flac", "96000.0", "2"])
        let (c, _) = try await importFile("sine1k_stereo_44k.mp3", rate: 48_000)
        XCTAssertEqual([c.sourceFormat, "\(c.sourceSampleRate)", "\(c.sourceChannels)"], ["mp3", "44100.0", "2"])
    }

    func testToneStaysAt1kHz() async throws {
        for name in tonal {
            for rate in rates {
                let (_, dest) = try await importFile(name, rate: rate)
                try assertTone(dest, rate: rate)
            }
        }
    }

    func testMonoBecomesIdenticalChannels() async throws {
        let (_, dest) = try await importFile("sine1k_mono_48k_24bit.wav", rate: 44_100)
        let l = try samples(dest, channel: 0), r = try samples(dest, channel: 1)
        XCTAssertEqual(l, r)
        XCTAssertGreaterThan(l.map(abs).max() ?? 0, 0.1)
        // Mismo caso sin remuestreo (48k -> 48k).
        let (_, same) = try await importFile("sine1k_mono_48k_24bit.wav", rate: 48_000)
        XCTAssertEqual(try samples(same, channel: 0), try samples(same, channel: 1))
        XCTAssertEqual(try samples(same).count, 72_000)
    }

    func testResampleRoundTrip() async throws {
        let (_, a) = try await importFile("sine1k_stereo_44k.mp3", rate: 44_100)
        let up = out("up.wav"), back = out("back.wav")
        try await converting {
            try await importer.resample(a, to: up, sampleRate: 48_000)
            try await importer.resample(up, to: back, sampleRate: 44_100)
        }
        let fa = try AudioFileReader(url: a), fu = try AudioFileReader(url: up), fb = try AudioFileReader(url: back)
        XCTAssertEqual(fu.sampleRate, 48_000)
        XCTAssertEqual(fb.sampleRate, 44_100)
        XCTAssertEqual(Double(fb.frameCount) / 44_100, Double(fa.frameCount) / 44_100, accuracy: 0.001)
        XCTAssertEqual(Double(fu.frameCount) / 48_000, Double(fa.frameCount) / 44_100, accuracy: 0.001)
        try assertTone(up, rate: 48_000)
        try assertTone(back, rate: 44_100)
    }

    func testProgressMonotonicEndsAtOne() async throws {
        for name in ["sine1k_stereo_96k.flac", "sine1k_mono_48k_24bit.wav"] {
            let log = ProgressLog()
            _ = try await importFile(name, rate: 44_100) { log.add($0) }
            let v = log.all
            XCTAssertFalse(v.isEmpty)
            XCTAssertEqual(v.last, 1)
            XCTAssertEqual(v, v.sorted(), name)
            XCTAssertTrue(v.allSatisfy { $0 >= 0 && $0 <= 1 })
        }
    }

    // MARK: - Metadatos

    func testMP3Metadata() async throws {
        #if !canImport(AVFoundation)
        throw XCTSkip("[windows] sin etiquetas ID3 (fuera del corte del paso 7): el título sale del nombre del fichero")
        #endif
        let m = await importer.metadata(of: fixture("sine1k_stereo_44k.mp3"))
        XCTAssertEqual(m.title, "Tema MP3")
        XCTAssertEqual(m.artist, "Artista MP3")
        let (r, _) = try await importFile("sine1k_stereo_44k.mp3", rate: 48_000)
        XCTAssertEqual(r.title, "Tema MP3")
        XCTAssertEqual(r.artist, "Artista MP3")
    }

    func testFLACMetadataIfAVFoundationReadsIt() async throws {
        let m = await importer.metadata(of: fixture("sine1k_stereo_96k.flac"))
        // AVFoundation puede no leer los Vorbis comments de FLAC: entonces se deduce del nombre.
        if m.title == "Tema FLAC" {
            XCTAssertEqual(m.artist, "Artista FLAC")
        } else {
            XCTAssertEqual(m.title, "sine1k_stereo_96k")
            XCTAssertNil(m.artist)
            print("AudioKit: AVFoundation no lee los Vorbis comments de FLAC")
        }
    }

    func testMetadataFromFilename() async throws {
        let m = await importer.metadata(of: fixture("Artista Prueba - Tema Prueba.wav"))
        XCTAssertEqual(m.title, "Tema Prueba")
        XCTAssertEqual(m.artist, "Artista Prueba")
        let plain = await importer.metadata(of: fixture("sine1k_mono_48k_24bit.wav"))
        XCTAssertEqual(plain.title, "sine1k_mono_48k_24bit")
        XCTAssertNil(plain.artist)
    }

    // MARK: - Errores

    func assertFails(_ source: URL, rate: Double = 44_100, expecting expected: (AudioImportError) -> Bool,
                     file: StaticString = #filePath, line: UInt = #line) async {
        let dest = out("fail-\(UUID().uuidString).wav")
        do {
            _ = try await converting {
                try await importer.importAudio(from: source, to: dest, sampleRate: rate, progress: { _ in })
            }
            XCTFail("debía fallar", file: file, line: line)
        } catch let e as AudioImportError {
            XCTAssertTrue(expected(e), "error inesperado: \(e)", file: file, line: line)
        } catch {
            XCTFail("error no tipado: \(error)", file: file, line: line)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path), file: file, line: line)
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: tmpDir.path)) ?? []
        XCTAssertTrue(leftovers.allSatisfy { !$0.hasSuffix(".tmp.wav") }, "temporal sin limpiar", file: file, line: line)
    }

    func testUnsupportedExtension() async throws {
        let ogg = out("song.ogg")
        try Data([1, 2, 3]).write(to: ogg)
        await assertFails(ogg) { if case .unsupportedFormat = $0 { true } else { false } }
    }

    func testCorruptFile() async {
        await assertFails(fixture("corrupt.wav")) { if case .unreadable = $0 { true } else { false } }
    }

    func testEmptyFile() async {
        await assertFails(fixture("empty.wav")) { $0 == .emptyAudio }
    }

    func testUnsupportedSampleRate() async {
        await assertFails(fixture("sine1k_stereo_44k.mp3"), rate: 22_050) { $0 == .unsupportedSampleRate(22_050) }
    }
}

#if canImport(AVFoundation)
/// Los mismos casos con la conversión de Windows forzada en el Mac (parte 7.1). La decodificación sigue siendo la
/// de AVAudioFile; remuestreo (r8brain) y escritura (`AudioFileWriter`) son los de Windows.
final class AudioImporterPortableTests: AudioImporterTests {
    override class var portable: Bool { true }

    /// Punto fino: la muestra 0 no se mueve. Clic en el instante t0 fuera de las dos rejillas: el pico (parabólico)
    /// cae en t0 · destino ± 0,05 muestras con r8brain, igual que con AVAudioConverter.
    func testClickInstantMatchesAVAudioConverter() async throws {
        for (from, to) in [(48_000.0, 44_100.0), (44_100.0, 48_000.0), (96_000.0, 44_100.0)] {
            // Pulso gaussiano (σ = 0,2 ms) en t0 = 0,7 s + 0,37 muestras de destino.
            let t0 = 0.7 + 0.37 / to, sigma = 0.0002
            let x = (0..<Int(from)).map { i -> Float in
                let t = Double(i) / from - t0
                return Float(0.8 * exp(-t * t / (2 * sigma * sigma)))
            }
            let src = out("click-\(Int(from)).wav")
            try AudioFileWriter(url: src, sampleRate: from, channelCount: 1, format: .float32).write([x])
            var found: [Double] = []
            for portable in [false, true] {
                let dest = out("click-\(Int(from))-\(Int(to))-\(portable).wav")
                try await AudioImporter.$forcePortable.withValue(portable) {
                    _ = try await importer.importAudio(from: src, to: dest, sampleRate: to, progress: { _ in })
                }
                let y = try samples(dest)
                let k = y.indices.max { y[$0] < y[$1] }!
                var num = 0.0, den = 0.0
                for i in (k - 30)...(k + 30) { num += Double(i) * Double(y[i]); den += Double(y[i]) }
                found.append(num / den - t0 * to)
            }
            print(String(format: "importar clic %.0f → %.0f: AVAudioConverter %+.1e, r8brain %+.1e muestras", from, to, found[0], found[1]))
            XCTAssertEqual(found[1], 0, accuracy: 0.05)
            XCTAssertEqual(found[1], found[0], accuracy: 0.05)
        }
    }
}
#endif
