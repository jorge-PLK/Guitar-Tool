import CoreGraphics
import Foundation

// Entrada del montaje (mini-spec Fase 7, «Montaje»). VideoKit no depende de Store ni de AudioKit: la app traduce
// `Project.recording`, `Project.montage` y las secciones a estos tipos. Todos los tiempos son del tema (s) salvo
// que se diga otra cosa.

/// Tramo en tiempo del tema.
public struct MontageSpan: Codable, Sendable, Equatable, Hashable {
    public var start: Double
    public var end: Double

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }

    public var duration: Double { max(0, end - start) }
    public func contains(_ t: Double) -> Bool { t >= start && t < end }
}

/// Lienzo del montaje (mini-spec, «Layouts»): 1920 × 1080 o 1080 × 1920, escalado a la resolución de exportación.
public struct MontageCanvas: Codable, Sendable, Equatable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public static let landscape = MontageCanvas(width: 1920, height: 1080)
    public static let portrait = MontageCanvas(width: 1080, height: 1920)
    public var size: CGSize { CGSize(width: width, height: height) }
}

/// Los cuatro layouts (mini-spec, tabla de «Layouts»; mismos nombres que `MontageState.layout` de Store).
public enum MontageLayoutKind: String, Codable, Sendable, CaseIterable {
    case side, grid, stack, single
}

/// Caja normalizada sobre el fotograma (0…1), **origen arriba a la izquierda** (como la pantalla, no como Vision).
public struct FramingBox: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let full = FramingBox(x: 0, y: 0, width: 1, height: 1)
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
}

/// Un punto de la trayectoria de encuadre.
public struct FramingKey: Codable, Sendable, Equatable {
    public var time: Double
    public var box: FramingBox

    public init(time: Double, box: FramingBox) {
        self.time = time
        self.box = box
    }
}

/// Resultado del análisis de encuadre de una toma (`cache/framing/<takeID>.json`, mini-spec «Encuadre»).
public struct FramingAnalysis: Codable, Sendable, Equatable {
    /// Versión del formato y del algoritmo: si cambia, la app regenera la caché.
    public static let currentVersion = 1
    public var version: Int
    /// Huella de la toma y sus punches (`GuitarFramer.fingerprint`); si no coincide, se regenera.
    public var fingerprint: String
    /// Tamaño del fotograma analizado (px).
    public var frameWidth: Int
    public var frameHeight: Int
    /// Fotogramas muestreados y con pose detectada.
    public var samples: Int
    public var detected: Int
    /// Caja fija: mediana de las cajas detectadas (`nil`: sin detección → fotograma entero).
    public var fixed: FramingBox?
    /// Trayectoria suavizada con los huecos interpolados, en tiempo del tema (vacía sin detección).
    public var track: [FramingKey]

    public init(version: Int = FramingAnalysis.currentVersion, fingerprint: String, frameWidth: Int, frameHeight: Int,
                samples: Int, detected: Int, fixed: FramingBox?, track: [FramingKey]) {
        self.version = version
        self.fingerprint = fingerprint
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        self.samples = samples
        self.detected = detected
        self.fixed = fixed
        self.track = track
    }

    /// Caja de la trayectoria en `t` (interpolación lineal; fuera, el extremo más cercano).
    public func trackBox(at t: Double) -> FramingBox? {
        guard let first = track.first, let last = track.last else { return nil }
        if t <= first.time { return first.box }
        if t >= last.time { return last.box }
        var lo = 0, hi = track.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if track[mid].time <= t { lo = mid } else { hi = mid }
        }
        let a = track[lo], b = track[hi]
        let u = b.time > a.time ? (t - a.time) / (b.time - a.time) : 0
        func mix(_ p: Double, _ q: Double) -> Double { p + (q - p) * u }
        return FramingBox(x: mix(a.box.x, b.box.x), y: mix(a.box.y, b.box.y),
                          width: mix(a.box.width, b.box.width), height: mix(a.box.height, b.box.height))
    }
}

/// Encuadre de una toma: modo, análisis y ajuste manual (`TakeFraming` de Store más el análisis de la caché).
public struct MontageFraming: Codable, Sendable, Equatable {
    public enum Mode: String, Codable, Sendable {
        case fixed, follow
    }

    public var mode: Mode
    public var analysis: FramingAnalysis?
    /// Fijo: caja manual que sustituye a la automática.
    public var manualBox: FramingBox?
    /// Seguir: zoom sobre la trayectoria (1 = automático; 2 = caja la mitad de grande).
    public var followZoom: Double
    /// Seguir: desplazamiento de la caja, en fracción del fotograma.
    public var followOffsetX: Double
    public var followOffsetY: Double

