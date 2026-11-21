import CMiniz
import Foundation
@testable import NativeAudioFile
@testable import NativePlatform
import XCTest

// Fixtures copiados de Packages/AudioKit/Tests/AudioKitTests/Fixtures (seno de 1 kHz; corrupt.wav es ruido).
final class AudioFileTests: XCTestCase {
    func fixture(_ name: String) -> URL { Bundle.module.url(forResource: "Fixtures/" + name, withExtension: nil)! }

    /// Referencias de AVAudioFile medidas en P8 (`Probes/P8-windows/mac-ref/decref.swift`): fotogramas,
    /// Hz, canales, RMS del canal 0 (6 decimales) y primera muestra > 0,01.
    static let references: [(file: String, frames: Int, rate: Double, channels: Int, rms: Double, first: Int)] = [
        ("sine1k_mono_48k_24bit.wav", 72_000, 48_000, 1, 0.088368, 1),
        ("sine1k_stereo_44k.mp3", 66_150, 44_100, 2, 0.059359, 1),
        ("sine1k_stereo_96k.flac", 144_000, 96_000, 2, 0.062486, 2),
    ]
    /// RMS impreso con 6 decimales: medio dígito más la diferencia de decodificador de MP3 (P8: ≤ 4e-6 rel.).
    static let rmsTolerance = 1e-5
    /// Muestra a muestra frente a AVAudioFile: WAV y FLAC son enteros escalados por 2^-(b-1), idénticos;
    /// MP3 cambia de decodificador (dr_mp3 frente a Core Audio), se acota su diferencia máxima.
    static let mp3SampleTolerance: Float = 1e-3

    func testPortableDecoderMatchesAVAudioFileReference() throws {
        for ref in Self.references {
            let a = try NativeAudioFile.read(fixture(ref.file), backend: .portable)
            let ch0 = a.channels[0]
            let rms = (ch0.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(ch0.count)).squareRoot()
            let first = ch0.firstIndex { abs($0) > 0.01 } ?? -1
            print("\(ref.file): \(a.frameCount) fotogramas, \(a.sampleRate) Hz, \(a.channelCount) ch, RMS \(rms), primera \(first)")
            XCTAssertEqual(a.frameCount, ref.frames, ref.file)
            XCTAssertEqual(a.sampleRate, ref.rate, ref.file)
            XCTAssertEqual(a.channelCount, ref.channels, ref.file)
            XCTAssertEqual(rms, ref.rms, accuracy: Self.rmsTolerance, ref.file)
            XCTAssertEqual(first, ref.first, ref.file)
        }
    }

    #if canImport(AVFoundation)
    func testPortableDecoderMatchesAVAudioFileSampleBySample() throws {
        for ref in Self.references {
            let av = try NativeAudioFile.read(fixture(ref.file), backend: .system)
            let dr = try NativeAudioFile.read(fixture(ref.file), backend: .portable)
            XCTAssertEqual(dr.frameCount, av.frameCount, ref.file)
            XCTAssertEqual(dr.channelCount, av.channelCount, ref.file)
            var maxDiff: Float = 0
            for c in 0..<min(av.channelCount, dr.channelCount) {
                for i in 0..<min(av.frameCount, dr.frameCount) { maxDiff = max(maxDiff, abs(av.channels[c][i] - dr.channels[c][i])) }
            }
            print("\(ref.file): Δ máx dr_* vs AVAudioFile = \(maxDiff)")
            XCTAssertLessThanOrEqual(maxDiff, ref.file.hasSuffix(".mp3") ? Self.mp3SampleTolerance : 0, ref.file)
        }
    }

    /// El escritor portátil cuantiza como Core Audio: mismas muestras releídas en 16, 24 y 32 bits.
    func testPortableWriterMatchesAVAudioFileWriter() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nativekit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let left = noise(5000, seed: 41, scale: 1.1), right = noise(5000, seed: 42, scale: 0.3)
        for format in [WAVSampleFormat.int16, .int24, .float32] {
            let a = dir.appendingPathComponent("av-\(format.bits).wav"), p = dir.appendingPathComponent("dr-\(format.bits).wav")
            for (url, backend) in [(a, AudioBackend.system), (p, .portable)] {
                let w = try AudioFileWriter(url: url, sampleRate: 48_000, channelCount: 2, format: format, backend: backend)
                try w.write([left, right])
                try w.close()
            }
            let ra = try NativeAudioFile.read(a, backend: .system), rp = try NativeAudioFile.read(p, backend: .system)
            XCTAssertEqual(ra, rp, "\(format)")
        }
    }
    #endif

    /// Escribir y releer con el motor del sistema, en una ruta no ASCII.
    func testWriteReadRoundTripNonASCIIPath() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nativekit-ñandú-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let x = noise(3000, seed: 43, scale: 0.9)
        for format in [WAVSampleFormat.int16, .int24, .float32] {
            let url = dir.appendingPathComponent("toma ñ \(format.bits).wav")
            try NativeAudioFile.write(url, channels: [x], sampleRate: 44_100, format: format)
            let r = try NativeAudioFile.read(url)
            XCTAssertEqual(r.sampleRate, 44_100)
            XCTAssertEqual(r.frameCount, x.count)
            let scale: Float = format == .int16 ? 32768 : 8_388_608
            for i in x.indices {
                let expected = format == .float32 ? x[i] : (x[i] * scale).rounded() / scale
                XCTAssertEqual(r.channels[0][i], expected, "\(format) muestra \(i)")
                if r.channels[0][i] != expected { break }
            }
        }
    }

    func testReaderSeekAndBlocks() throws {
        let url = fixture("sine1k_stereo_96k.flac")
        let whole = try NativeAudioFile.read(url)
        let r = try AudioFileReader(url: url)
        try r.seek(toFrame: 50_000)
        let block = try r.read(maxFrames: 1000)
        XCTAssertEqual(block[1], Array(whole.channels[1][50_000..<51_000]))
        XCTAssertEqual(r.framePosition, 51_000)
        let mono = try NativeAudioFile.readMono(url)
        XCTAssertEqual(mono.samples[100], (whole.channels[0][100] * 0.5 + whole.channels[1][100] * 0.5), accuracy: 1e-7)
    }

    func testCorruptFileThrows() {
        XCTAssertThrowsError(try NativeAudioFile.read(fixture("corrupt.wav")))
        XCTAssertThrowsError(try NativeAudioFile.read(fixture("corrupt.wav"), backend: .portable))
    }
}

