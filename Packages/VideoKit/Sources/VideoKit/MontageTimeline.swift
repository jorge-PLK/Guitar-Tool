import CoreGraphics
import Foundation

/// Estado de un recuadro en un instante.
public struct MontageBoxState: Sendable, Equatable {
    public var partID: String
    /// Índice en `MontageTimeline.parts` (el compositor lo usa para la pista de vídeo).
    public var partIndex: Int
    public var name: String
    /// Hueco del layout en el lienzo (origen arriba a la izquierda), antes de la escala.
    public var rect: CGRect
    /// 0,92…1 en la entrada y la salida.
    public var scale: Double
    public var opacity: Double
    /// Sigma del desenfoque en unidades del lienzo.
    public var blur: Double
    /// Recorte del fotograma (normalizado, origen arriba a la izquierda), con la proporción de `rect`.
    public var crop: FramingBox

    /// `rect` escalado alrededor de su centro: donde se dibuja.
    public var displayRect: CGRect {
        let w = rect.width * scale, h = rect.height * scale
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }
}

/// Estado de un fotograma del montaje.
public struct MontageFrameState: Sendable, Equatable {
    /// En el orden de las partes (el último se dibuja encima).
    public var boxes: [MontageBoxState]
    /// Fundido global (0 negro, 1 imagen).
    public var fade: Double
    public var captionOpacity: Double
}

/// Función pura `t → estado` del montaje (mini-spec Fase 7, «Layouts» y «Transiciones»).
///
/// - Cada parte con imagen tiene **apariciones** `[entrada, salida)`: la entrada empieza `anticipation` antes del
///   inicio de presencia (o en su primer fotograma, si es más tarde) y la salida al final de la presencia. Las que se
///   solapan se juntan.
/// - Visibilidad `v`: sube con ease-in-out en `transition` desde la entrada y baja igual desde la salida;
///   escala `0,92 + 0,08·v`, opacidad `v`, desenfoque `maxBlur·(1 − v)`.
/// - Layout: están en él las partes entre su entrada y su salida. En cada cambio, los recuadros que siguen van de
///   donde estaban al hueco nuevo con ease-in-out en `transition`; el que entra aparece en su hueco; el que sale se
///   queda donde estaba mientras se desvanece.
/// - Plano único: la rítmica elegida, salvo durante las apariciones de las solistas; sus salidas y entradas coinciden
///   con las de la solista (fundido cruzado con la misma escala y desenfoque).
/// - Fundido global de un compás al principio y al final (si el plan lo pide) y rótulo los 5 primeros segundos.
public struct MontageTimeline: Sendable {
    public struct Part: Sendable, Equatable {
        public var id: String
        public var name: String
        public var isSolo: Bool
        public var presence: [MontageSpan]
        /// Primer instante (tiempo del tema) con imagen de la toma.
        public var firstImage: Double?
        public var frameSize: CGSize
        public var framing: MontageFraming

        public init(id: String, name: String, isSolo: Bool, presence: [MontageSpan], firstImage: Double?, frameSize: CGSize,
                    framing: MontageFraming = MontageFraming()) {
            self.id = id
            self.name = name
            self.isSolo = isSolo
            self.presence = presence
            self.firstImage = firstImage
            self.frameSize = frameSize
            self.framing = framing
        }
    }

    struct Appearance: Equatable {
        var enter: Double
        var exit: Double
    }

    /// Tramo entre dos cambios del layout.
    struct Segment {
        var time: Double
        var members: [Int]
        var from: [Int: CGRect]
        var to: [Int: CGRect]
        /// Hueco en que se quedan las partes que han salido.
        var frozen: [Int: CGRect]
    }

    public let canvas: CGSize
    public let layout: MontageLayoutKind
    /// Envolvente de los segmentos.
    public let span: MontageSpan
    /// Segmentos del vídeo y su correspondencia con el tiempo del tema.
    public let timeMap: MontageTimeMap
    public let barDuration: Double
    public let fadeIn: Bool
    public let fadeOut: Bool
    public let hasCaption: Bool
    /// Solo las partes con imagen (las demás no tienen recuadro).
    public let parts: [Part]
    let appearances: [[Appearance]]
    let segments: [Segment]

