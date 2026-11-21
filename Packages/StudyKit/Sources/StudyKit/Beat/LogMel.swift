import NativeDSP
import Foundation

/// Constantes del contrato BeatKit (mini-spec Fase 2 §1 StudyKit, `docs/probes/P4-modelos.md` «Pulso (Beat This!)»).
enum BeatContract {
    /// Frecuencia de trabajo del preproceso.
    static let sampleRate: Double = 22_050
    static let nFFT = 1024
    static let hop = 441
    /// Tramas por segundo de las salidas del modelo (22 050 / 441).
    static let fps: Double = 50
    static let nMels = 128
    static let fMin: Double = 30
    static let fMax: Double = 11_000
    /// Corrección de P0: el código oficial divide el módulo por sqrt(n_fft) (= 32), no por sqrt(Σ win²).
    static let magnitudeScale: Float = 1 / 32
    /// log1p(1000 · mel).
    static let logMultiplier: Float = 1000
    /// Troceado: 1500 tramas (30 s) con borde de 6.
    static let chunk = 1500
    static let border = 6
    static var bins: Int { nFFT / 2 + 1 }
}

/// Log-mel de Beat This! (`LogMelSpect` de torchaudio): STFT 1024 hop 441 Hann periódica centrada con `reflect`,
/// |X| / 32, banco mel Slaney de 128 bandas 30–11 000 Hz sin normalizar, log1p(1000 · x).
final class BeatLogMel: @unchecked Sendable {
    static let shared = BeatLogMel()

    /// Banco mel [513 × 128] row-major (fila = bin de la STFT), calculado en doble y guardado en Float.
    let melBank: [Float]
    private let window: [Float]
    private let dft: DSP.RealDFT

