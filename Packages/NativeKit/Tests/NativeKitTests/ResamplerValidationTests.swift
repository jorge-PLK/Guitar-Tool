import Foundation
import NativeResample
import XCTest
#if canImport(AVFoundation)
import AVFoundation
#endif

/// Parte 7.1 (plan, «Corte del paso 7»): r8brain (`Resampler`) frente a `AVAudioConverter` calidad Mastering, que
/// es el conversor del Mac, en los pares de frecuencias que usa la app: `AudioImporter` y `TakeResampling`
/// (cualquier origen → 44,1 / 48 kHz) y `MonoResampler` de StudyKit (44,1 / 48 / 96 kHz → 22,05 kHz).
///
/// Criterio: alineado absoluto 0 ± 0,05 muestras de salida (el de `BeatTests.testResamplerKeepsPulseTime`);
/// banda de paso y rechazo de alias no peores que los de AVAudioConverter (con margen de 0,01 dB y 3 dB); longitud
/// exacta round(n · destino / origen). En Windows corre solo la parte absoluta (no hay AVAudioConverter).
final class ResamplerValidationTests: XCTestCase {
    /// Pares (origen, destino) de la app.
    static let pairs: [(Double, Double)] = [
        (48_000, 44_100), (44_100, 48_000), (96_000, 48_000), (96_000, 44_100), (88_200, 44_100),
        (22_050, 44_100), (32_000, 48_000),
        (44_100, 22_050), (48_000, 22_050), (96_000, 22_050),
    ]
    /// Tolerancia del centroide, en muestras de salida (`BeatTests.testResamplerKeepsPulseTime`).
    static let alignTolerance = 0.05
    /// Margen frente a AVAudioConverter.
    static let passbandMarginDB = 0.01
    static let aliasMarginDB = 3.0

    typealias Engine = @Sendable (_ x: [Float], _ from: Double, _ to: Double) throws -> [Float]

    static let r8brain: Engine = { x, from, to in try Resampler.resample(x, from: from, to: to) }

    // MARK: medidas

    /// Desvío del centroide de un pulso gaussiano (σ = 0,2 ms, banda < 3 kHz a −60 dB) puesto en `t0` fuera de la
    /// rejilla de salida, en muestras de salida, para varias fracciones.
    static func alignment(_ engine: Engine, from: Double, to: Double) throws -> Double {
        var worst = 0.0
        for frac in [0.0, 0.37, 0.5, 0.81] {
            let n = Int(from * 1.0), t0 = 0.5 + frac / to, sigma = 0.0002
            let x = (0..<n).map { i -> Float in
                let t = Double(i) / from - t0
                return Float(0.8 * exp(-t * t / (2 * sigma * sigma)))
            }
            let y = try engine(x, from, to)
            let k = y.indices.max { y[$0] < y[$1] }!
            let half = Int((to * 0.0015).rounded())    // ±1,5 ms = ±7,5 σ
            var num = 0.0, den = 0.0
            for i in (k - half)...(k + half) { num += Double(i) * Double(y[i]); den += Double(y[i]) }
            let off = num / den - t0 * to
            if abs(off) > abs(worst) { worst = off }
        }
        return worst
    }

    /// Amplitud de la componente `f` (Hz) en `y` a `rate`, con ventana de Hann sobre el tramo central (sin bordes).
    static func amplitude(_ y: [Float], rate: Double, f: Double) -> Double {
        let start = y.count / 4, len = y.count / 2
        var re = 0.0, im = 0.0, wsum = 0.0
        let w0 = 2 * Double.pi * f / rate
        for i in 0..<len {
            let w = 0.5 - 0.5 * cos(2 * Double.pi * Double(i) / Double(len - 1))
            let v = Double(y[start + i]) * w
            let ph = w0 * Double(start + i)
            re += v * cos(ph); im -= v * sin(ph)
            wsum += w
        }
        return 2 * (re * re + im * im).squareRoot() / wsum
    }

    static func tone(_ f: Double, rate: Double, seconds: Double = 1, amp: Double = 0.5) -> [Float] {
        (0..<Int(rate * seconds)).map { Float(amp * sin(2 * Double.pi * f * Double($0) / rate)) }
    }

    /// Máxima desviación de ganancia (dB) en tonos de 100 Hz a 0,9 · Nyquist de la salida (y de la entrada).
    static func passband(_ engine: Engine, from: Double, to: Double) throws -> Double {
        let nyq = min(from, to) / 2
        var worst = 0.0
        for f in [100.0, 1_000, 5_000, 0.5 * nyq, 0.8 * nyq, 0.9 * nyq] {
            let y = try engine(tone(f, rate: from), from, to)
            let db = 20 * log10(amplitude(y, rate: to, f: f) / 0.5)
            if abs(db) > abs(worst) { worst = db }
        }
        return worst
    }