    public init(mode: Mode = .fixed, analysis: FramingAnalysis? = nil, manualBox: FramingBox? = nil, followZoom: Double = 1,
                followOffsetX: Double = 0, followOffsetY: Double = 0) {
        self.mode = mode
        self.analysis = analysis
        self.manualBox = manualBox
        self.followZoom = followZoom
        self.followOffsetX = followOffsetX
        self.followOffsetY = followOffsetY
    }

    /// Caja de la guitarra en `t` con el ajuste manual (`nil`: sin detección → fotograma entero, centrado).
    public func box(at songTime: Double) -> FramingBox? {
        switch mode {
        case .fixed:
            return manualBox ?? analysis?.fixed
        case .follow:
            guard let b = analysis?.trackBox(at: songTime) else { return nil }
            let z = followZoom > 0 ? followZoom : 1
            let w = b.width / z, h = b.height / z
            return FramingBox(x: b.midX + followOffsetX - w / 2, y: b.midY + followOffsetY - h / 2, width: w, height: h)
        }
    }
}

/// Vídeo de la toma de una parte: fichero base con su desfase y punches (como `TakePreview`).
public struct MontagePartVideo: Codable, Sendable, Equatable {
    /// `video.mov` de la toma (`nil`: la base se grabó sin cámara; solo los punches con vídeo tienen imagen).
    public var url: URL?
    /// Desfase manual de la base (positivo: su imagen llega tarde).
    public var videoOffset: Double
    public var punches: [PreviewPunch]
    /// Tramo del tema que cubre la toma (desde su `songStart`, margen incluido, hasta su final).
    public var take: MontageSpan

    public init(url: URL?, videoOffset: Double, punches: [PreviewPunch] = [], take: MontageSpan) {
        self.url = url
        self.videoOffset = videoOffset
        self.punches = punches
        self.take = take
    }
}

/// Una parte del montaje.
public struct MontagePart: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var isSolo: Bool
    /// Tramos en que la parte está en pantalla y suena (`MontagePlan.presence`).
    public var presence: [MontageSpan]
    /// `nil`: toma sin vídeo (solo audio, sin recuadro).
    public var video: MontagePartVideo?
    public var framing: MontageFraming

    public init(id: String, name: String, isSolo: Bool, presence: [MontageSpan], video: MontagePartVideo?,
                framing: MontageFraming = MontageFraming()) {
        self.id = id
        self.name = name
        self.isSolo = isSolo
        self.presence = presence
        self.video = video
        self.framing = framing
    }
}

/// Cuándo suena una pista de audio de la vista previa. Los bordes llevan fundidos de 80 ms
/// (`MontageStyle.audioFade`, mini-spec «Transiciones»), dentro del tramo.
public enum MontageAudioGate: Codable, Sendable, Equatable {
    /// Siempre (stems no sustituidos).
    case always
    /// Solo en esos tramos (las tomas: su presencia).
    case during([MontageSpan])
    /// Silenciada en esos tramos con el fundido inverso (la guitarra original durante la presencia de su parte).
    case except([MontageSpan])
}

/// Pista de audio de la vista previa (stems y tomas, sin normalizar).
public struct MontageAudioTrack: Codable, Sendable, Equatable {
    public var url: URL
    /// Instante del tema en que suena la muestra 0 del fichero.
    public var songStart: Double
    /// Ganancia lineal (volumen del canal).
    public var volume: Double
    public var gate: MontageAudioGate

    public init(url: URL, songStart: Double, volume: Double, gate: MontageAudioGate) {
        self.url = url
        self.songStart = songStart
        self.volume = volume
        self.gate = gate
    }
}

/// Rótulo opcional (mini-spec, «Exportación»).
public struct MontageCaption: Codable, Sendable, Equatable {
    public var title: String
    public var artist: String

    public init(title: String, artist: String) {
        self.title = title
        self.artist = artist
    }
}

/// Correspondencia entre el tiempo del vídeo (segmentos concatenados) y el del tema.
public struct MontageTimeMap: Sendable, Equatable {
    public let segments: [MontageSpan]
    /// Segundo del vídeo en que empieza cada segmento.
    public let videoStarts: [Double]
    public let duration: Double

    public init(segments: [MontageSpan]) {
        self.segments = segments
        var acc = 0.0, starts: [Double] = []
        for s in segments { starts.append(acc); acc += s.duration }
        videoStarts = starts
        duration = acc
    }

    /// Índice del segmento que contiene el instante del tema `t` (bordes incluidos; el final de uno, del siguiente).
    public func segmentIndex(songTime t: Double) -> Int? {
        if let i = segments.firstIndex(where: { t >= $0.start && t < $0.end }) { return i }
        if let last = segments.last, t == last.end { return segments.count - 1 }
        return nil
    }

    /// Instante del tema del segundo `v` del vídeo.
    public func songTime(videoTime v: Double) -> Double {
        guard !segments.isEmpty else { return v }
        var k = 0
        while k + 1 < segments.count && v >= videoStarts[k + 1] { k += 1 }
        return segments[k].start + (v - videoStarts[k])
    }

