import Accelerate
import Foundation

/// |CQT| de 12 bins por octava desde E1 (84 bins, 7 octavas), hop 256 a 22 050 Hz: lo que mide la alineación con
/// Songsterr (mini-spec Fase 5b, «Alineación»), como `cqt_salience` de `Probes/P5b-guitarra/eval_reference.py`.
///
/// Réplica de `librosa.cqt(y, sr=22050, hop_length=256, fmin=midi_to_hz(28), n_bins=84, bins_per_octave=12)`
/// (tuning 0, filter_scale 1, ventana Hann, norm 1, scale True): cada bin es el producto escalar del audio con una
/// sinusoide compleja en ventana Hann de longitud `Q·sr/f` normalizada en L1, por `√longitud`, con la trama `t`
/// centrada en la muestra `t·256`. Como en librosa, cada octava se calcula con el audio diezmado a la mitad respecto
/// a la de encima, así que todas las ventanas miden lo mismo en muestras (~145) y el coste no depende de la altura.
struct SemitoneSpectrogram {
    static let sampleRate = 22_050.0
    static let hop = 256
    /// E1: la cuerda más grave del bajo de 4.
    static let lowestMIDI = 28
    static let binsPerOctave = 12
    static let octaves = 7
    static var binCount: Int { binsPerOctave * octaves }
    /// Q de librosa (`filters.wavelet_lengths`): `1/α` con α = (2^(2/12) − 1)/(2^(2/12) + 1).
    static let q: Double = {
        let r = pow(2.0, 2.0 / Double(binsPerOctave))
        return (r + 1) / (r - 1)
    }()
    /// Filtro de media banda para diezmar por 2: seno cardinal con corte en 1/4 de la frecuencia de muestreo y
    /// ventana Blackman. Paso plano hasta ~0,2·sr (la octava más aguda que se mide en cada paso llega a 0,24·sr del
    /// paso siguiente, es decir, 0,12·sr de este) y lo que se pliega cae por encima de la banda útil.
    static let halfBandTaps = 63
    static let halfBand: [Float] = {
        let n = halfBandTaps, m = Double(n - 1) / 2, fc = 0.25
        var h = (0..<n).map { i -> Double in
            let x = Double(i) - m
            let sinc = x == 0 ? 2 * fc : sin(2 * .pi * fc * x) / (.pi * x)
            let w = 0.42 - 0.5 * cos(2 * .pi * Double(i) / Double(n - 1)) + 0.08 * cos(4 * .pi * Double(i) / Double(n - 1))
            return sinc * w
        }
        let sum = h.reduce(0, +)
        h = h.map { $0 / sum }
        return h.map(Float.init)
    }()

    static func midiHz(_ midi: Double) -> Double { 440 * pow(2, (midi - 69) / 12) }

    let frameCount: Int
    /// |CQT| en orden bin × trama: `magnitude[bin * frameCount + trama]`.
    let magnitude: [Float]

    /// - Parameter samples: mono a `sampleRate`.
    init(samples: [Float]) {
        let frames = 1 + samples.count / Self.hop
        frameCount = frames
        let nb = Self.binCount, bpo = Self.binsPerOctave
        let topDecimation = 1 << (Self.octaves - 1)
        // Mismas ventanas en todas las octavas (en muestras de su audio diezmado): la del bin j de la octava o mide
        // Q·(sr/2^(6−o))/(f₀·2^o·2^(j/12)) = Q·sr/(64·f₀·2^(j/12)).
        let f0 = Self.midiHz(Double(Self.lowestMIDI))
        let lengths = (0..<bpo).map { Self.q * Self.sampleRate / (Double(topDecimation) * f0 * pow(2, Double($0) / 12)) }
        let width = Int(lengths[0].rounded(.up)) + 1
        // Núcleos: columnas (re, −im) de cada bin, centrados en `width`, normalizados en L1.
        var kernels = [Float](repeating: 0, count: width * 2 * bpo)
        let octaveRate = Self.sampleRate / Double(topDecimation)
        for j in 0..<bpo {
            let n = Int(lengths[j].rounded())
            let f = f0 * pow(2, Double(j) / 12)
            let lpad = (width - n) / 2
            var hann = (0..<n).map { 0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(n)) }
            let norm = hann.reduce(0, +)
            hann = hann.map { $0 / norm }
            for i in 0..<n {
                let phase = 2 * Double.pi * f * Double(i - n / 2) / octaveRate
                kernels[(lpad + i) * 2 * bpo + 2 * j] = Float(hann[i] * cos(phase))
                kernels[(lpad + i) * 2 * bpo + 2 * j + 1] = Float(-hann[i] * sin(phase))
            }
        }

