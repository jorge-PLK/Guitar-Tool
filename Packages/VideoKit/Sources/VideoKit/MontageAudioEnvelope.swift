import Foundation

/// Ganancia de una pista de la vista previa en el tiempo (mini-spec Fase 7, «Transiciones» y «Compositor y vista
/// previa»): volumen × compuerta (fundidos de 80 ms dentro de cada tramo; el inverso para `.except`) × fundido
/// global de un compás. Compuerta y fundido global usan la misma curva que la exportación (seno al cuadrado,
/// `MontageMixer` de AudioKit); `breakpoints` los parte en rampas lineales (`fadeSteps`, `globalFadeSteps`) para
/// `AVAudioMix`.
public enum MontageAudioEnvelope {
    /// Rampas lineales de `AVAudioMix` con que la vista previa aproxima cada fundido de 80 ms (5 ms cada una).
    /// Error frente al seno al cuadrado ≤ π²/(16·N²) ≈ 0,0024 de ganancia (`MontageTimelineTests`).
    static let fadeSteps = 16

    /// Curva de fundido de la exportación (`MontageMixer.ramp`): seno al cuadrado, derivada 0 en los extremos.
    static func ramp(_ x: Double) -> Double {
        let s = sin(Double.pi / 2 * min(max(x, 0), 1))
        return s * s
    }

    /// Compuerta `.during` en `t`: por tramo, rampa de entrada × rampa de salida de `audioFade` hacia dentro (como
    /// `MontageMixer.spanEnvelope`); entre tramos, la mayor.
    static func during(_ spans: [MontageSpan], at t: Double) -> Double {
        let f = MontageStyle.audioFade
        var g = 0.0
        for s in spans where s.duration > 0 && t >= s.start && t <= s.end {
            g = max(g, ramp((t - s.start) / f) * ramp((s.end - t) / f))
        }
        return g
    }

    static func gate(_ gate: MontageAudioGate, at t: Double) -> Double {
        switch gate {
        case .always: 1
        case .during(let s): during(s, at: t)
        case .except(let s): 1 - during(s, at: t)
        }
    }

    /// Rampas lineales con que la vista previa aproxima cada fundido global de un compás (entrada, salida y cortes).
    /// El error de interpolar el seno al cuadrado con N rampas es π²/(16·N²) de ganancia sea cual sea la duración del
    /// fundido, así que con las mismas 16 que el de 80 ms queda en ≈ 0,0024 (≤ 0,005 pedido por Jorge el 16/11/2026);
    /// a 2 s por compás, rampas de 125 ms. Donde coincide con un fundido de 80 ms, los vértices de este (cada 5 ms)
    /// también parten el global y el producto queda en la misma cota.
    static let globalFadeSteps = 16

    /// Fundido global del audio en `t`, como la exportación (`MontageMixer.globalFade`): por segmento, rampa de
    /// entrada × rampa de salida en seno al cuadrado sobre `fadeDuration` (un compás, como mucho la mitad del
    /// segmento); fuera de los segmentos, 0. La imagen sigue con el lineal (`MontageTimeline.globalFade`).
    static func globalFade(at t: Double, timeline: MontageTimeline) -> Double {
        guard let k = timeline.timeMap.segmentIndex(songTime: t) else { return 0 }
        let s = timeline.timeMap.segments[k], d = timeline.fadeDuration(segment: k), fades = timeline.segmentFades(k)
        var g = 1.0
        if fades.fadeIn { g *= ramp((t - s.start) / d) }
        if fades.fadeOut { g *= ramp((s.end - t) / d) }
        return g
    }

    /// Ganancia lineal de `track` en el instante del tema `t`.
    public static func gain(_ track: MontageAudioTrack, at t: Double, timeline: MontageTimeline) -> Double {
        track.volume * gate(track.gate, at: t) * globalFade(at: t, timeline: timeline)
    }

    /// Vértices (tiempo del tema) de la aproximación lineal a trozos de la ganancia, dentro del segmento `k` del
    /// vídeo: `globalFadeSteps` + 1 por cada fundido global y `fadeSteps` + 1 por cada fundido de 80 ms (más el centro
    /// de tramos cortos).
    static func breakpoints(_ track: MontageAudioTrack, timeline: MontageTimeline, segment k: Int) -> [Double] {
        let span = timeline.timeMap.segments[k], f = MontageStyle.audioFade, d = timeline.fadeDuration(segment: k)
        let fades = timeline.segmentFades(k)
        var t: [Double] = [span.start, span.end]
        for i in 0...globalFadeSteps {
            let step = d * Double(i) / Double(globalFadeSteps)
            if fades.fadeIn { t.append(span.start + step) }
            if fades.fadeOut { t.append(span.end - step) }
        }
        switch track.gate {
        case .always: break
        case .during(let s), .except(let s):
            for x in s where x.duration > 0 {
                t.append((x.start + x.end) / 2)
                for i in 0...fadeSteps {
                    let step = f * Double(i) / Double(fadeSteps)
                    t += [min(x.start + step, x.end), max(x.end - step, x.start)]
                }
            }
        }
        return Set(t.filter { $0 >= span.start && $0 <= span.end }).sorted()
    }
}
