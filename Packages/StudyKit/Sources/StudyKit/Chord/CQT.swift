import NativeDSP
import Foundation

/// Contrato ChordKit de P4 (mini-spec Fase 2 §1 `ChordRecognizer`; `docs/probes/P4-modelos.md` «Acordes (BTC)»;
/// README de `Tests/StudyKitTests/Fixtures`).
enum ChordContract {
    static let sampleRate = 22_050.0
    static let hop = 2048
    static let nBins = 144
    static let binsPerOctave = 24
    /// `mp3.inst_len` de BTC: la CQT se calcula por trozos de 10 s (220 500 muestras) concatenados.
    static let chunkSamples = 220_500
    /// `model.timestep`: tramas por ventana del modelo (sin solape; la última se rellena con ceros).
    static let windowFrames = 108
    static let nChords = 170
    /// 10 s / 108 tramas (lo que `test.py` de BTC llama `feature_per_second`).
    static let frameDuration = 10.0 / 108.0
    /// mean/std del checkpoint `btc_model_large_voca.pt` (README de Fixtures, `chord_ref.json`).
    static let featureMean: Float = -2.2279878897355596
    static let featureStd: Float = 1.7191329394436938
    /// log(|CQT| + 1e-6) (`audio_file_to_features` de BTC).
    static let logEpsilon: Float = 1e-6
}

/// Port de `librosa.cqt` 1.0.1 con sus valores por defecto (fmin C1, tuning 0, filter_scale 1, norm 1,
/// sparsity 0,01, ventana Hann, scale True, relleno con ceros) salvo hop, número de bins y bins por octava.
///
/// Igual que librosa: bases complejas en el dominio de la frecuencia por octava (FFT del filtro Hann centrado,
/// recortadas al 1 % de magnitud acumulada), STFT con ventana rectangular centrada, una diezmación temprana y
/// otra por octava (`resample(…, scale=True)` = × √2), compensación √(sr / sr_octava) en la base y división
/// final por √longitud. Lo único que no es copia literal es el filtro de diezmación: librosa usa soxr HQ
/// (FIR Kaiser de fase lineal, ~126 dB); aquí un FIR Kaiser equivalente con NativeDSP. Todas las bases quedan por
/// debajo del 40 % del Nyquist de su octava, donde ambos filtros son planos.
final class LibrosaCQT: @unchecked Sendable {
    static let shared = LibrosaCQT()

    /// Fila dispersa de la base: bins FFT `k` (0…nfft/2) con su valor complejo.
    struct Row {
        let k: [Int]
        let re: [Float]
        let im: [Float]
    }

    struct Octave {
        /// Primer bin CQT de la octava; la octava cubre `firstBin ..< firstBin + rows.count`.
        let firstBin: Int
        let nfft: Int
        let hop: Int
        let rows: [Row]
        /// Diezmar ×2 la señal después de esta octava.
        let halveAfter: Bool
        let dft: DSP.ComplexDFT
    }

    let nBins: Int
    let earlyDownsamples: Int
    let octaves: [Octave]
    /// 1/√longitud de cada filtro a la frecuencia de muestreo tras la diezmación temprana (`V /= sqrt(lengths)`).
    let lengthScale: [Float]
    let halfband: [Float]

    /// `Hann` en `librosa.filters.WINDOW_BANDWIDTHS`.
    static let hannBandwidth = 1.50018310546875
    /// `librosa.cqt(sparsity=0.01)`.
    static let sparsity: Float = 0.01

