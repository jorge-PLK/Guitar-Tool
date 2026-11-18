import Foundation

/// Adornos que se conmutan con el teclado (mini-spec Fase 5c, tabla «Teclas (modo edición)»; teclas de Guitar Pro 8).
public enum TabOrnament: Sendable, Equatable, CaseIterable {
    case palmMute, letRing, hammerPull
    /// Cicla: legato → shift → entrada desde abajo → entrada desde arriba → salida abajo → salida arriba → ninguno.
    case slide
    /// Cicla: 1 tono → ½ tono → bend-release → ninguno.
    case bend
    case vibrato, whammyVibrato, dead, ghost
    /// `;` y `:`.
    case accent, heavyAccent
    case staccato, naturalHarmonic, artificialHarmonic
    /// Nota de adorno antes del pulso, dos trastes por debajo y ligada.
    case grace
    case tapping
    /// Ligadura de duración con la nota anterior de la misma cuerda y altura.
    case tie
    case pickDown, pickUp
    /// Solo batería: golpe de adorno delante.
    case flam
}

public extension TabEditor {
    /// Bends de la tecla B (cuartos de tono: 4 = un tono; `TabBend.quarterTonesPerTone`), en el orden del ciclo
    /// (mini-spec Fase 5c, tabla de teclas): 1 tono, ½ tono, bend-release.
    static let bendCycle: [TabBend] = [
        TabBend(type: .bend, points: [TabBendPoint(position: 0, value: 0), TabBendPoint(position: 30, value: 4),
                                      TabBendPoint(position: TabBend.maxPosition, value: 4)]),
        TabBend(type: .bend, points: [TabBendPoint(position: 0, value: 0), TabBendPoint(position: 30, value: 2),
                                      TabBendPoint(position: TabBend.maxPosition, value: 2)]),
        TabBend(type: .bendRelease, points: [TabBendPoint(position: 0, value: 0), TabBendPoint(position: 20, value: 4),
                                             TabBendPoint(position: 40, value: 4),
                                             TabBendPoint(position: TabBend.maxPosition, value: 0)]),
    ]

    /// Vibrato de palanca (tecla W): la palanca baja medio tono dos veces y vuelve (mini-spec Fase 5c, tabla de teclas).
    static let whammyVibrato = TabBend(type: .custom, points: [
        TabBendPoint(position: 0, value: 0), TabBendPoint(position: 15, value: -2), TabBendPoint(position: 30, value: 0),
        TabBendPoint(position: 45, value: -2), TabBendPoint(position: TabBend.maxPosition, value: 0),
    ])

    /// Trastes por debajo de la nota principal a los que cae la nota de adorno de la tecla G (mini-spec Fase 5c, tabla).
    static let graceFretsBelow = 2

    private struct SlideState: Equatable {
        var slideIn: TabSlideIn?
        var slideOut: TabSlideOut?
    }

    /// Ciclo de la tecla S (mini-spec Fase 5c, tabla de teclas); el primer estado es «ninguno».
    private static let slideCycle: [SlideState] = [
        SlideState(), SlideState(slideOut: .legato), SlideState(slideOut: .shift),
        SlideState(slideIn: .intoFromBelow), SlideState(slideIn: .intoFromAbove),
        SlideState(slideOut: .outDown), SlideState(slideOut: .outUp),
    ]

    // MARK: Selección

    /// Notas de la pista que empiezan dentro del tramo.
    func noteIDs(in span: TabSpan, trackID: String) -> [Int] {
        guard let i = score.trackIndex(id: trackID) else { return [] }
        return score.tracks[i].notes.filter { $0.start.absoluteTick >= span.startTick && $0.start.absoluteTick < span.endTick }
            .map(\.id)
    }

    /// Puntos con algún golpe de batería dentro del tramo.
    func hitPoints(in span: TabSpan, trackID: String) -> [GridPoint] {
        guard let i = score.trackIndex(id: trackID) else { return [] }
        let points = score.tracks[i].hits.map(\.at).filter { $0.absoluteTick >= span.startTick && $0.absoluteTick < span.endTick }
        return Array(Set(points)).sorted()
    }

    // MARK: Guitarra y bajo