    /// `segments` (`nil`: solo `span`).
    public init(canvas: CGSize, layout: MontageLayoutKind, span: MontageSpan, segments: [MontageSpan]? = nil, barDuration: Double,
                fadeIn: Bool, fadeOut: Bool, parts: [Part], singleRhythmPartID: String? = nil, hasCaption: Bool = false) {
        self.canvas = canvas
        self.layout = layout
        let segs = segments ?? [span]
        timeMap = MontageTimeMap(segments: segs)
        self.span = MontageSpan(start: segs.first?.start ?? span.start, end: segs.last?.end ?? span.end)
        self.barDuration = barDuration
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
        self.hasCaption = hasCaption
        self.parts = parts
        var apps = parts.map(Self.appearances)
        if layout == .single { apps = Self.singleAppearances(parts: parts, apps: apps, rhythmID: singleRhythmPartID) }
        appearances = apps
        self.segments = Self.segments(apps, layout: layout, canvas: canvas)
    }

    /// Desde el plan, con lo que solo se sabe al abrir los vídeos: primer fotograma y tamaño de cada parte con imagen
    /// (las que no están en `images` no tienen recuadro).
    public init(plan: MontagePlan, images: [String: (firstImage: Double, frameSize: CGSize)]) {
        let parts = plan.parts.compactMap { p -> Part? in
            guard p.video != nil, let img = images[p.id] else { return nil }
            return Part(id: p.id, name: p.name, isSolo: p.isSolo, presence: p.presence, firstImage: img.firstImage,
                        frameSize: img.frameSize, framing: p.framing)
        }
        self.init(canvas: plan.canvas.size, layout: plan.layout, span: plan.span, segments: plan.segments, barDuration: plan.barDuration,
                  fadeIn: plan.fadeIn,
                  fadeOut: plan.fadeOut, parts: parts, singleRhythmPartID: plan.singleRhythmPartID, hasCaption: plan.caption != nil)
    }

    // MARK: Curvas

    /// Ease-in-out cúbica (la «curva tipo muelle» de la spec, sin rebote): derivada nula en los extremos.
    public static func ease(_ x: Double) -> Double {
        let u = min(max(x, 0), 1)
        return u < 0.5 ? 4 * u * u * u : 1 - pow(-2 * u + 2, 3) / 2
    }

    static func lerp(_ a: CGRect, _ b: CGRect, _ u: Double) -> CGRect {
        CGRect(x: a.minX + (b.minX - a.minX) * u, y: a.minY + (b.minY - a.minY) * u,
               width: a.width + (b.width - a.width) * u, height: a.height + (b.height - a.height) * u)
    }

    // MARK: Apariciones

    static func appearances(_ p: Part) -> [Appearance] {
        guard let first = p.firstImage else { return [] }
        let raw = p.presence.filter { $0.duration > 0 }.sorted { $0.start < $1.start }.compactMap { s -> Appearance? in
            let enter = max(s.start - MontageStyle.anticipation, first)
            return s.end > enter ? Appearance(enter: enter, exit: s.end) : nil
        }
        return merge(raw)
    }

    static func merge(_ list: [Appearance]) -> [Appearance] {
        var out: [Appearance] = []
        for a in list.sorted(by: { $0.enter < $1.enter }) {
            if let last = out.last, a.enter <= last.exit { out[out.count - 1].exit = max(last.exit, a.exit) } else { out.append(a) }
        }
        return out
    }

    /// Plano único: solistas con sus apariciones; la rítmica elegida, sus apariciones menos las de las solistas;
    /// el resto, fuera.
    static func singleAppearances(parts: [Part], apps: [[Appearance]], rhythmID: String?) -> [[Appearance]] {
        let rhythm = parts.firstIndex { $0.id == rhythmID } ?? parts.firstIndex { !$0.isSolo } ?? parts.indices.first
        let solos = merge(parts.indices.filter { parts[$0].isSolo && $0 != rhythm }.flatMap { apps[$0] })
        return parts.indices.map { i in
            if i == rhythm {
                var pieces = apps[i]
                for s in solos {
                    pieces = pieces.flatMap { a -> [Appearance] in
                        guard s.exit > a.enter, s.enter < a.exit else { return [a] }
                        var r: [Appearance] = []
                        if s.enter > a.enter { r.append(Appearance(enter: a.enter, exit: s.enter)) }
                        if s.exit < a.exit { r.append(Appearance(enter: s.exit, exit: a.exit)) }
                        return r
                    }
                }
                return pieces
            }
            return parts[i].isSolo ? apps[i] : []
        }
    }