    /// Rechazo (dB, positivo) del alias de tonos por encima de la Nyquist de la salida (bajada), o de la imagen por
    /// encima de la Nyquist de la entrada (subida). El peor de 1,05 · y 1,3 · Nyquist.
    static func aliasRejection(_ engine: Engine, from: Double, to: Double) throws -> Double {
        var worst = Double.infinity
        if to < from {
            for k in [1.05, 1.3] {
                let f = k * to / 2
                guard f < from / 2 else { continue }
                let y = try engine(tone(f, rate: from), from, to)
                let alias = to - f
                worst = min(worst, -20 * log10(max(amplitude(y, rate: to, f: alias), 1e-12) / 0.5))
            }
        } else {
            // Imagen entre la Nyquist de la entrada y la de la salida, cerca de la primera y en medio.
            for k in [0.05, 0.5] {
                let image = from / 2 + k * (to / 2 - from / 2)
                let f = from - image
                let y = try engine(tone(f, rate: from), from, to)
                worst = min(worst, -20 * log10(max(amplitude(y, rate: to, f: image), 1e-12) / 0.5))
            }
        }
        return worst
    }

    // MARK: pruebas

    /// Lo que no necesita AVAudioConverter (también en Windows): alineado, longitud y banda de paso absolutos.
    func testR8brainAbsoluteOnAppPairs() throws {
        for (from, to) in Self.pairs {
            let n = 12_345
            let y = try Resampler.resample([Float](repeating: 0.1, count: n), from: from, to: to)
            XCTAssertEqual(y.count, Int((Double(n) * to / from).rounded()), "\(from) → \(to)")
            let off = try Self.alignment(Self.r8brain, from: from, to: to)
            XCTAssertEqual(off, 0, accuracy: Self.alignTolerance, "\(from) → \(to)")
            let pb = try Self.passband(Self.r8brain, from: from, to: to)
            XCTAssertEqual(pb, 0, accuracy: 0.01, "\(from) → \(to)")
            let ar = try Self.aliasRejection(Self.r8brain, from: from, to: to)
            XCTAssertGreaterThan(ar, 100, "\(from) → \(to)")
        }
    }

    /// Por bloques (como `AudioImporter` en Windows) sale lo mismo que de una vez, y el tiempo de 60 s estéreo
    /// 44,1 → 48 kHz queda impreso (informativo; en Debug el C++ va sin optimizar).
    func testStreamMatchesOfflineAndTiming() throws {
        let n = 44_100 * 60
        let l = (0..<n).map { Float(0.3 * sin(Double($0) * 0.0123)) }, r = l.map { -$0 }
        let t = Date()
        let whole = try Resampler.resample(channels: [l, r], from: 44_100, to: 48_000)
        let secs = Date().timeIntervalSince(t)
        let stream = try StreamResampler(from: 44_100, to: 48_000, channels: 2)
        var got: [[Float]] = [[], []]
        var pos = 0
        while pos < n {
            let m = min(16_384, n - pos)
            let o = stream.process([Array(l[pos..<(pos + m)]), Array(r[pos..<(pos + m)])])
            got[0] += o[0]; got[1] += o[1]
            pos += m
        }
        let tail = stream.flush()
        got[0] += tail[0]; got[1] += tail[1]
        print(String(format: "r8brain 60 s estéreo 44,1 → 48 kHz: %.2f s", secs))
        XCTAssertEqual(got[0].count, Int((Double(n) * 48_000 / 44_100).rounded()))
        XCTAssertEqual(got, whole)
    }

