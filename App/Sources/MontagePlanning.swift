import AudioKit
import Foundation
import Store
import VideoKit

/// Tramo del tema en segundos (la interfaz no importa VideoKit ni AudioKit).
struct LaneSpan: Equatable, Sendable {
    var start: Double
    var end: Double
    var duration: Double { max(0, end - start) }
}

/// Un carril de la línea de tiempo: la mejor toma de una parte.
struct MontageLane: Identifiable, Equatable {
    var id: UUID
    var partName: String
    var takeID: UUID
    var isSolo: Bool
    /// Pista de guitarra que sustituye (silenciada mientras la parte está presente).
    var replaces: GuitarRole?
    /// Tramos en que la parte está en pantalla y suena.
    var presence: [LaneSpan]
    /// Tramo del tema que cubre la toma.
    var take: LaneSpan
    /// `nil`: toma sin vídeo (solo audio, sin recuadro).
    var video: MontagePartVideo?
    var hasVideo: Bool { video != nil }
}

/// Tramo del carril «Plano» con la parte que se ve (`nil`: ninguna); `black`, su toma ya acabó (fundido a negro).
struct PlaneShot: Equatable, Sendable {
    var start: Double
    var end: Double
    var part: UUID?
    var black: Bool
}

/// Tramo del vídeo con sus fundidos de un compás en los bordes (`fadeIn`/`fadeOut`).
struct LaneSegment: Equatable, Sendable {
    var start: Double
    var end: Double
    var fadeIn: Bool
    var fadeOut: Bool
}

/// Lo que sale de un proyecto: el plan de VideoKit, el trabajo de mezcla equivalente y los datos de la interfaz.
struct MontageDraft {
    var plan: MontagePlan
    var lanes: [MontageLane]
    /// Pistas del `MontageMixJob` (stems y tomas, con volumen y presencia); el resto del trabajo lo pone el controlador.
    var mixTracks: [MontageTrack]
    /// Partes que suenan en el montaje pero no tienen vídeo (solo audio).
    var audioOnlyParts: [String]
    /// Partes sin mejor toma (carril vacío, «Sin toma»).
    var missingParts: [String]
    /// Tramos del tema que entran en el vídeo: uno solo, o con «Cortar huecos sin tomas» los de presencia concatenados.
    var segments: [LaneSegment]
    var span: LaneSpan { LaneSpan(start: plan.span.start, end: plan.span.end) }
}

/// Puente Store → `MontagePlan` / `MontageTrack` (mini-spec Fase 7, «Qué entra en el montaje»). Funciones puras; la
/// duración de cada toma se la da quien llama (`takeDuration`) para no tocar el disco aquí.
enum MontagePlanning {
    /// Lado mayor de la vista previa en pantalla (decisión propia: tiempo real sin gastar la GPU).
    static let previewMaxDimension = 960
    /// Plano único y apilado son portrait; lado a lado, rejilla y plano único landscape, landscape (spec, «Layouts»).
    static func isPortrait(_ kind: Store.MontageLayoutKind) -> Bool { kind.isPortrait }

    static func canvas(for kind: Store.MontageLayoutKind) -> MontageCanvas {
        isPortrait(kind) ? .portrait : .landscape
    }

    /// Dimensiones de exportación: la resolución de Ajustes es landscape; en portrait se gira.
    static func exportSize(_ r: VideoResolution, kind: Store.MontageLayoutKind) -> (width: Int, height: Int) {
        let w = max(r.width, r.height), h = min(r.width, r.height)
        return isPortrait(kind) ? (h, w) : (w, h)
    }

    /// Encuadre de VideoKit desde el ajuste guardado y el análisis (si lo hay).
    static func framing(_ f: TakeFraming, analysis: FramingAnalysis?) -> MontageFraming {
        MontageFraming(mode: f.mode == .follow ? .follow : .fixed, analysis: analysis,
                       manualBox: f.manualBox.map { FramingBox(x: $0.x, y: $0.y, width: $0.width, height: $0.height) },
                       followZoom: f.followZoom, followOffsetX: f.followOffset.x, followOffsetY: f.followOffset.y)
    }

    /// Tramos del vídeo para el mezclador: los de `MontagePlan.segments` con los fundidos de un compás en los bordes
    /// (primer segmento: `fadeIn`; último: `fadeOut`; en los cortes interiores, siempre).
    static func laneSegments(_ segs: [VideoSpan], fadeIn: Bool, fadeOut: Bool) -> [LaneSegment] {
        segs.enumerated().map { i, s in
            LaneSegment(start: s.start, end: s.end, fadeIn: i == 0 ? fadeIn : true, fadeOut: i == segs.count - 1 ? fadeOut : true)
        }
    }

    static func linear(_ dB: Double) -> Double { pow(10, dB / 20) }

