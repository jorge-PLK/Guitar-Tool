#if canImport(CoreGraphics)
import CoreGraphics
#endif
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
    /// «Mantener aspect ratio de vídeo»: el fotograma entero (`crop` = `.full`) ajustado dentro del recuadro, con el
    /// resto relleno de la misma toma ampliada, difuminada y oscurecida.
    public var fit: Bool = false
    /// Fundido a negro de la imagen al acabar la toma (1 imagen, 0 negro; `MontageTimeline.imageBrightness`). Se aplica
    /// a todo el recuadro: imagen, relleno difuminado y nombre.
    public var brightness: Double = 1

    /// `rect` escalado alrededor de su centro: donde se dibuja.
    public var displayRect: CGRect {
        let w = rect.width * scale, h = rect.height * scale
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }
}

/// Tramo del plano único con la parte que se ve (`MontageTimeline.singleShots`).
public struct MontageShot: Sendable, Equatable {
    public var span: MontageSpan
    /// `nil`: no se ve ninguna parte.
    public var partID: String?
    /// La imagen de la parte ya ha acabado (fundido a negro y negro).
    public var black: Bool

    public init(span: MontageSpan, partID: String?, black: Bool = false) {
        self.span = span
        self.partID = partID
        self.black = black
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
///   con las de la solista (fundido cruzado con la misma escala y desenfoque). Encima, los cortes libres. Una parte
///   solo se ve donde su toma tiene imagen (`singleAppearances`).
/// - Toma que acaba antes que su recuadro: fundido a negro de `MontageStyle.endFade` desde su última imagen y negro
///   hasta que el recuadro sale (`imageBrightness`), en vez de congelar el último fotograma.
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
        /// Tramos (tiempo del tema) en que la toma tiene imagen, para los cortes libres del plano único (`nil`: desde
        /// `firstImage` hasta el final de la presencia, que es lo que se sabe sin abrir el vídeo).
        public var images: [MontageSpan]?

        public init(id: String, name: String, isSolo: Bool, presence: [MontageSpan], firstImage: Double?, frameSize: CGSize,
                    framing: MontageFraming = MontageFraming(), images: [MontageSpan]? = nil) {
            self.id = id
            self.name = name
            self.isSolo = isSolo
            self.presence = presence
            self.firstImage = firstImage
            self.frameSize = frameSize
            self.framing = framing
            self.images = images
        }

        /// Cobertura en el plano único (decisión de Jorge del 17/11/2026: una guitarra solo se ve donde tiene toma):
        /// los tramos con imagen, cada uno salvo el último acortado en `transition` para que la salida no se quede sin
        /// fotogramas (tras el último, el compositor congela su último fotograma `transition` segundos, lo que dura la
        /// salida o el fundido a negro).
        func coverage() -> [MontageSpan] {
            guard let first = firstImage else { return [] }
            guard let images else {
                let end = presence.map(\.end).max() ?? first
                return end > first ? [MontageSpan(start: first, end: end)] : []
            }
            let sorted = images.filter { $0.duration > 0 }.sorted { $0.start < $1.start }
            var merged: [MontageSpan] = []
            for s in sorted {
                if let last = merged.last, s.start <= last.end { merged[merged.count - 1].end = max(last.end, s.end) } else { merged.append(s) }
            }
            return merged.enumerated().compactMap { k, s in
                let end = k == merged.count - 1 ? s.end : s.end - MontageStyle.transition
                return end > s.start ? MontageSpan(start: s.start, end: end) : nil
            }
        }

        /// Última imagen de la toma (tiempo del tema; `nil` sin imagen): desde ahí, fundido a negro.
        var imageEnd: Double? { coverage().last?.end }
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
    /// Nombre de la parte en cada recuadro (`MontagePlan.showPartLabels`).
    public let showPartLabels: Bool
    /// `MontagePlan.keepVideoAspect` ya restringido a los layouts en que actúa (apilado y plano único).
    public let keepVideoAspect: Bool
    /// Solo las partes con imagen (las demás no tienen recuadro).
    public let parts: [Part]
    let appearances: [[Appearance]]
    let segments: [Segment]
    /// Por parte, instante en que empieza su fundido a negro (`nil`: su recuadro sale antes de quedarse sin imagen).
    let darkFrom: [Double?]

    /// `segments` (`nil`: solo `span`). `singleCuts` solo cuenta en el plano único.
    public init(canvas: CGSize, layout: MontageLayoutKind, span: MontageSpan, segments: [MontageSpan]? = nil, barDuration: Double,
                fadeIn: Bool, fadeOut: Bool, parts: [Part], singleRhythmPartID: String? = nil, hasCaption: Bool = false,
                showPartLabels: Bool = true, keepVideoAspect: Bool = false, singleCuts: [MontageCut] = []) {
        self.canvas = canvas
        self.layout = layout
        self.showPartLabels = showPartLabels
        self.keepVideoAspect = keepVideoAspect && layout.honorsVideoAspect
        let segs = segments ?? [span]
        timeMap = MontageTimeMap(segments: segs)
        self.span = MontageSpan(start: segs.first?.start ?? span.start, end: segs.last?.end ?? span.end)
        self.barDuration = barDuration
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
        self.hasCaption = hasCaption
        self.parts = parts
        var apps = parts.map(Self.appearances)
        if layout.isSingle {
            apps = Self.singleAppearances(parts: parts, apps: apps, rhythmID: singleRhythmPartID, cuts: singleCuts, end: self.span.end)
        }
        appearances = apps
        self.segments = Self.segments(apps, layout: layout, canvas: canvas)
        darkFrom = parts.indices.map { i in
            guard let e = parts[i].imageEnd, apps[i].contains(where: { $0.exit > e + MontageStyle.endFadeTolerance }) else { return nil }
            return e
        }
    }

    /// Desde el plan, con lo que solo se sabe al abrir los vídeos: primer fotograma y tamaño de cada parte con imagen
    /// (las que no están en `images` no tienen recuadro) y, para los cortes libres, sus tramos con imagen
    /// (`imageSpans`; sin entrada, desde el primer fotograma sin final).
    public init(plan: MontagePlan, images: [String: (firstImage: Double, frameSize: CGSize)], imageSpans: [String: [MontageSpan]] = [:]) {
        let parts = plan.parts.compactMap { p -> Part? in
            guard p.video != nil, let img = images[p.id] else { return nil }
            return Part(id: p.id, name: p.name, isSolo: p.isSolo, presence: p.presence, firstImage: img.firstImage,
                        frameSize: img.frameSize, framing: p.framing, images: imageSpans[p.id])
        }
        self.init(canvas: plan.canvas.size, layout: plan.layout, span: plan.span, segments: plan.segments, barDuration: plan.barDuration,
                  fadeIn: plan.fadeIn,
                  fadeOut: plan.fadeOut, parts: parts, singleRhythmPartID: plan.singleRhythmPartID, hasCaption: plan.caption != nil,
                  showPartLabels: plan.showPartLabels, keepVideoAspect: plan.keepVideoAspect, singleCuts: plan.singleCuts)
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

    /// Plano único (cortes libres y cobertura: peticiones de Jorge del 17/11/2026). Una parte solo se ve donde su toma
    /// tiene imagen (`Part.coverage`). En cada instante manda, por orden:
    /// 1. El corte libre vigente con parte, si esa parte tiene imagen ahí. El corte `k` manda en
    ///    `[tₖ − anticipation, tₖ₊₁ − anticipation)`: el fundido cruzado (el mismo que rítmica ↔ solista) empieza
    ///    `anticipation` antes del corte y la parte nueva está completa en el corte, como la entrada de la solista.
    ///    Donde su toma no cubre (empieza tarde o acaba dentro del tramo), manda el automático.
    /// 2. El automático, solo entre partes con imagen en ese instante y dentro de sus apariciones (`apps`, las de su
    ///    presencia: se ve quien suena): las solistas; si no, la rítmica elegida; si no, la primera parte no solista.
    /// 3. Si nadie tiene imagen: la parte que se veía sigue en pantalla si su toma ya acabó (fundido a negro y negro,
    ///    `imageBrightness`); en un hueco interior de su imagen, o si no se veía nadie, ninguna.
    /// `end`: final del vídeo (tiempo del tema), hasta donde sigue en negro la última parte.
    static func singleAppearances(parts: [Part], apps: [[Appearance]], rhythmID: String?, cuts: [MontageCut], end: Double) -> [[Appearance]] {
        let rhythm = parts.firstIndex { $0.id == rhythmID } ?? parts.firstIndex { !$0.isSolo } ?? parts.indices.first
        let coverage = parts.map { $0.coverage() }
        let imageEnd = parts.map(\.imageEnd)
        let lead = MontageStyle.anticipation
        let cuts = MontageCut.normalized(cuts)
        // Tramos mandados por los cortes, ya recortados a la cobertura de su parte: (parte, desde, hasta).
        var forced: [(part: Int, span: MontageSpan)] = []
        for (k, c) in cuts.enumerated() {
            guard let id = c.partID, let i = parts.firstIndex(where: { $0.id == id }) else { continue }
            let a = c.time - lead, b = k + 1 < cuts.count ? cuts[k + 1].time - lead : .infinity
            for img in coverage[i] {
                let s = MontageSpan(start: max(a, img.start), end: min(b, img.end))
                if s.duration > 0 { forced.append((i, s)) }
            }
        }
        var edges: [Double] = [end]
        for list in apps { for x in list { edges += [x.enter, x.exit] } }
        for list in coverage { for s in list { edges += [s.start, s.end] } }
        for f in forced { edges += [f.span.start, f.span.end] }
        let bounds: [Double] = Set(edges).filter(\.isFinite).sorted()
        func covered(_ i: Int, _ t: Double) -> Bool { coverage[i].contains { $0.contains(t) } }
        func present(_ i: Int, _ t: Double) -> Bool { apps[i].contains { $0.enter <= t && t < $0.exit } && covered(i, t) }
        func automatic(_ t: Double) -> [Int] {
            let solos = parts.indices.filter { parts[$0].isSolo && $0 != rhythm && present($0, t) }
            if !solos.isEmpty { return solos }
            if let rhythm, present(rhythm, t) { return [rhythm] }
            return parts.indices.first { !parts[$0].isSolo && present($0, t) }.map { [$0] } ?? []
        }
        var out = Array(repeating: [Appearance](), count: parts.count)
        func add(_ i: Int, _ a: Double, _ b: Double) {
            if let last = out[i].last, last.exit >= a { out[i][out[i].count - 1].exit = max(last.exit, b) } else { out[i].append(Appearance(enter: a, exit: b)) }
        }
        // Tramos entre bordes consecutivos (antes del primero y tras el último, nadie; `end` es uno de ellos).
        var previous: [Int] = []
        for (a, b) in zip(bounds, bounds.dropFirst()) {
            let mid = (a + b) / 2
            var now = forced.first(where: { $0.span.contains(mid) }).map { [$0.part] } ?? automatic(mid)
            if now.isEmpty { now = previous.filter { i in imageEnd[i].map { $0 <= a + 1e-9 } ?? false } }
            for i in now { add(i, a, b) }
            previous = now
        }
        return out
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

    /// Brillo de la imagen de la parte `i` en `t` (decisión de Jorge del 17/11/2026, «toma que acaba antes que el
    /// plan»): 1 hasta su última imagen y, si su recuadro sigue en pantalla después, fundido lineal a negro en
    /// `MontageStyle.endFade` (sobre el último fotograma, que el compositor retiene ese tiempo) y 0 hasta que sale.
    public func imageBrightness(part i: Int, at t: Double) -> Double {
        guard let e = darkFrom[i] else { return 1 }
        return min(max(1 - (t - e) / MontageStyle.endFade, 0), 1)
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

    /// Fundido global de la imagen en `t` (lineal), por segmento; fuera de los segmentos, 0. El del audio, en seno al
    /// cuadrado como la exportación, es `MontageAudioEnvelope.globalFade`.
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

    /// Plano único: quién se ve en cada tramo de `span` (carril «Plano»). En un fundido cruzado cuenta la parte que
    /// entra; `black`, desde la última imagen de una parte que sigue en pantalla (fundido a negro y negro). Tramos
    /// contiguos iguales, juntos; sin nadie, `partID` nil.
    public func singleShots() -> [MontageShot] {
        var edges = [span.start, span.end]
        for list in appearances { for a in list { edges += [a.enter, a.exit] } }
        edges += darkFrom.compactMap { $0 }
        let bounds = Set(edges).filter { $0.isFinite && $0 >= span.start && $0 <= span.end }.sorted()
        var out: [MontageShot] = []
        for (a, b) in zip(bounds, bounds.dropFirst()) {
            let mid = (a + b) / 2
            // La que entró más tarde (la de encima en el fundido cruzado).
            let on = parts.indices.compactMap { i in appearances[i].first { $0.enter <= mid && mid < $0.exit }.map { (i, $0.enter) } }
                .max { $0.1 < $1.1 }?.0
            let shot = MontageShot(span: MontageSpan(start: a, end: b), partID: on.map { parts[$0].id },
                                   black: on.flatMap { darkFrom[$0] }.map { $0 <= a } ?? false)
            if let last = out.last, last.partID == shot.partID, last.black == shot.black, last.span.end == a {
                out[out.count - 1].span.end = b
            } else {
                out.append(shot)
            }
        }
        return out
    }

    public func state(at t: Double) -> MontageFrameState {
        var boxes: [MontageBoxState] = []
        for (i, p) in parts.enumerated() {
            let v = visibility(part: i, at: t)
            guard v > 0, let r = rect(part: i, at: t), r.width > 0, r.height > 0 else { continue }
            // Con «Mantener aspect ratio» no hay encuadre de guitarra: el fotograma entero, ajustado por el compositor.
            let crop = keepVideoAspect ? .full
                : GuitarFramer.crop(box: p.framing.box(at: t), frameSize: p.frameSize, aspect: Double(r.width / r.height))
            boxes.append(MontageBoxState(partID: p.id, partIndex: i, name: p.name, rect: r,
                                         scale: MontageStyle.entryScale + (1 - MontageStyle.entryScale) * v, opacity: v,
                                         blur: MontageStyle.maxBlur * (1 - v), crop: crop, fit: keepVideoAspect,
                                         brightness: imageBrightness(part: i, at: t)))
        }
        return MontageFrameState(boxes: boxes, fade: globalFade(at: t), captionOpacity: captionOpacity(at: t))
    }
}