    init(sampleRate sr0: Double = ChordContract.sampleRate, hop hop0: Int = ChordContract.hop,
         nBins: Int = ChordContract.nBins, binsPerOctave bpo: Int = ChordContract.binsPerOctave) {
        precondition(nBins > 1 && bpo > 0)
        self.nBins = nBins
        // fmin = note_to_hz("C1") = midi_to_hz(24); tuning 0.
        let fmin = 440.0 * pow(2.0, (24.0 - 69.0) / 12.0)
        let freqs = (0..<nBins).map { fmin * pow(2.0, Double($0) / Double(bpo)) }

        // filters._relative_bandwidth
        let logf = freqs.map { log2($0) }
        var localBpo = [Double](repeating: 0, count: nBins)
        localBpo[0] = 1 / (logf[1] - logf[0])
        localBpo[nBins - 1] = 1 / (logf[nBins - 1] - logf[nBins - 2])
        for i in 1..<(nBins - 1) { localBpo[i] = 2 / (logf[i + 1] - logf[i - 1]) }
        let alpha = localBpo.map { (pow(2.0, 2 / $0) - 1) / (pow(2.0, 2 / $0) + 1) }

        // filters.wavelet_lengths (gamma 0, filter_scale 1): Q = 1/alpha, longitud = Q·sr/f.
        let fCutoff = zip(freqs, alpha).map { f, a in f * (1 + 0.5 * Self.hannBandwidth * a) }.max()!
        let nyquist = sr0 / 2
        let nOctaves = Int(ceil(Double(nBins) / Double(bpo)))
        let nFilters = min(bpo, nBins)

        // __early_downsample_count
        let count1 = max(0, Int(ceil(log2(nyquist / fCutoff))) - 2)
        let count2 = max(0, hop0.trailingZeroBitCount - nOctaves + 1)
        let early = min(count1, count2)
        earlyDownsamples = early
        let sr = sr0 / Double(1 << early)
        var myHop = hop0 >> early
        var mySr = sr

        lengthScale = zip(freqs, alpha).map { f, a in Float(1 / ((1 / a) * sr / f).squareRoot()) }
        halfband = Self.designHalfband()

        var octs: [Octave] = []
        for i in 0..<nOctaves {
            let hi = nBins - nFilters * i
            let lo = max(0, nBins - nFilters * (i + 1))
            let (nfft, rows) = Self.basis(freqs: freqs[lo..<hi], alpha: alpha[lo..<hi], sr: mySr,
                                          gain: (sr / mySr).squareRoot())
            let octaveHop = myHop
            var halve = false
            if i < nOctaves - 1, lo > 0 {
                let fMaxNext = freqs[lo - 1]
                if myHop % 2 == 0 && fMaxNext <= mySr / 5 {
                    halve = true
                    myHop /= 2
                    mySr /= 2
                }
            }
            let setup = DSP.ComplexDFT(count: nfft, direction: .forward)!
            octs.append(Octave(firstBin: lo, nfft: nfft, hop: octaveHop, rows: rows, halveAfter: halve, dft: setup))
        }
        octaves = octs
    }

    // MARK: - Bases

    /// `__vqt_filter_fft` para una octava: `filters.wavelet(pad_fft=True, norm=1)`, `basis *= lengths/n_fft`,
    /// FFT, mitad no negativa, `sparsify_rows(quantile=0.01)` y `× √(sr/sr_octava)`.
    static func basis(freqs: ArraySlice<Double>, alpha: ArraySlice<Double>, sr: Double, gain: Double) -> (Int, [Row]) {
        let lengths = zip(freqs, alpha).map { f, a in (1 / a) * sr / f }
        let nfft = Int(pow(2.0, ceil(log2(lengths.max()!))))
        let half = nfft / 2
        let setup = DSP.ComplexDFTD(count: nfft, direction: .forward)!
        var inR = [Double](repeating: 0, count: nfft), inI = inR, outR = inR, outI = inR
        var rows: [Row] = []
        for (ilen, f) in zip(lengths, freqs) {
            // np.arange(-ilen // 2, ilen // 2): de floor(-ilen/2) a floor(ilen/2) (excluido).
            let n0 = (-ilen / 2).rounded(.down)
            let n1 = (ilen / 2).rounded(.down)
            let len = Int(n1 - n0)
            var re = [Double](repeating: 0, count: len), im = re
            var l1 = 0.0
            for j in 0..<len {
                let phase = (n0 + Double(j)) * 2 * Double.pi * f / sr
                // get_window("hann", len, fftbins=True): Hann periódica.
                let w = 0.5 - 0.5 * cos(2 * Double.pi * Double(j) / Double(len))
                re[j] = cos(phase) * w
                im[j] = sin(phase) * w
                l1 += (re[j] * re[j] + im[j] * im[j]).squareRoot()
            }
            // util.normalize(norm=1), luego basis *= lengths / n_fft; pad_center a n_fft.
            let k = ilen / Double(nfft) / l1
            for j in 0..<nfft { inR[j] = 0; inI[j] = 0 }
            let lpad = (nfft - len) / 2
            for j in 0..<len {
                inR[lpad + j] = re[j] * k
                inI[lpad + j] = im[j] * k
            }
            setup.execute(inR, inI, &outR, &outI)

            // sparsify_rows en float32, como librosa (la base es complex64).
            let fr = (0...half).map { Float(outR[$0]) }
            let fi = (0...half).map { Float(outI[$0]) }
            let mags = zip(fr, fi).map { ($0 * $0 + $1 * $1).squareRoot() }
            let norm = mags.reduce(0, +)
            let sorted = mags.sorted()
            var cum: Float = 0
            var thresh = sorted.last!
            for m in sorted {
                cum += m / norm
                if cum >= sparsity { thresh = m; break }
            }
            var ks: [Int] = [], rr: [Float] = [], ri: [Float] = []
            let g = Float(gain)
            for i in 0...half where mags[i] >= thresh {
                ks.append(i)
                rr.append(fr[i] * g)
                ri.append(fi[i] * g)
            }
            rows.append(Row(k: ks, re: rr, im: ri))
        }
        return (nfft, rows)
    }