        var out = [Float](repeating: 0, count: nb * frames)
        var signal = samples
        var response = [Float](repeating: 0, count: frames * 2 * bpo)
        var rows = [Float](repeating: 0, count: frames * width)
        for o in stride(from: Self.octaves - 1, through: 0, by: -1) {
            let decimation = 1 << (Self.octaves - 1 - o)
            if o < Self.octaves - 1 { signal = Self.halve(signal) }
            let hopO = Self.hop / decimation
            // Audio de la octava con `width/2` ceros delante: la fila t empieza en t·hopO y su centro es la muestra t·hopO.
            let half = width / 2
            var padded = [Float](repeating: 0, count: half + max(signal.count, (frames - 1) * hopO + 1) + width)
            padded.withUnsafeMutableBufferPointer { p in
                signal.withUnsafeBufferPointer { s in
                    if s.count > 0 { (p.baseAddress! + half).update(from: s.baseAddress!, count: s.count) }
                }
            }
            rows.withUnsafeMutableBufferPointer { r in
                padded.withUnsafeBufferPointer { p in
                    for t in 0..<frames {
                        (r.baseAddress! + t * width).update(from: p.baseAddress! + t * hopO, count: width)
                    }
                }
            }
            vDSP_mmul(rows, 1, kernels, 1, &response, 1, vDSP_Length(frames), vDSP_Length(2 * bpo), vDSP_Length(width))
            // scale=True de librosa: × √(longitud de la ventana a la frecuencia de muestreo original).
            for j in 0..<bpo {
                let bin = o * bpo + j
                var gain = Float((lengths[j] * Double(decimation)).squareRoot())
                response.withUnsafeBufferPointer { r in
                    out.withUnsafeMutableBufferPointer { m in
                        var split = DSPSplitComplex(realp: UnsafeMutablePointer(mutating: r.baseAddress! + 2 * j),
                                                    imagp: UnsafeMutablePointer(mutating: r.baseAddress! + 2 * j + 1))
                        let dst = m.baseAddress! + bin * frames
                        vDSP_zvabs(&split, vDSP_Stride(2 * bpo), dst, 1, vDSP_Length(frames))
                        vDSP_vsmul(dst, 1, &gain, dst, 1, vDSP_Length(frames))
                    }
                }
            }
        }
        magnitude = out
    }

    /// Diezmado por 2 con fase cero: `y[n] = Σ h[p]·x[2n + p − 31]`.
    static func halve(_ x: [Float]) -> [Float] {
        let taps = halfBandTaps, m = (taps - 1) / 2
        let outCount = (x.count + 1) / 2
        guard outCount > 0 else { return [] }
        var padded = [Float](repeating: 0, count: m + x.count + taps + 1)
        padded.withUnsafeMutableBufferPointer { p in
            x.withUnsafeBufferPointer { s in (p.baseAddress! + m).update(from: s.baseAddress!, count: s.count) }
        }
        var y = [Float](repeating: 0, count: outCount)
        vDSP_desamp(padded, 2, halfBand, &y, vDSP_Length(outCount), vDSP_Length(taps))
        return y
    }

    /// Normalizada por trama a [0, 1] (`c / (c.max(axis=0) + 1e-9)`), mismo orden que `magnitude`.
    func salience() -> [Float] {
        let n = frameCount, nb = Self.binCount
        var peak = [Float](repeating: 0, count: n)
        var eps: Float = 1e-9
        magnitude.withUnsafeBufferPointer { m in
            peak.withUnsafeMutableBufferPointer { p in
                for b in 0..<nb { vDSP_vmax(m.baseAddress! + b * n, 1, p.baseAddress!, 1, p.baseAddress!, 1, vDSP_Length(n)) }
                vDSP_vsadd(p.baseAddress!, 1, &eps, p.baseAddress!, 1, vDSP_Length(n))
            }
        }
        var out = magnitude
        out.withUnsafeMutableBufferPointer { o in
            for b in 0..<nb {
                let row = o.baseAddress! + b * n
                vDSP_vdiv(peak, 1, row, 1, row, 1, vDSP_Length(n))
            }
        }
        return out
    }

    /// Croma (12 clases × tramas de `hop · pool`): suma de los bins de cada clase y media de las `pool` tramas
    /// centradas en la del croma. Orden clase × trama. La clase 0 es Do.
    func chroma(pool: Int) -> (values: [Float], frames: Int) {
        let n = frameCount, nb = Self.binCount
        var pc = [Float](repeating: 0, count: 12 * n)
        magnitude.withUnsafeBufferPointer { m in
            pc.withUnsafeMutableBufferPointer { c in
                for b in 0..<nb {
                    let cls = (Self.lowestMIDI + b) % 12
                    let dst = c.baseAddress! + cls * n
                    vDSP_vadd(dst, 1, m.baseAddress! + b * n, 1, dst, 1, vDSP_Length(n))
                }
            }
        }
        let frames = 1 + (n - 1) / pool
        var out = [Float](repeating: 0, count: 12 * frames)
        pc.withUnsafeBufferPointer { c in
            for cls in 0..<12 {
                for t in 0..<frames {
                    let lo = max(0, t * pool - pool / 2), hi = min(n, t * pool + (pool + 1) / 2)
                    guard hi > lo else { continue }
                    var mean: Float = 0
                    vDSP_meanv(c.baseAddress! + cls * n + lo, 1, &mean, vDSP_Length(hi - lo))
                    out[cls * frames + t] = mean
                }
            }
        }
        return (out, frames)
    }
}

