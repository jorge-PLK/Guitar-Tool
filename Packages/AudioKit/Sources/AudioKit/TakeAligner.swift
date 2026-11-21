import NativeDSP
import Foundation

/// Retardo del rig medido en una toma (mini-spec Fase 3, «Alineado con el backing» 3).
public struct RigDelayEstimate: Sendable, Equatable {
    /// Valor a usar: el medido si es fiable; si no, el último fiable.
    public var samples: Double
    /// Pico encontrado en la ventana (aunque no sea fiable), en muestras con decimales.
    public var measuredSamples: Double
    /// Correlación normalizada en el pico (1 = mismas envolventes desplazadas).
    public var correlation: Double
    /// Mayor pico secundario de la ventana frente al principal.
    public var secondaryRatio: Double
    public var reliable: Bool
}

/// Alineado de tomas (mini-spec Fase 3, «Alineado con el backing»): retardo del rig por correlación de
/// envolventes, desplazamiento entero y re-desplazamiento al llegar la calibración.
public enum TakeAligner {
    /// Ventana del retardo del rig (mini-spec Fase 3, «Alineado» 3).
    public static let rigWindowSeconds = 0.020
    /// Envolvente: |x| con paso bajo de 2 kHz (FIR de 129 coeficientes) y derivada. La derivada quita la
    /// parte lenta (la caída de cada nota), que aplana la correlación en 20 ms; el pico queda en el
    /// ataque. Decisión propia: la spec dice «envolventes» sin más detalle.
    static let envelopeCutoffHz = 2_000.0
    static let envelopeFilterHalf = 64
    /// Decisión propia (la spec dice «si el pico no es claro», sin número): fiable si la correlación
    /// normalizada del pico llega a 0,5, ningún otro pico de la ventana pasa del 60 % del principal y el
    /// pico es un máximo local (no un borde de la ventana).
    public static let minCorrelation = 0.5
    public static let maxSecondaryRatio = 0.6
    /// Mínimo de señal para medir: 0,5 s.
    static let minSeconds = 0.5

    /// Envolvente derivada que se correlaciona.
    static func envelope(_ x: [Float], sampleRate: Double) -> [Float] {
        var a = [Float](repeating: 0, count: x.count)
        DSP.vabs(x, 1, &a, 1, DSPLength(x.count))
        let h = SignalMath.lowpass(cutoffHz: envelopeCutoffHz, sampleRate: sampleRate, half: envelopeFilterHalf)
        let e = SignalMath.filterSymmetric(a, h)
        var d = [Float](repeating: 0, count: e.count)
        for i in 1..<max(1, e.count) { d[i] = e[i] - e[i - 1] }
        return d
    }

    /// Retardo de `guitar` respecto a `reference` (misma línea de tiempo) en `[0, 20 ms]`.
    public static func rigDelay(guitar: [Float], reference: [Float], sampleRate: Double, lastReliable: Double) -> RigDelayEstimate {
        let w = Int((rigWindowSeconds * sampleRate).rounded())
        let m = SignalMath.sincHalfWidth + 2
        let n = min(guitar.count, reference.count)
        let span = w + 2 * m
        let unreliable = RigDelayEstimate(samples: lastReliable, measuredSamples: .nan, correlation: 0, secondaryRatio: 1, reliable: false)
        guard n - span >= Int(minSeconds * sampleRate) else { return unreliable }
        let eg = envelope(Array(guitar[0..<n]), sampleRate: sampleRate)
        let ef = envelope(Array(reference[0..<n]), sampleRate: sampleRate)
        let p = n - span
        // r[i] = Σ eg[i + j]·ef[m + j], j < p  →  retardo i − m.
        var r = [Float](repeating: 0, count: span + 1)
        eg.withUnsafeBufferPointer { g in
            ef.withUnsafeBufferPointer { f in
                DSP.conv(g.baseAddress!, 1, f.baseAddress! + m, 1, &r, 1, DSPLength(span + 1), DSPLength(p))
            }
        }
        var eG: Float = 0, eF: Float = 0
        eg.withUnsafeBufferPointer { DSP.svesq($0.baseAddress! + m, 1, &eG, DSPLength(p)) }
        ef.withUnsafeBufferPointer { DSP.svesq($0.baseAddress! + m, 1, &eF, DSPLength(p)) }
        let norm = (Double(eG) * Double(eF)).squareRoot()
        guard norm > 0 else { return unreliable }
        let rd = r.map { Double($0) / norm }

        var k = m
        for i in m...(m + w) where rd[i] > rd[k] { k = i }
        let isLocalMax = rd[k] >= rd[k - 1] && rd[k] >= rd[k + 1]
        // Lóbulo principal: hasta el primer cruce por cero a cada lado.
        var a = k, b = k
        while a > 0 && rd[a - 1] > 0 { a -= 1 }
        while b < rd.count - 1 && rd[b + 1] > 0 { b += 1 }
        var secondary = 0.0
        for i in m...(m + w) where (i < a || i > b) && rd[i] >= rd[i - 1] && rd[i] >= rd[i + 1] {
            secondary = max(secondary, rd[i])
        }
        let peak = rd[k]
        let ratio = peak > 0 ? secondary / peak : 1
        let measured = SignalMath.refinePeak(rd, near: k) - Double(m)
        let reliable = isLocalMax && peak >= minCorrelation && ratio <= maxSecondaryRatio
        return RigDelayEstimate(samples: reliable ? measured : lastReliable, measuredSamples: measured,
                                correlation: peak, secondaryRatio: ratio, reliable: reliable)
    }