    /// Segundo del vídeo del instante del tema `t`; dentro de un hueco cortado, el inicio del segmento siguiente
    /// (antes del primero, 0; tras el último, el final).
    public func videoTime(songTime t: Double) -> Double {
        for (k, s) in segments.enumerated() {
            if t < s.start { return videoStarts[k] }
            if t <= s.end { return videoStarts[k] + (t - s.start) }
        }
        return duration
    }
}

/// Todo lo que VideoKit necesita para la vista previa y la exportación del montaje.
public struct MontagePlan: Codable, Sendable, Equatable {
    public var canvas: MontageCanvas
    public var fps: Double
    public var layout: MontageLayoutKind
    /// Tramos del tema que forman el vídeo, ordenados y sin solape (`MontagePlan.segments`); el vídeo es su
    /// concatenación. Uno solo sin «Cortar huecos sin tomas».
    public var segments: [MontageSpan]
    /// Duración de un compás (`MontagePlan.barDuration`), para los fundidos.
    public var barDuration: Double
    /// Fundido de un compás al entrar el primer segmento (no empieza con el tema) y al salir el último (no acaba con
    /// él). En los cortes entre segmentos siempre hay fundido de salida y de entrada.
    public var fadeIn: Bool
    public var fadeOut: Bool
    /// En el orden de las partes (el de los recuadros).
    public var parts: [MontagePart]
    /// Plano único: rítmica elegida (`nil`: la primera no solista con vídeo).
    public var singleRhythmPartID: String?
    /// Pistas de la vista previa (la exportación usa el WAV ya mezclado).
    public var audio: [MontageAudioTrack]
    public var caption: MontageCaption?

    /// Un solo segmento (`span`).
    public init(canvas: MontageCanvas, fps: Double, layout: MontageLayoutKind, span: MontageSpan, barDuration: Double,
                fadeIn: Bool, fadeOut: Bool, parts: [MontagePart], singleRhythmPartID: String? = nil,
                audio: [MontageAudioTrack] = [], caption: MontageCaption? = nil) {
        self.init(canvas: canvas, fps: fps, layout: layout, segments: [span], barDuration: barDuration, fadeIn: fadeIn, fadeOut: fadeOut,
                  parts: parts, singleRhythmPartID: singleRhythmPartID, audio: audio, caption: caption)
    }

    public init(canvas: MontageCanvas, fps: Double, layout: MontageLayoutKind, segments: [MontageSpan], barDuration: Double,
                fadeIn: Bool, fadeOut: Bool, parts: [MontagePart], singleRhythmPartID: String? = nil,
                audio: [MontageAudioTrack] = [], caption: MontageCaption? = nil) {
        self.canvas = canvas
        self.fps = fps
        self.layout = layout
        self.segments = segments.filter { $0.duration > 0 }.sorted { $0.start < $1.start }
        self.barDuration = barDuration
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
        self.parts = parts
        self.singleRhythmPartID = singleRhythmPartID
        self.audio = audio
        self.caption = caption
    }

    /// Envolvente de los segmentos (del inicio del primero al final del último).
    public var span: MontageSpan {
        MontageSpan(start: segments.first?.start ?? 0, end: segments.last?.end ?? 0)
    }
    public var timeMap: MontageTimeMap { MontageTimeMap(segments: segments) }
    /// Duración del vídeo: la suma de los segmentos.
    public var videoDuration: Double { timeMap.duration }
    /// Instante del tema que se ve en el segundo `videoTime` del vídeo, y al revés (un hueco cortado va al inicio
    /// del segmento siguiente).
    public func songTime(videoTime: Double) -> Double { timeMap.songTime(videoTime: videoTime) }
    public func videoTime(songTime: Double) -> Double { timeMap.videoTime(songTime: songTime) }

    // MARK: Reglas de la mini-spec, para el puente de la app

    /// BPM y compás por defecto sin pulso (mini-spec, «Qué entra en el montaje»: 120 BPM y 4/4, como en la Fase 6).
    public static let defaultBPM = 120.0
    public static let defaultBeatsPerBar = 4

    /// Duración de un compás del pulso (o la de 120 BPM en 4/4).
    public static func barDuration(bpm: Double?, beatsPerBar: Int?) -> Double {
        let b = (bpm ?? 0) > 0 ? bpm! : defaultBPM
        let n = (beatsPerBar ?? 0) > 0 ? beatsPerBar! : defaultBeatsPerBar
        return Double(n) * 60 / b
    }