/// Envolvente de ataques de un stem: flujo espectral positivo del logaritmo de la magnitud (STFT Hann de 1024
/// muestras, hop 128 a 22 050 Hz, ~5,8 ms), dividido por su media. Para el ajuste fino en ms de la alineación.
struct OnsetEnvelope {
    static let fftSize = 1024
    static let hop = 128
    /// Compresión: log(1 + γ·|X|).
    static let compression: Float = 10
    /// Lo que adelanta el pico de la envolvente al ataque: con la ventana centrada, el flujo logarítmico salta en
    /// cuanto el ataque entra en la parte con peso de la ventana (~0,3 de ella). Medido con tonos de ataque de 2 ms
    /// en `SongsterrAlignerTests.testOnsetEnvelopePeakMatchesAttack` (14,6 ms); se resta al tiempo de la nota al leer.
    static let peakAdvance = 0.0146

    let values: [Float]
    let frameRate: Double
    /// Tiempo de la muestra 0 de `values`: la diferencia entre las tramas t−1 y t se fecha en su punto medio.
    let start: Double

    init(samples: [Float], sampleRate: Double) {
        let nfft = Self.fftSize, half = nfft / 2, hop = Self.hop
        let frames = 1 + samples.count / hop
        frameRate = sampleRate / Double(hop)
        start = 0.5 / frameRate
        guard frames >= 2, let setup = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(nfft), .FORWARD) else {
            values = []
            return
        }
        defer { vDSP_DFT_DestroySetup(setup) }
        let window = (0..<nfft).map { Float(0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(nfft))) }
        var frame = [Float](repeating: 0, count: nfft)
        var inRe = [Float](repeating: 0, count: half), inIm = [Float](repeating: 0, count: half)
        var outRe = [Float](repeating: 0, count: half), outIm = [Float](repeating: 0, count: half)
        var prev = [Float](repeating: 0, count: half), cur = [Float](repeating: 0, count: half)
        var diff = [Float](repeating: 0, count: half)
        var env = [Float](repeating: 0, count: frames - 1)
        var gamma = Self.compression, one: Float = 1, zero: Float = 0
        var count = Int32(half)
        samples.withUnsafeBufferPointer { x in
            for t in 0..<frames {
                let s = t * hop - nfft / 2
                let lo = max(0, s), hi = min(x.count, s + nfft)
                frame.withUnsafeMutableBufferPointer { fr in
                    fr.update(repeating: 0)
                    if hi > lo { (fr.baseAddress! + (lo - s)).update(from: x.baseAddress! + lo, count: hi - lo) }
                    vDSP_vmul(fr.baseAddress!, 1, window, 1, fr.baseAddress!, 1, vDSP_Length(nfft))
                }
                inRe.withUnsafeMutableBufferPointer { ir in
                    inIm.withUnsafeMutableBufferPointer { ii in
                        var split = DSPSplitComplex(realp: ir.baseAddress!, imagp: ii.baseAddress!)
                        frame.withUnsafeBytes { raw in
                            vDSP_ctoz(raw.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(half))
                        }
                        vDSP_DFT_Execute(setup, ir.baseAddress!, ii.baseAddress!, &outRe, &outIm)
                    }
                }
                outRe[0] = 0  // continua fuera (y en im[0] va Nyquist)
                outIm[0] = 0
                outRe.withUnsafeMutableBufferPointer { orr in
                    outIm.withUnsafeMutableBufferPointer { oi in
                        var split = DSPSplitComplex(realp: orr.baseAddress!, imagp: oi.baseAddress!)
                        vDSP_zvabs(&split, 1, &cur, 1, vDSP_Length(half))
                    }
                }
                cur.withUnsafeMutableBufferPointer { c in
                    vDSP_vsmsa(c.baseAddress!, 1, &gamma, &one, c.baseAddress!, 1, vDSP_Length(half))
                    vvlogf(c.baseAddress!, c.baseAddress!, &count)
                }
                if t > 0 {
                    diff.withUnsafeMutableBufferPointer { d in
                        vDSP_vsub(prev, 1, cur, 1, d.baseAddress!, 1, vDSP_Length(half))
                        vDSP_vthres(d.baseAddress!, 1, &zero, d.baseAddress!, 1, vDSP_Length(half))
                        var sum: Float = 0
                        vDSP_sve(d.baseAddress!, 1, &sum, vDSP_Length(half))
                        env[t - 1] = sum
                    }
                }
                swap(&prev, &cur)
            }
        }
        var mean: Float = 0
        vDSP_meanv(env, 1, &mean, vDSP_Length(env.count))
        if mean > 0 {
            var inv = 1 / mean
            env.withUnsafeMutableBufferPointer { e in
                vDSP_vsmul(e.baseAddress!, 1, &inv, e.baseAddress!, 1, vDSP_Length(e.count))
            }
        }
        values = env
    }

    /// Valor interpolado en `time` (s); 0 fuera.
    func value(at time: Double) -> Float {
        let x = (time - start) * frameRate
        guard x >= 0, !values.isEmpty else { return 0 }
        let i = Int(x)
        guard i + 1 < values.count else { return i < values.count ? values[i] : 0 }
        let f = Float(x - Double(i))
        return values[i] * (1 - f) + values[i + 1] * f
    }
}