    static func segments(_ apps: [[Appearance]], layout: MontageLayoutKind, canvas: CGSize) -> [Segment] {
        let events = Set(apps.flatMap { $0.flatMap { [$0.enter, $0.exit] } }).sorted()
        func members(at t: Double) -> [Int] {
            apps.indices.filter { i in apps[i].contains { $0.enter <= t && t < $0.exit } }
        }
        var out: [Segment] = []
        for e in events {
            let now = members(at: e)
            if let last = out.last, last.members == now { continue }
            var current: [Int: CGRect] = [:]
            var frozen = out.last?.frozen ?? [:]
            if let last = out.last {
                let u = ease((e - last.time) / MontageStyle.transition)
                for i in last.members { current[i] = lerp(last.from[i]!, last.to[i]!, u) }
                for i in last.members where !now.contains(i) { frozen[i] = current[i] }
            }
            let targets = MontageLayout.rects(layout, count: now.count, canvas: canvas)
            var from: [Int: CGRect] = [:], to: [Int: CGRect] = [:]
            for (k, i) in now.enumerated() {
                to[i] = targets[k]
                from[i] = current[i] ?? frozen[i] ?? targets[k]
                frozen[i] = nil
            }
            out.append(Segment(time: e, members: now, from: from, to: to, frozen: frozen))
        }
        return out
    }

    // MARK: Estado

    /// Visibilidad (0…1) de la parte `i` en `t`.
    public func visibility(part i: Int, at t: Double) -> Double {
        let d = MontageStyle.transition
        return appearances[i].reduce(0.0) { best, a in
            let rise = Self.ease((t - a.enter) / d), fall = 1 - Self.ease((t - a.exit) / d)
            return max(best, min(rise, fall))
        }
    }

    /// Duración de los fundidos del segmento `k`: un compás, o la mitad del segmento si dura menos de dos.
    public func fadeDuration(segment k: Int) -> Double {
        max(1e-6, min(barDuration, timeMap.segments[k].duration / 2))
    }

    /// ¿Entra y sale con fundido el segmento `k`? El primero según `fadeIn`, el último según `fadeOut`; en los
    /// cortes, siempre.
    public func segmentFades(_ k: Int) -> (fadeIn: Bool, fadeOut: Bool) {
        (k > 0 || fadeIn, k < timeMap.segments.count - 1 || fadeOut)
    }

    /// Fundido global en `t` (lineal), por segmento; fuera de los segmentos, 0.
    public func globalFade(at t: Double) -> Double {
        guard let k = timeMap.segmentIndex(songTime: t) else { return 0 }
        let s = timeMap.segments[k], d = fadeDuration(segment: k), fades = segmentFades(k)
        var f = 1.0
        if fades.fadeIn { f = min(f, (t - s.start) / d) }
        if fades.fadeOut { f = min(f, (s.end - t) / d) }
        return min(max(f, 0), 1)
    }

    /// Opacidad del rótulo: los `captionDuration` primeros segundos del vídeo con fundidos de `captionFade`.
    public func captionOpacity(at t: Double) -> Double {
        guard hasCaption else { return 0 }
        let x = timeMap.videoTime(songTime: t), f = MontageStyle.captionFade
        return min(max(min(x / f, (MontageStyle.captionDuration - x) / f), 0), 1)
    }

    /// Hueco del layout de la parte `i` en `t` (`nil` si nunca ha estado en él).
    func rect(part i: Int, at t: Double) -> CGRect? {
        guard let seg = segments.last(where: { $0.time <= t }) else { return nil }
        if seg.members.contains(i) {
            return Self.lerp(seg.from[i]!, seg.to[i]!, Self.ease((t - seg.time) / MontageStyle.transition))
        }
        return seg.frozen[i]
    }

    public func state(at t: Double) -> MontageFrameState {
        var boxes: [MontageBoxState] = []
        for (i, p) in parts.enumerated() {
            let v = visibility(part: i, at: t)
            guard v > 0, let r = rect(part: i, at: t), r.width > 0, r.height > 0 else { continue }
            let crop = GuitarFramer.crop(box: p.framing.box(at: t), frameSize: p.frameSize, aspect: Double(r.width / r.height))
            boxes.append(MontageBoxState(partID: p.id, partIndex: i, name: p.name, rect: r,
                                         scale: MontageStyle.entryScale + (1 - MontageStyle.entryScale) * v, opacity: v,
                                         blur: MontageStyle.maxBlur * (1 - v), crop: crop))
        }
        return MontageFrameState(boxes: boxes, fade: globalFade(at: t), captionOpacity: captionOpacity(at: t))
    }
}