    /// Presencia de una parte: el tramo de su toma; si es solista, cortado con las secciones de solo (sin secciones
    /// de solo, vacía: no se espera solo; decisión de Jorge del 16/11/2026). Una presencia vacía no tiene recuadro ni
    /// cuenta para el tramo.
    public static func presence(take: MontageSpan, isSolo: Bool, soloSections: [MontageSpan]) -> [MontageSpan] {
        guard take.duration > 0 else { return [] }
        guard isSolo else { return [take] }
        return soloSections.sorted { $0.start < $1.start }.compactMap { s in
            let a = max(s.start, take.start), b = min(s.end, take.end)
            return b > a ? MontageSpan(start: a, end: b) : nil
        }
    }

    /// Tramo del vídeo: del inicio de presencia más temprano al final más tardío (`nil` si no hay presencia).
    public static func videoSpan(presences: [[MontageSpan]]) -> MontageSpan? {
        let all = presences.flatMap { $0 }.filter { $0.duration > 0 }
        guard let a = all.map(\.start).min(), let b = all.map(\.end).max() else { return nil }
        return MontageSpan(start: a, end: b)
    }

    /// Segmentos del vídeo («Cortar huecos sin tomas», decisión de Jorge del 16/11/2026).
    /// - Sin cortar: uno solo, `videoSpan` (de la primera presencia a la última).
    /// - Cortando: la unión de los tramos de cada parte, fusionados donde se tocan o solapan. Cada tramo empieza donde
    ///   empieza la entrada de su recuadro (`anticipation` antes de la presencia, sin pasar de `imageStarts[i]`, el
    ///   primer instante con imagen de la parte, ni de 0), para no cortar la transición.
    public static func segments(presences: [[MontageSpan]], imageStarts: [Double?]? = nil, cutGaps: Bool) -> [MontageSpan] {
        guard cutGaps else { return videoSpan(presences: presences).map { [$0] } ?? [] }
        var spans: [MontageSpan] = []
        for (i, list) in presences.enumerated() {
            let image = imageStarts?[safe: i] ?? nil
            for p in list where p.duration > 0 {
                var a = max(0, p.start - MontageStyle.anticipation)
                if let image { a = max(a, min(image, p.start)) }
                spans.append(MontageSpan(start: a, end: p.end))
            }
        }
        var out: [MontageSpan] = []
        for s in spans.sorted(by: { $0.start < $1.start }) {
            if let last = out.last, s.start <= last.end { out[out.count - 1].end = max(last.end, s.end) } else { out.append(s) }
        }
        return out
    }

    /// Fundidos globales: de entrada si el vídeo no empieza con el tema; de salida si no acaba con él.
    public static func globalFades(span: MontageSpan, songDuration: Double, tolerance: Double = 1e-3) -> (fadeIn: Bool, fadeOut: Bool) {
        (span.start > tolerance, span.end < songDuration - tolerance)
    }
}

/// Números del montaje. Los de la mini-spec la citan; el resto son decisiones de Fase 7 sin regla en la spec.
public enum MontageStyle {
    /// Recolocación, entrada y salida (mini-spec, «Transiciones»: 0,5 s).
    public static let transition = 0.5
    /// La entrada empieza antes del inicio de presencia: 0,5 s, igual que la transición, para que el recuadro esté
    /// completo (opacidad 1, 100 %, sin desenfoque) en la primera nota (decisión de Jorge del 16/11/2026, sustituye
    /// a los 0,3 s de la mini-spec, «Transiciones»).
    public static let anticipation = 0.5
    /// Escala al entrar (mini-spec, «Transiciones»: del 92 al 100 %).
    public static let entryScale = 0.92
    /// Fundido del audio de cada parte en los bordes de su presencia (mini-spec, «Transiciones»: 80 ms).
    public static let audioFade = 0.080
    /// Rótulo durante los primeros segundos (mini-spec, decisiones de Jorge: 5 s).
    public static let captionDuration = 5.0
    /// Fondo (#0F1113).
    public static let background = (r: 0x0F, g: 0x11, b: 0x13)

    // Sin cifra en la spec (decisión propia, en unidades del lienzo de 1920 px):
    /// Desenfoque (sigma) al empezar la entrada.
    public static let maxBlur = 16.0
    /// Fundido de entrada y de salida del rótulo.
    public static let captionFade = 0.5
    /// Margen exterior y separación entre recuadros.
    public static let margin = 48.0
    public static let gap = 24.0
    /// Esquinas y sombra de los recuadros (sin ellas en el plano único, que va a pantalla completa).
    public static let cornerRadius = 24.0
    public static let shadowBlur = 18.0
    public static let shadowOffset = 10.0
    public static let shadowAlpha = 0.5
    /// Nombre de la parte: cuerpo y separación del borde del recuadro.
    public static let labelFont = 28.0
    public static let labelInset = 20.0
    /// Rótulo: título, artista y separación del borde del lienzo.
    public static let captionTitleFont = 48.0
    public static let captionArtistFont = 32.0
    public static let captionInset = 64.0
}