final class ChildProcessTests: XCTestCase {
    /// Un hijo con un nieto: terminar el árbol deja 0 procesos vivos en ≤ 5 s. En el Mac el hijo y el nieto
    /// ignoran SIGTERM, así que hace falta el SIGKILL al grupo pasado el margen.
    func testTerminateKillsGrandchildren() throws {
        #if os(Windows)
        let child = ChildProcess(executableURL: URL(fileURLWithPath: "C:\\Windows\\System32\\cmd.exe"),
                                 arguments: ["/c", "ping -n 60 127.0.0.1 >nul"])
        let expectedAtLeast = 2   // cmd + ping
        #else
        let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent("nativekit-\(UUID().uuidString).pid")
        defer { try? FileManager.default.removeItem(at: pidFile) }
        let child = ChildProcess(executableURL: URL(fileURLWithPath: "/bin/sh"),
                                 arguments: ["-c", "trap '' TERM; sleep 60 & echo $! > '\(pidFile.path)'; wait; wait"])
        let expectedAtLeast = 1
        #endif
        child.process.standardOutput = FileHandle.nullDevice
        try child.run()
        #if canImport(Darwin)
        let t = Date()
        while (try? String(contentsOf: pidFile, encoding: .utf8))?.hasSuffix("\n") != true, Date().timeIntervalSince(t) < 5 {
            Thread.sleep(forTimeInterval: 0.02)
        }
        #endif
        let start = Date()
        while child.activeProcessCount < expectedAtLeast, Date().timeIntervalSince(start) < 5 { Thread.sleep(forTimeInterval: 0.05) }
        XCTAssertGreaterThanOrEqual(child.activeProcessCount, expectedAtLeast)
        child.terminate(grace: 0.3)
        let t0 = Date()
        while child.activeProcessCount > 0, Date().timeIntervalSince(t0) < 5 { Thread.sleep(forTimeInterval: 0.05) }
        print("árbol terminado en \(Date().timeIntervalSince(t0)) s")
        XCTAssertEqual(child.activeProcessCount, 0)
        #if canImport(Darwin)
        // El nieto (sleep) también: su pid lo escribe el hijo en un fichero.
        let pidText = try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let grandchild = try XCTUnwrap(Int32(pidText))
        XCTAssertNotEqual(Darwin.kill(grandchild, 0), 0, "el nieto \(grandchild) sigue vivo")
        #endif
        child.waitUntilExit()
        XCTAssertFalse(child.isRunning)
    }
}

final class MinizTests: XCTestCase {
    func payload() -> [UInt8] {
        let text = Array("{\"tracks\":[{\"name\":\"Guitarra\",\"notes\":[1,2,3,4,5,6]}]}".utf8)
        var g = LCG(s: 5)
        return (0..<200).flatMap { _ in text + [UInt8(truncatingIfNeeded: Int(g.next() * 1000))] }
    }

    func inflateRaw(_ data: [UInt8]) -> [UInt8]? {
        var outLen = 0
        guard let p = data.withUnsafeBytes({ tinfl_decompress_mem_to_heap($0.baseAddress, $0.count, &outLen, 0) }) else { return nil }
        defer { mz_free(p) }
        return Array(UnsafeRawBufferPointer(start: p, count: outLen))
    }

    /// Deflate crudo de miniz → inflado con miniz.
    func testRawDeflateRoundTrip() throws {
        let src = payload()
        var len = 0
        let p = try XCTUnwrap(src.withUnsafeBytes { tdefl_compress_mem_to_heap($0.baseAddress, $0.count, &len, 128) })
        let packed = Array(UnsafeRawBufferPointer(start: p, count: len))
        mz_free(p)
        XCTAssertLessThan(packed.count, src.count)
        XCTAssertEqual(inflateRaw(packed), src)
    }

    #if canImport(Compression)
    /// Lo que hace hoy SourceKit (`NSData.decompressed(using: .zlib)`, deflate crudo): miniz infla lo que
    /// comprime el framework Compression.
    func testInflatesAppleZlib() throws {
        let src = payload()
        let packed = try (Data(src) as NSData).compressed(using: .zlib) as Data
        XCTAssertEqual(inflateRaw([UInt8](packed)), src)
    }
    #endif
}