    #if canImport(AVFoundation)
    /// Mismo bucle que `MonoResampler` y `AudioImporter` en el Mac: Mastering, calidad máxima.
    static let avConverter: Engine = { x, from, to in
        let inFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: from, channels: 1, interleaved: false)!
        let outFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: to, channels: 1, interleaved: false)!
        let converter = AVAudioConverter(from: inFmt, to: outFmt)!
        converter.sampleRateConverterAlgorithm = AVSampleRateConverterAlgorithm_Mastering
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        let block = 1 << 15
        let inBuf = AVAudioPCMBuffer(pcmFormat: inFmt, frameCapacity: AVAudioFrameCount(block))!
        let outBuf = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: AVAudioFrameCount(block))!
        let feeder = Feeder(x)
        var out = [Float]()
        while true {
            outBuf.frameLength = 0
            var err: NSError?
            let status = converter.convert(to: outBuf, error: &err) { want, st in
                let n = min(Int(want), block, feeder.x.count - feeder.pos)
                guard n > 0 else { st.pointee = .endOfStream; return nil }
                feeder.x.withUnsafeBufferPointer { inBuf.floatChannelData![0].update(from: $0.baseAddress! + feeder.pos, count: n) }
                inBuf.frameLength = AVAudioFrameCount(n)
                feeder.pos += n
                st.pointee = .haveData
                return inBuf
            }
            if status == .error { throw err ?? NSError(domain: "av", code: 1) }
            let got = Int(outBuf.frameLength)
            if got > 0 { out.append(contentsOf: UnsafeBufferPointer(start: outBuf.floatChannelData![0], count: got)) }
            if status == .endOfStream || (status == .inputRanDry && got == 0) { break }
        }
        return out
    }

    final class Feeder: @unchecked Sendable {
        let x: [Float]
        var pos = 0
        init(_ x: [Float]) { self.x = x }
    }

    /// La tabla del informe: r8brain frente a AVAudioConverter en cada par de la app.
    func testR8brainVersusAVAudioConverter() throws {
        print("par | desfase r8b / AV (muestras) | banda de paso r8b / AV (dB) | alias r8b / AV (dB) | longitud r8b / AV (n = 12345)")
        for (from, to) in Self.pairs {
            let ones = [Float](repeating: 0.1, count: 12_345)
            let lenR = try Self.r8brain(ones, from, to).count, lenA = try Self.avConverter(ones, from, to).count
            let offR = try Self.alignment(Self.r8brain, from: from, to: to)
            let offA = try Self.alignment(Self.avConverter, from: from, to: to)
            let pbR = try Self.passband(Self.r8brain, from: from, to: to)
            let pbA = try Self.passband(Self.avConverter, from: from, to: to)
            let arR = try Self.aliasRejection(Self.r8brain, from: from, to: to)
            let arA = try Self.aliasRejection(Self.avConverter, from: from, to: to)
            print(String(format: "%.0f → %.0f | %+.1e / %+.1e | %+.1e / %+.1e | %.1f / %.1f | %d / %d",
                         from, to, offR, offA, pbR, pbA, arR, arA, lenR, lenA))
            XCTAssertEqual(offR, 0, accuracy: Self.alignTolerance, "\(from) → \(to)")
            XCTAssertLessThanOrEqual(abs(pbR), abs(pbA) + Self.passbandMarginDB, "\(from) → \(to)")
            XCTAssertGreaterThanOrEqual(arR, min(arA, 140) - Self.aliasMarginDB, "\(from) → \(to)")
        }
    }

    /// Las dos salidas, sobre ruido de banda limitada (200 senos de fase aleatoria hasta 0,9 · la Nyquist menor, para
    /// no medir la diferencia de banda de transición), coinciden en tiempo: desfase entero 0 por correlación y
    /// fracción por interpolación parabólica.
    func testR8brainAndAVAudioConverterLineUpOnNoise() throws {
        var g = SystemRandomNumberGenerator()
        for (from, to) in Self.pairs {
            let top = 0.9 * min(from, to) / 2
            let comps = (0..<200).map { _ in (Double.random(in: 20...top, using: &g), Double.random(in: 0...(2 * Double.pi), using: &g)) }
            let x = (0..<Int(from)).map { i -> Float in
                var s = 0.0
                for (f, ph) in comps { s += sin(2 * Double.pi * f * Double(i) / from + ph) }
                return Float(0.02 * s)
            }
            let a = try Self.r8brain(x, from, to), b = try Self.avConverter(x, from, to)
            let lo = Int(to * 0.1), hi = Int(to * 0.9)
            var corr = [Double]()
            for lag in -4...4 {
                var s = 0.0
                for i in lo..<hi { s += Double(a[i + lag]) * Double(b[i]) }
                corr.append(s)
            }
            let k = corr.indices.max { corr[$0] < corr[$1] }!
            var frac = 0.0
            if k > 0 && k < corr.count - 1 {
                let (l, c, r) = (corr[k - 1], corr[k], corr[k + 1])
                frac = 0.5 * (l - r) / (l - 2 * c + r)
            }
            let lag = Double(k - 4) + frac
            var err = 0.0, pow = 0.0
            for i in lo..<hi { err += Double((a[i] - b[i]) * (a[i] - b[i])); pow += Double(b[i] * b[i]) }
            print(String(format: "ruido %.0f → %.0f: desfase r8b − AV %+.1e muestras, diferencia %.1f dB", from, to, lag, 10 * log10(err / pow)))
            XCTAssertEqual(k - 4, 0, "\(from) → \(to)")
            XCTAssertEqual(lag, 0, accuracy: Self.alignTolerance, "\(from) → \(to)")
        }
    }
    #endif
}
