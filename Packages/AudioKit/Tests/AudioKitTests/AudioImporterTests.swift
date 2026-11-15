import Accelerate
import AVFoundation
import XCTest
@testable import AudioKit

final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []
    func add(_ v: Double) { lock.lock(); values.append(v); lock.unlock() }
    var all: [Double] { lock.lock(); defer { lock.unlock() }; return values }
}

final class AudioImporterTests: XCTestCase {
    let importer = AudioImporter()
    var tmpDir: URL!

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
        let r = try await importer.importAudio(from: fixture(name), to: dest, sampleRate: rate, progress: progress)
        return (r, dest)
    }

    /// Lee el canal `ch` entero.
    func samples(_ url: URL, channel ch: Int = 0) throws -> [Float] {
        let f = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length))!
        try f.read(into: buf)
        return Array(UnsafeBufferPointer(start: buf.floatChannelData![ch], count: Int(buf.frameLength)))
    }

    /// Frecuencia del pico de FFT (ventana Hann de 16384 muestras del centro) y ancho de bin.
    func peak(_ x: [Float], rate: Double) -> (freq: Double, bin: Double) {
        let n = 16_384
        let start = (x.count - n) / 2
        var win = [Float](repeating: 0, count: n)
        vDSP_hann_window(&win, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        var seg = [Float](repeating: 0, count: n)
        vDSP_vmul(Array(x[start..<start + n]), 1, win, 1, &seg, 1, vDSP_Length(n))
        let log2n = vDSP_Length(14)
        let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        defer { vDSP_destroy_fftsetup(setup) }
        var re = [Float](repeating: 0, count: n / 2)
        var im = [Float](repeating: 0, count: n / 2)
        var mags = [Float](repeating: 0, count: n / 2)
        re.withUnsafeMutableBufferPointer { rp in
            im.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                seg.withUnsafeBufferPointer { sp in
                    sp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &mags, 1, vDSP_Length(n / 2))
            }
        }
        mags[0] = 0
        var maxV: Float = 0
        var maxI: vDSP_Length = 0
        vDSP_maxvi(mags, 1, &maxV, &maxI, vDSP_Length(n / 2))
        let bin = rate / Double(n)
        return (Double(maxI) * bin, bin)
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
                let f = try AVAudioFile(forReading: dest)
                XCTAssertEqual(f.fileFormat.channelCount, 2, "\(name) @\(rate)")
                XCTAssertEqual(f.fileFormat.sampleRate, rate, "\(name) @\(rate)")
                XCTAssertEqual(f.fileFormat.commonFormat, .pcmFormatFloat32, "\(name) @\(rate)")
                XCTAssertEqual(f.fileFormat.settings[AVLinearPCMBitDepthKey] as? Int, 32)
                XCTAssertEqual(dest.pathExtension, "wav")
            }
        }
    }

    func testDurationPreserved() async throws {
        for name in tonal {
            for rate in rates {
                let (r, dest) = try await importFile(name, rate: rate)
                let f = try AVAudioFile(forReading: dest)
                let dur = Double(f.length) / rate
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
        try await importer.resample(a, to: up, sampleRate: 48_000)
        try await importer.resample(up, to: back, sampleRate: 44_100)
        let fa = try AVAudioFile(forReading: a), fu = try AVAudioFile(forReading: up), fb = try AVAudioFile(forReading: back)
        XCTAssertEqual(fu.fileFormat.sampleRate, 48_000)
        XCTAssertEqual(fb.fileFormat.sampleRate, 44_100)
        XCTAssertEqual(Double(fb.length) / 44_100, Double(fa.length) / 44_100, accuracy: 0.001)
        XCTAssertEqual(Double(fu.length) / 48_000, Double(fa.length) / 44_100, accuracy: 0.001)
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
            _ = try await importer.importAudio(from: source, to: dest, sampleRate: rate, progress: { _ in })
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
