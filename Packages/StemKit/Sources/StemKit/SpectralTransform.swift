import Foundation
import NativeDSP

/// STFT/iSTFT compatibles con `torch.stft`/`torch.istft` (center=True, relleno reflect,
/// Hann periódica, iSTFT normalizada por la suma de ventanas al cuadrado), como
/// `stft_np`/`istft_np` de Probes/P4-modelos/bs_roformer_sw/sw_common.py.
///
/// El espectro se lee y escribe directamente en el layout del tensor `spec` del contrato:
/// `[2·bins, frames, 2]`, fila `2·f + canal`, re/im en el último eje, es decir
/// `spec[((2·f + canal) · frames + t) · 2 + ri]`.
///
/// No es seguro entre hilos: cada hilo usa su propia instancia (los búferes de trabajo son suyos).
final class SpectralTransform {
    let nFFT = RoformerContract.nFFT
    /// 512 en BS-RoFormer SW, 441 en el modelo de solista (`MaskModelContract`).
    let hop: Int
    let bins = RoformerContract.bins
    /// Muestras por canal de la señal en el dominio del tiempo.
    let length: Int
    /// `1 + length / hop`, como `torch.stft(center=True)`.
    let frames: Int

    /// DFT real empaquetada de la fachada `NativeDSP` (vDSP en el Mac, pocketfft en Windows; misma convención).
    private let forwardSetup: DSP.RealDFT
    private let inverseSetup: DSP.RealDFT
    /// Hann · 0,5: compensa el factor 2 de la DFT real directa (convención vDSP).
    private let analysisWindow: UnsafeMutablePointer<Float>
    /// Hann / n_fft: la DFT real inversa (convención vDSP) devuelve n_fft · irfft.
    private let synthesisWindow: UnsafeMutablePointer<Float>
    /// 1 / Σ w² en cada muestra de salida (1 donde la suma ≤ 1e-11, como istft_np).
    private let inverseEnvelope: UnsafeMutablePointer<Float>
    private let padded: UnsafeMutablePointer<Float>   // length + nFFT
    private let ola: UnsafeMutablePointer<Float>      // length + nFFT
    private let frame: UnsafeMutablePointer<Float>    // nFFT
    private let splitInR: UnsafeMutablePointer<Float> // nFFT / 2
    private let splitInI: UnsafeMutablePointer<Float>
    private let splitOutR: UnsafeMutablePointer<Float>
    private let splitOutI: UnsafeMutablePointer<Float>

    /// - Parameter length: debe ser > n_fft / 2 (el relleno reflect lo exige, igual que en torch).
    init(length: Int, hop: Int = RoformerContract.hop) {
        precondition(length > RoformerContract.nFFT / 2, "STFT: longitud demasiado corta para el relleno reflect")
        // hop ≤ n_fft/2: la envolvente Σ w² cubre toda la salida.
        precondition(hop > 0 && hop <= RoformerContract.nFFT / 2, "STFT: hop fuera de rango")
        self.length = length
        self.hop = hop
        self.frames = 1 + length / hop
        let n = RoformerContract.nFFT
        let half = n / 2
        guard let f = DSP.RealDFT(count: n, direction: .forward),
              let i = DSP.RealDFT(count: n, direction: .inverse) else {
            fatalError("DSP.RealDFT falló para n=\(n)")
        }
        forwardSetup = f
        inverseSetup = i

        func alloc(_ count: Int) -> UnsafeMutablePointer<Float> {
            let p = UnsafeMutablePointer<Float>.allocate(capacity: count)
            p.initialize(repeating: 0, count: count)
            return p
        }
        analysisWindow = alloc(n)
        synthesisWindow = alloc(n)
        inverseEnvelope = alloc(length)
        padded = alloc(length + n)
        ola = alloc(length + n)
        frame = alloc(n)
        splitInR = alloc(half)
        splitInI = alloc(half)
        splitOutR = alloc(half)
        splitOutI = alloc(half)

        // Hann periódica en Double (como sw_common._WINDOW) y luego a Float.
        var hann = [Double](repeating: 0, count: n)
        for k in 0..<n { hann[k] = 0.5 - 0.5 * cos(2 * Double.pi * Double(k) / Double(n)) }
        for k in 0..<n {
            analysisWindow[k] = Float(hann[k] * 0.5)
            synthesisWindow[k] = Float(hann[k] / Double(n))
        }
        // Envolvente Σ w² sobre la señal rellenada; la salida es [n/2, n/2 + length).
        let total = n + hop * (frames - 1)
        var env = [Double](repeating: 0, count: total)
        for t in 0..<frames {
            let a = t * hop
            for k in 0..<n { env[a + k] += hann[k] * hann[k] }
        }
        for j in 0..<length {
            let e = env[half + j]
            inverseEnvelope[j] = e > 1e-11 ? Float(1 / e) : 1
        }
    }

