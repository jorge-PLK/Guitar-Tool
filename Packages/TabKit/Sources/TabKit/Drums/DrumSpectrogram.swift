import Accelerate
import Foundation

/// Entrada de ADTOF (`adtof_pytorch.audio.AudioProcessor.process_audio`): STFT 2048 / 441 con `np.hanning`,
/// `center=True` y relleno de ceros, |X| de los bins 0..1023, banco logarítmico estilo madmom (84 bandas) y
/// log10(1 + x). Mini-spec Fase 5, «Transcripción», Batería.
enum DrumSpectrogram {
    typealias C = DrumContract

    /// Una banda del banco: pesos no nulos desde el bin `start` (contiguos; los ceros intermedios se guardan).
    struct Band: Sendable {
        var start: Int
        var weights: [Float]
    }

    /// `_setup_filterbank`: frecuencias logarítmicas → bin FFT más cercano → bins únicos → triángulos
    /// normalizados a suma 1. Los pesos se calculan en Double y se guardan en float32, como el original.
    static let filterbank: [Band] = makeFilterbank()

    static func makeFilterbank() -> [Band] {
        // `_log_frequencies`: f = 20 · 2^(k/12) mientras f ≤ 20 000 · (1 + 1e-12), por multiplicación sucesiva.
        var freqs = [Double]()
        let factor = pow(2.0, 1.0 / Double(C.bandsPerOctave))
        var f = C.minFrequency
        while f <= C.maxFrequency * (1.0 + 1e-12) {
            freqs.append(f)
            f *= factor
        }
        // `np.fft.fftfreq(2048, 1 / 44 100)[:1024]` = k · 1 / (2048 · (1 / 44 100)).
        let step = 1.0 / (Double(C.fftSize) * (1.0 / C.sampleRate))
        let n = C.magnitudeBins
        var bins = [Int]()
        for f in freqs {
            // `argmin |fftfreq − f|`: el primero si empatan.
            var best = 0, bestD = Double.infinity
            for k in 0..<n {
                let d = abs(Double(k) * step - f)
                if d < bestD { best = k; bestD = d }
            }
            if best > (bins.last ?? -1) { bins.append(best) }
        }
        // `_create_madmom_filterbank`.
        var bands = [Band]()
        for i in 0..<(bins.count - 2) {
            let left = bins[i], center = bins[i + 1], right = bins[i + 2]
            var row = [Float](repeating: 0, count: n)
            if right - left < 2 {
                row[left] = 1
            } else {
                for b in left..<center { row[b] = Float(Double(b - left) / Double(center - left)) }
                row[center] = 1
                for b in (center + 1)..<min(right, n) { row[b] = Float(Double(right - b) / Double(right - center)) }
            }
            var sum = row.reduce(Float(0), +)
            if sum == 0 { sum = 1 }
            let nz = row.indices.filter { row[$0] != 0 }
            let lo = nz.first ?? 0, hi = nz.last ?? 0
            bands.append(Band(start: lo, weights: row[lo...hi].map { $0 / sum }))
        }
        return bands
    }

    /// `np.hanning(2048)`: 0,5 − 0,5 · cos(2πi / 2047), en Double y pasado a float32.
    static let window: [Float] = (0..<C.fftSize).map {
        Float(0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(C.fftSize - 1)))
    }

    /// Espectrograma [T][84] en orden C (T = 1 + floor(n / 441)) de un audio mono a 44,1 kHz.
    static func compute(_ audio: [Float]) -> [Float] {
        let nfft = C.fftSize, half = nfft / 2, hop = C.hop, nb = C.bands
        let frames = C.frames(forSamples: audio.count)
        let bands = filterbank
        precondition(bands.count == nb, "banco de \(bands.count) bandas, se esperaban \(nb)")
        guard let setup = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(nfft), .FORWARD) else {
            preconditionFailure("vDSP_DFT_zrop_CreateSetup(\(nfft))")
        }
        defer { vDSP_DFT_DestroySetup(setup) }

        var out = [Float](repeating: 0, count: frames * nb)
        var frame = [Float](repeating: 0, count: nfft)
        var inRe = [Float](repeating: 0, count: half), inIm = [Float](repeating: 0, count: half)
        var outRe = [Float](repeating: 0, count: half), outIm = [Float](repeating: 0, count: half)
        var mag = [Float](repeating: 0, count: half)
        let pad = nfft / 2
        audio.withUnsafeBufferPointer { x in
            window.withUnsafeBufferPointer { w in
                for t in 0..<frames {
                    // Trama t del audio con 1024 ceros a cada lado: muestras [t·441 − 1024, t·441 + 1024).
                    let s = t * hop - pad
                    let lo = max(0, s), hi = min(x.count, s + nfft)
                    frame.withUnsafeMutableBufferPointer { fr in
                        fr.update(repeating: 0)
                        if hi > lo { (fr.baseAddress! + (lo - s)).update(from: x.baseAddress! + lo, count: hi - lo) }
                        vDSP_vmul(fr.baseAddress!, 1, w.baseAddress!, 1, fr.baseAddress!, 1, vDSP_Length(nfft))
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
                    // Formato empaquetado de zrop, escalado por 2: re[0] = 2·X[0], im[0] = 2·X[1024] (Nyquist, fuera),
                    // (re[k], im[k]) = 2·X[k] para k = 1..1023.
                    outRe.withUnsafeMutableBufferPointer { orr in
                        outIm.withUnsafeMutableBufferPointer { oi in
                            mag.withUnsafeMutableBufferPointer { m in
                                var split = DSPSplitComplex(realp: orr.baseAddress! + 1, imagp: oi.baseAddress! + 1)
                                vDSP_zvabs(&split, 1, m.baseAddress! + 1, 1, vDSP_Length(half - 1))
                                m[0] = abs(orr[0])
                                var k: Float = 0.5
                                vDSP_vsmul(m.baseAddress!, 1, &k, m.baseAddress!, 1, vDSP_Length(half))
                            }
                        }
                    }
                    mag.withUnsafeBufferPointer { m in
                        for (b, band) in bands.enumerated() {
                            var v: Float = 0
                            band.weights.withUnsafeBufferPointer { wt in
                                vDSP_dotpr(m.baseAddress! + band.start, 1, wt.baseAddress!, 1, &v, vDSP_Length(wt.count))
                            }
                            out[t * nb + b] = v
                        }
                    }
                }
            }
        }
        // log10(1 + x): como numpy, primero 1 + x en float32 y luego log10.
        var one: Float = 1
        var count = Int32(out.count)
        out.withUnsafeMutableBufferPointer { o in
            vDSP_vsadd(o.baseAddress!, 1, &one, o.baseAddress!, 1, vDSP_Length(o.count))
            vvlog10f(o.baseAddress!, o.baseAddress!, &count)
        }
        return out
    }
}