    // MARK: - Diezmación

    /// FIR Kaiser de fase lineal equivalente a soxr HQ en ×1/2: banda de paso hasta 0,913 del Nyquist de
    /// salida, banda eliminada desde el Nyquist, ~126 dB (20 bits). Ganancia 1 en continua.
    static func designHalfband(attenuationDB att: Double = 126, passbandEnd: Double = 0.913) -> [Float] {
        let fs = 0.25                       // Nyquist de salida en ciclos por muestra de entrada
        let fp = passbandEnd * fs
        let fc = (fp + fs) / 2
        let beta = 0.1102 * (att - 8.7)
        var n = Int(ceil((att - 7.95) / (2.285 * 2 * Double.pi * (fs - fp)))) + 1
        if n % 2 == 0 { n += 1 }
        let mid = Double(n - 1) / 2
        func i0(_ x: Double) -> Double {
            var sum = 1.0, term = 1.0, k = 1.0
            while term > 1e-17 * sum {
                term *= (x / (2 * k)) * (x / (2 * k))
                sum += term
                k += 1
            }
            return sum
        }
        let i0b = i0(beta)
        var h = (0..<n).map { i -> Double in
            let t = Double(i) - mid
            let x = 2 * fc * t
            let sinc = t == 0 ? 1 : sin(Double.pi * x) / (Double.pi * x)
            let r = t / mid
            return 2 * fc * sinc * i0(beta * max(0, 1 - r * r).squareRoot()) / i0b
        }
        let s = h.reduce(0, +)
        h = h.map { $0 / s }
        return h.map(Float.init)
    }

    /// `librosa.resample(y, orig_sr=2, target_sr=1, scale=True)`: ceil(n/2) muestras, centrado (sin retardo),
    /// relleno con ceros fuera de la señal, × √2.
    func halve(_ x: [Float]) -> [Float] {
        let n = x.count
        guard n > 0 else { return [] }
        let m = (n + 1) / 2
        let p = halfband.count
        let c = p / 2
        var padded = [Float](repeating: 0, count: 2 * (m - 1) + p)
        padded.withUnsafeMutableBufferPointer { dst in
            x.withUnsafeBufferPointer { src in (dst.baseAddress! + c).update(from: src.baseAddress!, count: n) }
        }
        var out = [Float](repeating: 0, count: m)
        DSP.desamp(padded, 2, halfband, &out, DSPLength(m), DSPLength(p))
        var s = Float(2.0.squareRoot())
        DSP.vsmul(out, 1, &s, &out, 1, DSPLength(m))
        return out
    }

    // MARK: - Transformada