    deinit {
        for p in [analysisWindow, synthesisWindow, inverseEnvelope, padded, ola, frame,
                  splitInR, splitInI, splitOutR, splitOutI] {
            p.deallocate()
        }
    }

    /// Número de floats del tensor `spec` para esta longitud: 2 canales · bins · frames · 2.
    var specCount: Int { 2 * bins * frames * 2 }

    /// Índice del elemento real de (bin `f`, canal `c`, trama `t`) en el layout `spec`.
    @inline(__always)
    func specIndex(bin f: Int, channel c: Int, frame t: Int) -> Int {
        ((2 * f + c) * frames + t) * 2
    }

    /// STFT del canal `channel` de `x` (`length` muestras), escrita en `spec` con el layout del contrato.
    func forward(_ x: UnsafePointer<Float>, channel: Int, into spec: UnsafeMutablePointer<Float>) {
        let half = nFFT / 2
        // center=True: relleno reflect de n_fft/2 por cada lado (sin repetir el borde, como numpy/torch).
        reflectPad(x, count: length, left: half, right: half, into: padded)
        let binStride = DSPStride(4 * frames)
        var inSplit = SplitComplex(realp: splitInR, imagp: splitInI)
        for t in 0..<frames {
            DSP.vmul(padded + t * hop, 1, analysisWindow, 1, frame, 1, DSPLength(nFFT))
            frame.withMemoryRebound(to: InterleavedComplex.self, capacity: half) {
                DSP.ctoz($0, 2, &inSplit, 1, DSPLength(half))
            }
            forwardSetup.execute(splitInR, splitInI, splitOutR, splitOutI)
            // Formato empaquetado (convención vDSP): R[0] = DC, I[0] = Nyquist (ambos reales).
            let dc = specIndex(bin: 0, channel: channel, frame: t)
            let nyq = specIndex(bin: bins - 1, channel: channel, frame: t)
            spec[dc] = splitOutR[0]
            spec[dc + 1] = 0
            spec[nyq] = splitOutI[0]
            spec[nyq + 1] = 0
            let first = specIndex(bin: 1, channel: channel, frame: t)
            var src = SplitComplex(realp: splitOutR + 1, imagp: splitOutI + 1)
            var dst = SplitComplex(realp: spec + first, imagp: spec + first + 1)
            DSP.zvmov(&src, 1, &dst, binStride, DSPLength(half - 1))
        }
    }

    /// iSTFT del canal `channel` leído de `spec` (layout del contrato); escribe `length` muestras en `y`.
    /// Como irfft, ignora la parte imaginaria de DC y Nyquist.
    func inverse(_ spec: UnsafePointer<Float>, channel: Int, into y: UnsafeMutablePointer<Float>) {
        let half = nFFT / 2
        let spec = UnsafeMutablePointer(mutating: spec)
        let binStride = DSPStride(4 * frames)
        ola.update(repeating: 0, count: length + nFFT)
        var outSplit = SplitComplex(realp: splitOutR, imagp: splitOutI)
        for t in 0..<frames {
            splitInR[0] = spec[specIndex(bin: 0, channel: channel, frame: t)]
            splitInI[0] = spec[specIndex(bin: bins - 1, channel: channel, frame: t)]
            let first = specIndex(bin: 1, channel: channel, frame: t)
            var src = SplitComplex(realp: spec + first, imagp: spec + first + 1)
            var dst = SplitComplex(realp: splitInR + 1, imagp: splitInI + 1)
            DSP.zvmov(&src, binStride, &dst, 1, DSPLength(half - 1))
            inverseSetup.execute(splitInR, splitInI, splitOutR, splitOutI)
            frame.withMemoryRebound(to: InterleavedComplex.self, capacity: half) {
                DSP.ztoc(&outSplit, 1, $0, 2, DSPLength(half))
            }
            let dstOLA = ola + t * hop
            DSP.vma(frame, 1, synthesisWindow, 1, dstOLA, 1, dstOLA, 1, DSPLength(nFFT))
        }
        DSP.vmul(ola + half, 1, inverseEnvelope, 1, y, 1, DSPLength(length))
    }
}

/// Relleno `reflect` de numpy (sin repetir el borde): `dst = [x[left] … x[1], x, x[n-2] … x[n-1-right]]`.
/// Requiere `left < count` y `right < count`.
func reflectPad(_ x: UnsafePointer<Float>, count n: Int, left: Int, right: Int,
                into dst: UnsafeMutablePointer<Float>) {
    precondition(left < n && right < n, "reflect: relleno mayor que la señal")
    if left > 0 {
        dst.update(from: x + 1, count: left)
        DSP.vrvrs(dst, 1, DSPLength(left))
    }
    (dst + left).update(from: x, count: n)
    if right > 0 {
        let tail = dst + left + n
        tail.update(from: x + (n - 1 - right), count: right)
        DSP.vrvrs(tail, 1, DSPLength(right))
    }
}
