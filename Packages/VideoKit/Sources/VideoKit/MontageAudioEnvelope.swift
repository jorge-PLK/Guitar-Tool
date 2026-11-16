import Foundation

/// Ganancia de una pista de la vista previa en el tiempo (mini-spec Fase 7, «Transiciones» y «Compositor y vista
/// previa»): volumen × compuerta (fundidos de 80 ms dentro de cada tramo; el inverso para `.except`) × fundido
/// global de un compás. Lineal a trozos: `breakpoints` da los vértices para las rampas de `AVAudioMix`.
public enum MontageAudioEnvelope {
    /// Compuerta `.during` en `t`: trapecio por tramo, rampas de `audioFade` hacia dentro.
    static func during(_ spans: [MontageSpan], at t: Double) -> Double {
        let f = MontageStyle.audioFade
        var g = 0.0
        for s in spans where s.duration > 0 {
            let v = min((t - s.start) / f, (s.end - t) / f, 1)
            g = max(g, min(max(v, 0), 1))
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

    /// Ganancia lineal de `track` en el instante del tema `t` (el fundido global, el mismo que la imagen).
    public static func gain(_ track: MontageAudioTrack, at t: Double, timeline: MontageTimeline) -> Double {
        track.volume * gate(track.gate, at: t) * timeline.globalFade(at: t)
    }

    /// Vértices (tiempo del tema) entre los que la ganancia es lineal, dentro del segmento `k` del vídeo.
    static func breakpoints(_ track: MontageAudioTrack, timeline: MontageTimeline, segment k: Int) -> [Double] {
        let span = timeline.timeMap.segments[k], f = MontageStyle.audioFade, d = timeline.fadeDuration(segment: k)
        let fades = timeline.segmentFades(k)
        var t: [Double] = [span.start, span.end]
        if fades.fadeIn { t.append(span.start + d) }
        if fades.fadeOut { t.append(span.end - d) }
        switch track.gate {
        case .always: break
        case .during(let s), .except(let s):
            for x in s where x.duration > 0 {
                let mid = (x.start + x.end) / 2
                t += [x.start, min(x.start + f, mid), max(x.end - f, mid), x.end]
            }
        }
        return Set(t.filter { $0 >= span.start && $0 <= span.end }).sorted()
    }
}
