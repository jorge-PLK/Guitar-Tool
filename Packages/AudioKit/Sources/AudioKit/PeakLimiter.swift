import Foundation

/// Limitador de pico con anticipación para la normalización del montaje (mini-spec Fase 7, «Exportación»).
///
/// Streaming y sin distorsión por recorte: la reducción de ganancia es una curva continua, común a los dos
/// canales, que llega a su valor justo antes del pico.
/// 1. Reducción necesaria por muestra: `umbral / pico` (pico = máximo de |L| y |R|) si lo supera, 1 si no.
/// 2. Mínimo de la ventana de anticipación (`lookAheadSeconds`), de modo que la reducción ya está completa en el pico.
/// 3. Media móvil de la misma longitud: el ataque es una rampa dentro de la anticipación.
/// 4. Liberación exponencial (`releaseSeconds`); la ganancia final nunca supera a la de ataque, así que el
///    umbral se respeta en las muestras.
///
/// El audio sale retrasado `lookAhead` muestras (más otras tantas de relleno inicial que se descartan); `process` devuelve lo que ya se puede entregar y `flush`
/// el resto, de modo que la salida tiene tantas muestras como la entrada.
final class PeakLimiter {
    /// Anticipación y ataque (mini-spec Fase 7, ampliación: limitador).
    static let lookAheadSeconds = 0.005
    /// Liberación (mini-spec Fase 7, ampliación: limitador).
    static let releaseSeconds = 0.1

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
    /// Salidas por descartar: las de las `lookAhead` muestras de relleno con que arranca la señal.
    private var toSkip: Int
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
        // Arranca con `lookAhead` muestras de silencio previas, para que el ataque llegue completo a un pico
        // que esté en las primeras muestras.
        position = lookAhead
        toSkip = lookAhead
    }

    /// Reducción máxima aplicada, en dB (≥ 0).
    var maxReductionDB: Double { -20 * log10(minGain) }

    func process(_ left: [Float], _ right: [Float]) -> ([Float], [Float]) {
        var outL = [Float](), outR = [Float]()
        outL.reserveCapacity(left.count)
        outR.reserveCapacity(left.count)
        for i in 0..<left.count {
            guard let (l, r) = push(left[i], right[i]) else { continue }
            if toSkip > 0 { toSkip -= 1; continue }
            outL.append(l)
            outR.append(r)
        }
        return (outL, outR)
    }

    /// Entrega las muestras que quedan en la anticipación.
    func flush() -> ([Float], [Float]) {
        let zeros = [Float](repeating: 0, count: lookAhead)
        return process(zeros, zeros)
    }

    private func push(_ l: Float, _ r: Float) -> (Float, Float)? {
        let j = position
        position += 1
        let peak = max(abs(l), abs(r))
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
        guard j >= lookAhead else { return nil }
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