    /// Conmuta `ornament` en las notas: si todas lo tienen lo quita de todas; si no, lo pone en todas. S y B ciclan
    /// (el siguiente estado sale de la primera nota y se aplica a todas). Una sola operación de deshacer. Falla sin
    /// tocar nada en pistas de batería o voz, con notas que no existen, con G sobre un traste 0 y con L sin nota
    /// anterior que ligar (con varias notas, las que no se pueden ligar o adornar se saltan si alguna sí puede).
    mutating func toggle(_ ornament: TabOrnament, trackID: String, noteIDs: [Int]) throws {
        try edit(trackID: trackID) { track in
            guard track.kind == .guitar || track.kind == .bass, track.tuning != nil, ornament != .flam else {
                throw TabEditError.wrongTrackKind
            }
            let wanted = Set(noteIDs)
            let idx = track.notes.indices.filter { wanted.contains(track.notes[$0].id) }
            guard !idx.isEmpty, idx.count == wanted.count else { throw TabEditError.unknownNote }
            switch ornament {
            case .slide:
                let first = track.notes[idx[0]].techniques
                let now = SlideState(slideIn: first.slideIn, slideOut: first.slideOut)
                let next = Self.slideCycle.firstIndex(of: now).map { Self.slideCycle[($0 + 1) % Self.slideCycle.count] }
                    ?? Self.slideCycle[0]
                for i in idx {
                    track.notes[i].techniques.slideIn = next.slideIn
                    track.notes[i].techniques.slideOut = next.slideOut
                }
            case .bend:
                let now = track.notes[idx[0]].techniques.bend
                let next: TabBend?
                if let now {
                    let k = Self.bendCycle.firstIndex(of: now)
                    next = k.flatMap { $0 + 1 < Self.bendCycle.count ? Self.bendCycle[$0 + 1] : nil }
                } else {
                    next = Self.bendCycle[0]
                }
                for i in idx { track.notes[i].techniques.bend = next }
            case .grace:
                let on = !idx.allSatisfy { !track.notes[$0].techniques.graces.isEmpty }
                var changed = false
                for i in idx {
                    if !on { track.notes[i].techniques.graces = []; changed = true; continue }
                    guard let fret = track.fret(of: track.notes[i]), fret >= 1 else { continue }
                    track.notes[i].techniques.graces = [TabGrace(fret: max(0, fret - Self.graceFretsBelow),
                                                                  type: .beforeBeat, hammerPull: true)]
                    changed = true
                }
                guard changed else { throw TabEditError.fretOutOfRange }
            case .tie:
                let on = !idx.allSatisfy { track.notes[$0].techniques.tieDestination }
                var changed = false
                for i in idx {
                    if !on { track.notes[i].techniques.tieDestination = false; changed = true; continue }
                    let n = track.notes[i]
                    guard track.notes.contains(where: {
                        $0.id != n.id && $0.string == n.string && $0.pitch == n.pitch && $0.end == n.start
                    }) else { continue }
                    track.notes[i].techniques.tieDestination = true
                    changed = true
                }
                guard changed else { throw TabEditError.noTieOrigin }
            default:
                let on = !idx.allSatisfy { Self.isOn(ornament, track.notes[$0].techniques) }
                for i in idx { Self.set(ornament, on: on, &track.notes[i].techniques) }
            }
        }
    }

    private static func isOn(_ o: TabOrnament, _ t: TabTechniques) -> Bool {
        switch o {
        case .palmMute: t.palmMute
        case .letRing: t.letRing
        case .hammerPull: t.hammerPull
        case .vibrato: t.vibrato != nil
        case .whammyVibrato: t.whammy == whammyVibrato
        case .dead: t.dead
        case .ghost: t.ghost
        case .accent: t.accent == .normal
        case .heavyAccent: t.accent == .heavy
        case .staccato: t.staccato
        case .naturalHarmonic: t.harmonic?.type == .natural
        case .artificialHarmonic: t.harmonic?.type == .artificial
        case .tapping: t.tapping
        case .pickDown: t.pickStroke == .down
        case .pickUp: t.pickStroke == .up
        case .slide, .bend, .grace, .tie, .flam: false
        }
    }

    private static func set(_ o: TabOrnament, on: Bool, _ t: inout TabTechniques) {
        switch o {
        case .palmMute: t.palmMute = on
        case .letRing: t.letRing = on
        case .hammerPull: t.hammerPull = on
        case .vibrato: t.vibrato = on ? .slight : nil
        case .whammyVibrato: t.whammy = on ? whammyVibrato : nil
        case .dead: t.dead = on
        case .ghost: t.ghost = on
        case .accent: t.accent = on ? .normal : nil
        case .heavyAccent: t.accent = on ? .heavy : nil
        case .staccato: t.staccato = on
        case .naturalHarmonic: t.harmonic = on ? TabHarmonic(type: .natural) : nil
        case .artificialHarmonic: t.harmonic = on ? TabHarmonic(type: .artificial) : nil
        case .tapping: t.tapping = on
        case .pickDown: t.pickStroke = on ? .down : nil
        case .pickUp: t.pickStroke = on ? .up : nil
        case .slide, .bend, .grace, .tie, .flam: break
        }
    }

    /// Cambia el traste de la nota de adorno de la nota (la primera de sus adornos). Mismo rango que `setFret`.
    mutating func setGraceFret(_ fret: Int, trackID: String, noteID: Int) throws {
        try edit(trackID: trackID) { track in
            guard track.kind == .guitar || track.kind == .bass, track.tuning != nil else { throw TabEditError.wrongTrackKind }
            guard let i = track.notes.firstIndex(where: { $0.id == noteID }),
                  !track.notes[i].techniques.graces.isEmpty else { throw TabEditError.unknownNote }
            guard Tuning.fretRange.contains(fret) else { throw TabEditError.fretOutOfRange }
            track.notes[i].techniques.graces[0].fret = fret
        }
    }

    // MARK: Batería

    /// Conmuta fantasma (`ghost`), acento (`accent`, `heavyAccent`) o flam en todos los golpes de los puntos dados.
    /// Los golpes de pieza (B C H T P) siguen en `setHit`.
    mutating func toggle(_ ornament: TabOrnament, trackID: String, hitPoints: [GridPoint]) throws {
        try edit(trackID: trackID) { track in
            guard track.kind == .drums, [.ghost, .accent, .heavyAccent, .flam].contains(ornament) else {
                throw TabEditError.wrongTrackKind
            }
            let points = Set(hitPoints)
            let idx = track.hits.indices.filter { points.contains(track.hits[$0].at) }
            guard !idx.isEmpty else { throw TabEditError.unknownNote }
            switch ornament {
            case .ghost:
                let on = !idx.allSatisfy { track.hits[$0].ghost }
                for i in idx { track.hits[i].ghost = on }
            case .accent, .heavyAccent:
                let level: TabAccent = ornament == .accent ? .normal : .heavy
                let on = !idx.allSatisfy { track.hits[$0].accent == level }
                for i in idx { track.hits[i].accent = on ? level : nil }
            default:
                let on = !idx.allSatisfy { track.hits[$0].grace != nil }
                for i in idx {
                    track.hits[i].grace = on ? TabGrace(fret: track.hits[i].piece.rawValue, type: .beforeBeat) : nil
                }
            }
        }
    }
}
