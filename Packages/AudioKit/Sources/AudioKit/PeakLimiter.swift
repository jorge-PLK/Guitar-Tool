import Accelerate
import Foundation

/// Limitador de pico real con anticipación para la normalización del montaje (mini-spec Fase 7, «Exportación»).
///
/// Streaming y sin distorsión por recorte: la reducción de ganancia es una curva continua, común a los dos
/// canales, que llega a su valor justo antes del pico.
/// 1. Pico real por muestra: el mayor de |x[n]| y de las muestras intermedias de `n-1…n` y `n…n+1`, de los dos
///    canales, con el mismo interpolador 4× que `LoudnessMeter` (`LoudnessMeter.phases`). Así el limitador
///    detecta lo mismo que mide el medidor y no deja pasar los picos entre muestras.
/// 2. Reducción necesaria por muestra: `umbral / pico` si lo supera, 1 si no.
/// 3. Mínimo de la ventana de anticipación (`lookAheadSeconds`), de modo que la reducción ya está completa en el pico.
/// 4. Media móvil de la misma longitud: el ataque es una rampa dentro de la anticipación.
/// 5. Liberación exponencial (`releaseSeconds`); la ganancia final nunca supera a la de ataque, así que el
///    umbral se respeta en las muestras y, salvo lo que varía la ganancia dentro del interpolador, entre ellas.
///
/// El audio sale retrasado `detectorDelay + lookAhead` muestras (otras tantas de relleno inicial que se descartan);
/// `process` devuelve lo que ya se puede entregar y `flush` el resto, de modo que la salida tiene tantas muestras
/// como la entrada.
final class PeakLimiter {
    /// Anticipación y ataque (mini-spec Fase 7, ampliación: limitador).
    static let lookAheadSeconds = 0.005
    /// Liberación (mini-spec Fase 7, ampliación: limitador).
    static let releaseSeconds = 0.1
    /// Muestras futuras que necesita el interpolador para dar las intermedias de `n…n+1`.
    static let detectorDelay = LoudnessMeter.firTaps / 2

    let lookAhead: Int
    private let threshold: Float
    private let releaseCoefficient: Double
    private var delayL: [Float]
    private var delayR: [Float]
    // Cola monótona (índice, valor) con el mínimo de la ventana.
    private let capacity: Int
    private var queueIndex: [Int]
    private var queueValue: [Float]
    private var head = 0
    private var count = 0
    private var average: [Double]
    private var averagePos = 0
    private var averageSum: Double
    private var envelope = 1.0
    private var position: Int
    /// Salidas por descartar: las de las muestras de relleno con que arranca la señal.
    private var toSkip: Int
    /// Detector: últimas `firTaps - 1` muestras de cada canal y el pico del tramo anterior (`n-1…n`).
    private var history: [[Double]]
    private var previousSpanPeak = 0.0
    /// Ganancia más baja aplicada (1 = no se limitó nada).
    private(set) var minGain = 1.0

    init(sampleRate: Double, thresholdDB: Double) {
        lookAhead = max(1, Int((Self.lookAheadSeconds * sampleRate).rounded()))
        threshold = Float(pow(10, thresholdDB / 20))
        releaseCoefficient = 1 - exp(-1 / (Self.releaseSeconds * sampleRate))
        delayL = [Float](repeating: 0, count: lookAhead)
        delayR = delayL
        capacity = lookAhead + 2
        queueIndex = [Int](repeating: 0, count: capacity)
        queueValue = [Float](repeating: 1, count: capacity)
        average = [Double](repeating: 1, count: lookAhead + 1)
        averageSum = Double(lookAhead + 1)
        history = Array(repeating: Array(repeating: 0.0, count: LoudnessMeter.firTaps - 1), count: 2)
        // Arranca con `lookAhead` muestras de silencio previas, para que el ataque llegue completo a un pico
        // que esté en las primeras muestras; el detector añade las suyas.
        position = lookAhead
        toSkip = lookAhead + Self.detectorDelay
    }

    /// Reducción máxima aplicada, en dB (≥ 0).
    var maxReductionDB: Double { -20 * log10(minGain) }