    /// Partes que un corte del plano único en `t` puede mandar (selector del carril «Plano»; decisión de Jorge del
    /// 17/11/2026): las que tienen toma con imagen en ese instante (`MontagePlan.singleCutCandidates`). Las demás se
    /// muestran desactivadas; sin plan, ninguna es elegible.
    static func cutEligibleParts(plan: MontagePlan?, at t: Double) -> Set<UUID> {
        Set((plan?.singleCutCandidates(at: t) ?? []).compactMap(UUID.init(uuidString:)))
    }

    /// Lo que se ve en el plano único, tramo a tramo (color del carril «Plano»): las mismas reglas de cobertura que la
    /// vista previa, sin abrir los vídeos (`MontagePlan.singleShots`). Sin plan, vacío.
    static func planeShots(plan: MontagePlan?) -> [PlaneShot] {
        (plan?.singleShots() ?? []).map {
            PlaneShot(start: $0.span.start, end: $0.span.end, part: $0.partID.flatMap(UUID.init(uuidString:)), black: $0.black)
        }
    }

    static func build(project: Project, layout: ProjectLayout, state: MontageState, barDuration: Double,
                      analyses: [UUID: FramingAnalysis], stems: [StemKind], guitarRoles: [GuitarRole],
                      takeDuration: (URL) -> Double?) -> MontageDraft? {
        let rec = project.recordingOrInitial()
        let soloSections = project.sections.filter(\.isSolo).map { VideoSpan(start: $0.start, end: $0.end) }

        // Partes con su mejor toma.
        var lanes: [MontageLane] = []
        var parts: [MontagePart] = []
        var takeByLane: [UUID: Take] = [:]
        var missing: [String] = []
        for part in rec.parts {
            guard let takeID = part.bestTakeID, let take = project.takes.first(where: { $0.id == takeID }),
                  let rel = take.processedFile, let start = take.songStart,
                  let dur = takeDuration(layout.url(relative: rel)), dur > 0 else { missing.append(part.name); continue }
            let span = VideoSpan(start: start, end: start + dur)
            // Solista sin secciones de solo: no se espera solo, no aparece ni suena (el carril lo anota).
            let presence = part.isLead && soloSections.isEmpty ? [] : MontagePlan.presence(take: span, isSolo: part.isLead, soloSections: soloSections)
            let punches = (take.punches ?? []).map {
                PreviewPunch(start: $0.start, end: $0.end, videoURL: $0.videoFile.map { layout.url(relative: $0) },
                             videoOffset: $0.videoOffset ?? take.videoOffset ?? 0)
            }
            let hasImage = take.videoFile != nil || punches.contains { $0.videoURL != nil }
            let video = hasImage ? MontagePartVideo(url: take.videoFile.map { layout.url(relative: $0) },
                                                    videoOffset: take.videoOffset ?? 0, punches: punches, take: span,
                                                    rotation: VideoRotation(degrees: take.rotationDegrees)) : nil
            let fr = Self.framing(state.framing(for: takeID), analysis: analyses[takeID])
            parts.append(MontagePart(id: part.id.uuidString, name: part.name, isSolo: part.isLead, presence: presence,
                                     video: video, framing: fr))
            lanes.append(MontageLane(id: part.id, partName: part.name, takeID: takeID, isSolo: part.isLead,
                                     replaces: part.replaces, presence: presence.map { LaneSpan(start: $0.start, end: $0.end) },
                                     take: LaneSpan(start: span.start, end: span.end), video: video))
            takeByLane[part.id] = take
        }
        // Orden propio del montaje (recuadros = carriles). Solo afecta a lanes y parts; las pistas de audio se
        // construyen abajo en el orden natural de `lanes` ya reordenado, pero su suma/nombres no dependen del orden.
        let order = state.effectiveOrder(of: rec.parts.map(\.id))
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        lanes.sort { (rank[$0.id] ?? .max) < (rank[$1.id] ?? .max) }
        func partRank(_ p: MontagePart) -> Int { UUID(uuidString: p.id).flatMap { rank[$0] } ?? .max }
        parts.sort { partRank($0) < partRank($1) }
        // Primer instante con imagen (con vídeo base, el inicio de la toma; sin él, el primer punch con vídeo).
        let imageStarts: [Double?] = parts.map { $0.video?.coverage.first?.start }
        let videoSegments = MontagePlan.segments(presences: parts.map(\.presence), imageStarts: imageStarts, cutGaps: state.cutGaps)
        guard let first = videoSegments.first, let last = videoSegments.last else { return nil }
        // Fundidos globales con el tramo crudo; los tramos finales salen de `plan.segments` (cuantizados a fotogramas).
        let rawSpan = VideoSpan(start: first.start, end: last.end)
        let fades = MontagePlan.globalFades(span: rawSpan, songDuration: project.song.duration)
        let single = state.singleRhythmPartID.flatMap { id in
            lanes.contains { $0.id == id && $0.hasVideo && !$0.isSolo } ? id.uuidString : nil
        }
        // Cortes libres del plano único (portrait o landscape); los de partes que ya no existen se omiten.
        let existingParts = Set(rec.parts.map(\.id))
        let cuts: [MontageCut] = state.singleCuts.normalizedSingleCuts().compactMap { c in
            guard let p = c.partID else { return MontageCut(time: c.time, partID: nil) }
            return existingParts.contains(p) ? MontageCut(time: c.time, partID: p.uuidString) : nil
        }
        let caption = state.caption ? MontageCaption(title: project.song.title, artist: project.song.artist ?? "") : nil

        // Audio: stems con la mezcla de Grabar; la guitarra sustituida, silenciada durante la presencia de su parte.
        func union(_ keep: (MontageLane) -> Bool) -> [VideoSpan] {
            lanes.filter(keep).flatMap(\.presence).map { VideoSpan(start: $0.start, end: $0.end) }
        }
        let anySolo = rec.mix.contains { $0.solo }
        func audible(_ m: StemMix) -> Bool { !m.muted && (!anySolo || m.solo) }

        struct Backing { var id: String; var url: URL; var gainDB: Double; var silenced: [VideoSpan] }
        var backing: [Backing] = []
        for kind in stems {
            let m = rec.mix.first { $0.kind == kind && $0.guitarRole == nil } ?? StemMix(kind: kind)
            guard audible(m) else { continue }
            // Sin pistas separadas, el stem de guitarras entero lo sustituye cualquier parte que sustituya a una guitarra.
            let sil = kind == .guitar && guitarRoles.isEmpty ? union { $0.replaces != nil } : []
            backing.append(Backing(id: "stem-\(kind.rawValue)", url: layout.stemURL(kind), gainDB: m.gainDB, silenced: sil))
        }
        for role in guitarRoles {
            let m = rec.mix.first { $0.guitarRole == role } ?? StemMix(kind: .guitar, guitarRole: role)
            guard audible(m) else { continue }
            backing.append(Backing(id: role.trackID, url: layout.guitarURL(role), gainDB: m.gainDB,
                                   silenced: union { $0.replaces == role }))
        }

        var previewAudio: [MontageAudioTrack] = []
        var mix: [MontageTrack] = []
        for b in backing {
            previewAudio.append(MontageAudioTrack(url: b.url, songStart: 0, volume: linear(b.gainDB),
                                           gate: b.silenced.isEmpty ? .always : .except(b.silenced)))
            mix.append(MontageTrack(id: b.id, url: b.url, songStart: 0, gainDB: b.gainDB, group: .backing,
                                    presence: b.silenced.isEmpty ? .always : .silenced(b.silenced.map { MixSpan(start: $0.start, end: $0.end) })))
        }
        // Tomas: su volumen de canal «Tú · parte» (`rec.partMix`; sin valor, 0 dB) y su presencia. El silencio (`muted`)
        // es una ayuda de escucha al grabar, no una decisión de mezcla: el montaje lo ignora.
        for lane in lanes where !lane.presence.isEmpty {
            guard let take = takeByLane[lane.id], let rel = take.processedFile, let start = take.songStart else { continue }
            let url = layout.url(relative: rel)
            let pm = rec.partMix(for: lane.id)
            previewAudio.append(MontageAudioTrack(url: url, songStart: start, volume: linear(pm.gainDB),
                                           gate: .during(lane.presence.map { VideoSpan(start: $0.start, end: $0.end) })))
            mix.append(MontageTrack(id: "take-\(lane.id.uuidString)", url: url, songStart: start, gainDB: pm.gainDB,
                                    group: .part(lane.partName),
                                    presence: .audible(lane.presence.map { MixSpan(start: $0.start, end: $0.end) })))
        }

        let plan = MontagePlan(canvas: canvas(for: state.layout), fps: state.export.fps,
                               layout: VideoLayoutKind(rawValue: state.layout.rawValue) ?? .side, segments: videoSegments,
                               barDuration: barDuration, fadeIn: fades.fadeIn, fadeOut: fades.fadeOut, parts: parts,
                               singleRhythmPartID: single, audio: previewAudio, caption: caption,
                               showPartLabels: state.showPartLabels, keepVideoAspect: state.keepVideoAspect,
                               singleCuts: state.layout.isSingleShot ? MontageCut.normalized(cuts) : [])
        // Mismos tramos que el plan (cuantizados, tramos que se tocan fundidos) para que vídeo y WAV duren lo mismo.
        let segments = laneSegments(plan.segments, fadeIn: fades.fadeIn, fadeOut: fades.fadeOut)
        return MontageDraft(plan: plan, lanes: lanes, mixTracks: mix,
                            audioOnlyParts: lanes.filter { !$0.hasVideo && !$0.presence.isEmpty }.map(\.partName),
                            missingParts: missing, segments: segments)
    }
}