    /// |CQT| de un trozo, en orden tiempo × bin (`frames × nBins`). Tramas = 1 + n / hop.
    func magnitude(_ y: [Float]) -> (values: [Float], frames: Int) {
        var sig = y
        for _ in 0..<earlyDownsamples { sig = halve(sig) }
        var perOctave: [[Float]] = []      // filas × tramas de cada octava
        var frames = Int.max
        for o in octaves {
            let r = response(sig, octave: o)
            perOctave.append(r.mags)
            frames = min(frames, r.frames)
            if o.halveAfter { sig = halve(sig) }
        }
        var out = [Float](repeating: 0, count: frames * nBins)
        for (o, mags) in zip(octaves, perOctave) {
            let oframes = mags.count / max(o.rows.count, 1)
            for b in 0..<o.rows.count {
                let bin = o.firstBin + b
                let s = lengthScale[bin]
                for t in 0..<frames { out[t * nBins + bin] = mags[b * oframes + t] * s }
            }
        }
        return (out, frames)
    }

    /// `__cqt_response`: STFT con ventana de unos, centrada con ceros, y producto por la base dispersa
    /// (sin conjugar, como `fft_basis.dot(D)`). Devuelve |·| en filas × tramas.
    private func response(_ y: [Float], octave o: Octave) -> (mags: [Float], frames: Int) {
        let nfft = o.nfft, half = nfft / 2
        let frames = 1 + y.count / o.hop
        var padded = [Float](repeating: 0, count: y.count + nfft)
        padded.withUnsafeMutableBufferPointer { dst in
            y.withUnsafeBufferPointer { src in (dst.baseAddress! + half).update(from: src.baseAddress!, count: y.count) }
        }
        let zeros = [Float](repeating: 0, count: nfft)
        var xr = [Float](repeating: 0, count: nfft), xi = xr
        var mags = [Float](repeating: 0, count: o.rows.count * frames)
        padded.withUnsafeBufferPointer { p in
            for t in 0..<frames {
                o.dft.execute(p.baseAddress! + t * o.hop, zeros, &xr, &xi)
                for (b, row) in o.rows.enumerated() {
                    var sr: Float = 0, si: Float = 0
                    for (j, k) in row.k.enumerated() {
                        let br = row.re[j], bi = row.im[j]
                        sr += br * xr[k] - bi * xi[k]
                        si += br * xi[k] + bi * xr[k]
                    }
                    mags[b * frames + t] = (sr * sr + si * si).squareRoot()
                }
            }
        }
        return (mags, frames)
    }

    /// CQT por trozos de 10 s concatenados (`btc_common.cqt_features`), orden tiempo × bin.
    func chunkedMagnitude(_ wav: [Float], chunk: Int = ChordContract.chunkSamples) -> (values: [Float], frames: Int) {
        var ranges: [Range<Int>] = []
        var cur = 0
        while wav.count > cur + chunk {
            ranges.append(cur..<(cur + chunk))
            cur += chunk
        }
        ranges.append(cur..<wav.count)
        let parts = Slots<(values: [Float], frames: Int)>(count: ranges.count, initial: ([], 0))
        // Copia inmutable: en Windows el cierre de concurrentPerform es @Sendable y no admite capturar un var.
        let chunks = ranges
        DispatchQueue.concurrentPerform(iterations: chunks.count) { i in
            let r = chunks[i]
            parts[i] = r.isEmpty ? ([], 0) : magnitude(Array(wav[r]))
        }
        var values: [Float] = []
        var frames = 0
        for i in 0..<ranges.count {
            values.append(contentsOf: parts[i].values)
            frames += parts[i].frames
        }
        return (values, frames)
    }
}

/// Casillas fijas que `concurrentPerform` rellena, cada iteración la suya.
private final class Slots<T>: @unchecked Sendable {
    private let p: UnsafeMutableBufferPointer<T>

    init(count: Int, initial: T) {
        p = .allocate(capacity: count)
        p.initialize(repeating: initial)
    }

    deinit {
        _ = p.deinitialize()
        p.deallocate()
    }

    subscript(i: Int) -> T {
        get { p[i] }
        set { p[i] = newValue }
    }
}