    func process(_ left: [Float], _ right: [Float]) -> ([Float], [Float]) {
        let (dl, dr, peaks) = detect(left, right)
        var outL = [Float](), outR = [Float]()
        outL.reserveCapacity(left.count)
        outR.reserveCapacity(left.count)
        for i in 0..<dl.count {
            let (l, r) = push(dl[i], dr[i], peak: peaks[i])
            if toSkip > 0 { toSkip -= 1; continue }
            outL.append(l)
            outR.append(r)
        }
        return (outL, outR)
    }

    /// Entrega las muestras que quedan en el detector y en la anticipación.
    func flush() -> ([Float], [Float]) {
        let zeros = [Float](repeating: 0, count: lookAhead + Self.detectorDelay)
        return process(zeros, zeros)
    }

    /// Retrasa la entrada `detectorDelay` muestras y da, para cada muestra retrasada `n`, su pico real
    /// (máximo de los dos canales de |x[n]| y de las intermedias de `n-1…n` y `n…n+1`).
    private func detect(_ left: [Float], _ right: [Float]) -> ([Float], [Float], [Float]) {
        let n = left.count
        guard n > 0 else { return ([], [], []) }
        let taps = LoudnessMeter.firTaps, center = LoudnessMeter.firCenter
        var delayed: [[Float]] = [[], []]
        // Pico de cada tramo `m…m+1` (|x[m]| y sus intermedias), con m la muestra retrasada.
        var span = [Double](repeating: 0, count: n)
        for (c, input) in [left, right].enumerated() {
            var ext = history[c]
            ext.reserveCapacity(ext.count + n)
            ext.append(contentsOf: input.map(Double.init))
            // La ventana `ext[w ..< w + taps]` está centrada en `ext[w + center]` (como en `LoudnessMeter`).
            let samples = Array(ext[center ..< center + n])
            delayed[c] = samples.map(Float.init)
            var interp = [Double](repeating: 0, count: n)
            span.withUnsafeMutableBufferPointer { s in
                interp.withUnsafeMutableBufferPointer { v in
                    let len = vDSP_Length(n)
                    vDSP_vabsD(samples, 1, v.baseAddress!, 1, len)
                    vDSP_vmaxD(s.baseAddress!, 1, v.baseAddress!, 1, s.baseAddress!, 1, len)
                    for phase in LoudnessMeter.phases {
                        vDSP_convD(ext, 1, phase, 1, v.baseAddress!, 1, len, vDSP_Length(taps))
                        vDSP_vabsD(v.baseAddress!, 1, v.baseAddress!, 1, len)
                        vDSP_vmaxD(s.baseAddress!, 1, v.baseAddress!, 1, s.baseAddress!, 1, len)
                    }
                }
            }
            history[c] = Array(ext.suffix(taps - 1))
        }
        var peaks = [Float](repeating: 0, count: n)
        var previous = previousSpanPeak
        for i in 0..<n {
            peaks[i] = Float(max(previous, span[i]))
            previous = span[i]
        }
        previousSpanPeak = previous
        return (delayed[0], delayed[1], peaks)
    }

    private func push(_ l: Float, _ r: Float, peak: Float) -> (Float, Float) {
        let j = position
        position += 1
        let need: Float = peak > threshold ? threshold / peak : 1
        while count > 0 && queueValue[(head + count - 1) % capacity] >= need { count -= 1 }
        let tail = (head + count) % capacity
        queueIndex[tail] = j
        queueValue[tail] = need
        count += 1
        while queueIndex[head] < j - lookAhead {
            head = (head + 1) % capacity
            count -= 1
        }
        let slot = j % lookAhead
        let oldL = delayL[slot], oldR = delayR[slot]
        delayL[slot] = l
        delayR[slot] = r
        let m = Double(queueValue[head])
        averageSum += m - average[averagePos]
        average[averagePos] = m
        averagePos = (averagePos + 1) % (lookAhead + 1)
        let g = averageSum / Double(lookAhead + 1)
        if g <= envelope { envelope = g } else { envelope += releaseCoefficient * (g - envelope) }
        minGain = min(minGain, envelope)
        return (Float(Double(oldL) * envelope), Float(Double(oldR) * envelope))
    }
}