    /// Desplazamiento entero de una toma: latencia más retardo del rig, redondeado; el resto (≤ media
    /// muestra) se ignora (mini-spec Fase 3, «Alineado» 4).
    public static func shiftSamples(latency: Double, rigDelay: Double?) -> Int {
        Int((latency + (rigDelay ?? 0)).rounded())
    }

    /// Vuelve a desplazar una toma grabada sin calibrar cuando llega una calibración válida con su misma
    /// clave (mini-spec Fase 3, «Calibración de latencia» · Sin calibrar). Cambia `songStart`; solo reescribe
    /// el fichero si el nuevo inicio cae antes del principio del tema (recorta lo que sobra).
    /// Devuelve `nil` si no toca (toma ya calibrada, calibración no válida o de otra clave).
    ///
    /// Sin calibrar no se conoce el canal de referencia y no se grabó: se usa la latencia calibrada de
    /// `guitarIn` (que incluye el retardo del rig que había al calibrar) y la toma queda sin retardo del rig.
    ///
    /// Convención de unidades: las latencias (`latencySamples`, la de `calibration`) van en muestras de
    /// `calibrationKey.sampleRate` (el dispositivo al grabar); `take.sampleRate`, `songStartFrame` y
    /// `frameCount` van en muestras del fichero. El cambio de latencia se pasa a segundos y de ahí a muestras
    /// del fichero (redondeo ≤ media muestra). Si las dos frecuencias coinciden (todas las tomas grabadas hasta
    /// hoy) la cuenta es entera y da exactamente lo mismo que antes. El fichero no se remuestrea nunca.
    public static func reshift(_ take: RecordedTake, file: URL, with calibration: LatencyCalibrationResult) throws -> RecordedTake? {
        guard !take.latencyCalibrated, calibration.applies(to: take.calibrationKey) else { return nil }
        let newLatency = calibration.latencySamples
        let delta = shiftSamples(latency: newLatency, rigDelay: nil) - take.shiftSamples
        let latencyRate = take.calibrationKey.sampleRate
        let deltaFrames: Int64
        if abs(latencyRate - take.sampleRate) < 0.5 {
            deltaFrames = Int64(delta)
        } else {
            deltaFrames = Int64((Double(delta) * take.sampleRate / latencyRate).rounded())
        }
        var start = take.songStartFrame - deltaFrames
        var out = take
        if start < 0 {
            let drop = Int(-start)
            var channels = try TakeFile.read(file)
            for c in channels.indices { channels[c] = Array(channels[c].dropFirst(drop)) }
            try TakeFile.write(channels, sampleRate: take.sampleRate, to: file)
            out.frameCount = channels.first?.count ?? 0
            start = 0
        }
        out.songStart = Double(start) / take.sampleRate
        out.latencySamples = newLatency
        out.rigDelaySamples = nil
        out.rigDelayReliable = nil
        out.latencyCalibrated = true
        return out
    }
}