    init() {
        melBank = Self.slaneyMelBank().map(Float.init)
        let n = BeatContract.nFFT
        window = (0..<n).map { Float(0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(n))) }
        dft = DSP.RealDFT(count: n, direction: .forward)!
    }

    /// Tramas que salen de `sampleCount` muestras (STFT centrada): 1 + n / hop.
    static func frameCount(sampleCount: Int) -> Int { 1 + sampleCount / BeatContract.hop }

    // MARK: banco mel

    static func hzToMelSlaney(_ f: Double) -> Double {
        let fSp = 200.0 / 3, minLogHz = 1000.0, minLogMel = minLogHz / fSp, logStep = log(6.4) / 27
        return f >= minLogHz ? minLogMel + log(f / minLogHz) / logStep : f / fSp
    }

    static func melToHzSlaney(_ m: Double) -> Double {
        let fSp = 200.0 / 3, minLogHz = 1000.0, minLogMel = minLogHz / fSp, logStep = log(6.4) / 27
        return m >= minLogMel ? minLogHz * exp(logStep * (m - minLogMel)) : m * fSp
    }

    /// Igual que `torchaudio.functional.melscale_fbanks(mel_scale="slaney", norm=None)` y
    /// `librosa.filters.mel(htk=False, norm=None)`: triángulos con vértices equiespaciados en mel.
    static func slaneyMelBank() -> [Double] {
        let bins = BeatContract.bins, nMels = BeatContract.nMels
        let mMin = hzToMelSlaney(BeatContract.fMin), mMax = hzToMelSlaney(BeatContract.fMax)
        let fPts = (0..<(nMels + 2)).map { melToHzSlaney(mMin + Double($0) * (mMax - mMin) / Double(nMels + 1)) }
        var bank = [Double](repeating: 0, count: bins * nMels)
        for k in 0..<bins {
            let f = Double(k) * BeatContract.sampleRate / Double(BeatContract.nFFT)
            for m in 0..<nMels {
                let down = (f - fPts[m]) / (fPts[m + 1] - fPts[m])
                let up = (fPts[m + 2] - f) / (fPts[m + 2] - fPts[m + 1])
                bank[k * nMels + m] = max(0, min(down, up))
            }
        }
        return bank
    }

    // MARK: espectrograma

    /// Log-mel [T × 128] row-major de una señal mono a 22 050 Hz. Necesita más de n_fft/2 muestras (`reflect`).
    func compute(_ x: [Float]) throws -> (values: [Float], frames: Int) {
        let n = x.count, half = BeatContract.nFFT / 2
        guard n > half else { throw BeatError.audioTooShort(samples: n) }
        let frames = Self.frameCount(sampleCount: n)
        let bins = BeatContract.bins

        // Relleno reflect de 512 a cada lado (sin repetir el borde, como torch.stft(center=True, pad_mode="reflect")).
        var padded = [Float](repeating: 0, count: n + 2 * half)
        for i in 0..<half {
            padded[i] = x[half - i]
            padded[half + n + i] = x[n - 2 - i]
        }
        padded.withUnsafeMutableBufferPointer { p in
            x.withUnsafeBufferPointer { p.baseAddress!.advanced(by: half).update(from: $0.baseAddress!, count: n) }
        }

        var mags = [Float](repeating: 0, count: frames * bins)
        var frame = [Float](repeating: 0, count: BeatContract.nFFT)
        var inRe = [Float](repeating: 0, count: half), inIm = [Float](repeating: 0, count: half)
        var outRe = [Float](repeating: 0, count: half), outIm = [Float](repeating: 0, count: half)
        // RealDFT (zrop) devuelve 2·X[k]; el contrato pide |X| / 32.
        let scale = BeatContract.magnitudeScale / 2

        padded.withUnsafeBufferPointer { pad in
            mags.withUnsafeMutableBufferPointer { mag in
                for t in 0..<frames {
                    DSP.vmul(pad.baseAddress! + t * BeatContract.hop, 1, window, 1, &frame, 1, DSPLength(BeatContract.nFFT))
                    // Pares → parte real, impares → parte imaginaria (formato de entrada de zrop).
                    frame.withUnsafeBufferPointer { f in
                        f.baseAddress!.withMemoryRebound(to: InterleavedComplex.self, capacity: half) { c in
                            inRe.withUnsafeMutableBufferPointer { re in
                                inIm.withUnsafeMutableBufferPointer { im in
                                    var split = SplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                                    DSP.ctoz(c, 2, &split, 1, DSPLength(half))
                                }
                            }
                        }
                    }
                    dft.execute(inRe, inIm, &outRe, &outIm)
                    let row = mag.baseAddress! + t * bins
                    row[0] = abs(outRe[0]) * scale          // DC
                    row[half] = abs(outIm[0]) * scale       // Nyquist, empaquetado en Im[0]
                    outRe.withUnsafeMutableBufferPointer { re in
                        outIm.withUnsafeMutableBufferPointer { im in
                            re[0] = 0; im[0] = 0
                            var split = SplitComplex(realp: re.baseAddress! + 1, imagp: im.baseAddress! + 1)
                            DSP.zvabs(&split, 1, row + 1, 1, DSPLength(half - 1))
                        }
                    }
                    var s = scale
                    DSP.vsmul(row + 1, 1, &s, row + 1, 1, DSPLength(half - 1))
                }
            }
        }

        // mel = |X| · banco ([T × 513] · [513 × 128]), luego log1p(1000 · mel).
        let nMels = BeatContract.nMels
        var mel = [Float](repeating: 0, count: frames * nMels)
        DSP.mmul(mags, 1, melBank, 1, &mel, 1, DSPLength(frames), DSPLength(nMels), DSPLength(bins))
        var mult = BeatContract.logMultiplier
        DSP.vsmul(mel, 1, &mult, &mel, 1, DSPLength(mel.count))
        var count = Int32(mel.count)
        mel.withUnsafeMutableBufferPointer { DSP.vvlog1pf($0.baseAddress!, $0.baseAddress!, &count) }
        return (mel, frames)
    }
}

public enum BeatError: Error, Equatable, Sendable {
    case audioTooShort(samples: Int)
    case unreadableAudio(String)
    case model(String)
}
