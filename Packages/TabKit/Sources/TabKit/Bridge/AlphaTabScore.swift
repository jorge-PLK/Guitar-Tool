import Foundation

/// Un pulso de alphaTab (nota, acorde, golpe o silencio) con lo que hace falta para volver a la partitura al hacer
/// clic: dónde empieza en la rejilla y qué notas o golpes lleva.
public struct AlphaTabBeatRef: Sendable, Equatable {
    public var start: GridPoint
    /// Ticks que cubre en la partitura de alphaTab.
    public var length: Int
    /// Índice de cuerda del JSON (0 = la más grave) → id de la `TabNote`.
    public var noteIDs: [Int: Int]
    public var pieces: [DrumPiece]
    public var isRest: Bool { noteIDs.isEmpty && pieces.isEmpty }
}

/// `TabScore` traducida al JSON v1 de `App/Resources/alphaTab/tf-bridge.js` (cabecera del fichero), más el mapa de
/// pulsos por pista y compás (mismo orden que el JSON) para traducir clics de alphaTab a posiciones de la partitura.
public struct AlphaTabScore: Sendable, Equatable {
    public var json: String
    /// Id de pista de `TabScore`, en el orden del JSON (índice de pista de alphaTab).
    public var trackIDs: [String]
    /// `beats[pista][compás][pulso]`.
    public var beats: [[[AlphaTabBeatRef]]]

    public func ref(track: Int, bar: Int, beat: Int) -> AlphaTabBeatRef? {
        guard beats.indices.contains(track), beats[track].indices.contains(bar),
              beats[track][bar].indices.contains(beat) else { return nil }
        return beats[track][bar][beat]
    }
}

public enum AlphaTabExporter {
    /// Cuerda de `TabScore` (1 = la más aguda) a índice del JSON (0 = la más grave).
    public static func jsonString(forScoreString string: Int, stringCount: Int) -> Int { stringCount - string }

    /// Cuerda de `TabScore` desde el índice del JSON.
    public static func scoreString(forJSONString s: Int, stringCount: Int) -> Int { stringCount - s }

    // MARK: JSON (esquema v1 de tf-bridge.js)

    private struct JBar: Encodable { var num: Int; var den: Int; var tempo: Double; var start: Double }
    private struct JBend: Encodable { var type: String; var pts: [[Int]] }
    private struct JHarmonic: Encodable { var type: String; var fret: Double? }
    /// Técnicas por nota (claves cortas, ver cabecera de tf-bridge.js); solo las puestas.
    private struct JTech: Encodable {
        var pm: Bool?; var lr: Bool?; var hp: Bool?; var dead: Bool?; var ghost: Bool?; var stac: Bool?
        var vib: String?; var bend: JBend?; var sin: String?; var sout: String?
        var harm: JHarmonic?; var acc: String?; var tie: Bool?

        var isBlank: Bool {
            pm == nil && lr == nil && hp == nil && dead == nil && ghost == nil && stac == nil && vib == nil
                && bend == nil && sin == nil && sout == nil && harm == nil && acc == nil && tie == nil
        }
    }
    /// Figura por defecto de una nota de adorno (fusa, como en Guitar Pro).
    static let graceDefaultDuration = 32

    /// `p`: altura MIDI de las notas de voz (sin cuerda ni traste); las demás no la llevan.
    private struct JNote: Encodable { var s: Int; var f: Int; var p: Int? = nil; var t: JTech? }
    private struct JBeat: Encodable {
        var d: Int
        var dots: Int?
        var tuplet: Int?
        var notes: [JNote]?
        var hits: [Int]?
        /// Golpes de `hits` que son fantasma.
        var ghosts: [Int]?
        /// Golpes de `hits` acentuados: nota GM (como texto) → `AccentuationType`.
        var accents: [String: String]?
        // Técnicas que alphaTab guarda por beat (subidas desde las notas del acorde).
        var tap: Bool?
        var trem: Int?
        var whammy: JBend?
        var pick: String?
        var brush: String?
        /// Beat de adorno (`Beat.graceType`): sin tiempo en la rejilla, va antes del beat de su nota principal.
        var grace: String?
    }
    private struct JTrack: Encodable {
        var name: String
        var kind: String
        var tuning: [Int]?
        /// Programa GM (base 0) de una voz.
        var program: Int?
        var bars: [[JBeat]]
    }
    private struct JScore: Encodable {
        var version = 1
        var title: String
        var artist: String
        var bars: [JBar]
        var tracks: [JTrack]
    }

    public static func make(score: TabScore, title: String, artist: String) throws -> AlphaTabScore {
        let bars = score.bars.map {
            JBar(num: $0.beatCount, den: $0.beatUnit, tempo: $0.tempo, start: $0.start)
        }
        var jtracks: [JTrack] = []
        var maps: [[[AlphaTabBeatRef]]] = []
        let names = score.trackDisplayNames
        for (ti, track) in score.tracks.enumerated() {
            var jbars: [[JBeat]] = []
            var bmap: [[AlphaTabBeatRef]] = []
            for bar in score.bars {
                let (jb, refs) = convertBar(track: track, bar: bar, score: score)
                jbars.append(jb)
                bmap.append(refs)
            }
            jtracks.append(JTrack(name: names[ti], kind: track.kind.rawValue,
                                  tuning: track.tuning.map { Array($0.strings.reversed()) },
                                  program: track.kind == .vocal ? track.program : nil, bars: jbars))
            maps.append(bmap)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(JScore(title: title, artist: artist, bars: bars, tracks: jtracks))
        return AlphaTabScore(json: String(decoding: data, as: UTF8.self), trackIDs: score.tracks.map(\.id), beats: maps)
    }

    // MARK: Técnicas

    /// Guitar Pro 7 guarda como mucho 4 puntos por curva de bend o palanca.
    static let maxBendPoints = 4

    private static func jBend(_ b: TabBend) -> JBend {
        let s = b.simplified(maxPoints: maxBendPoints).paddedForAlphaTab()
        return JBend(type: s.type.rawValue, pts: s.points.map { [$0.position, $0.value] })
    }

    private static func jTech(_ t: TabTechniques) -> JTech? {
        let j = JTech(pm: t.palmMute ? true : nil, lr: t.letRing ? true : nil, hp: t.hammerPull ? true : nil,
                     dead: t.dead ? true : nil, ghost: t.ghost ? true : nil, stac: t.staccato ? true : nil,
                     vib: t.vibrato?.rawValue, bend: t.bend.map(jBend), sin: t.slideIn?.rawValue,
                     sout: t.slideOut?.rawValue,
                     harm: t.harmonic.map { JHarmonic(type: $0.type.rawValue, fret: $0.fret) },
                     acc: t.accent?.rawValue, tie: t.tieDestination ? true : nil)
        return j.isBlank ? nil : j
    }

    // MARK: Compás a pulsos de alphaTab

    private struct Piece { var length: Int; var d: Int; var dots: Int; var tuplet: Int? }

    /// Longitudes que alphaTab sabe escribir con un solo pulso, de mayor a menor, según la subdivisión del pulso donde
    /// empieza (semicorcheas: figuras y puntillos; tresillos: tresillos de corchea y de negra).
    private static let sixteenthPieces = [
        Piece(length: 48, d: 1, dots: 0, tuplet: nil), Piece(length: 36, d: 2, dots: 1, tuplet: nil),
        Piece(length: 24, d: 2, dots: 0, tuplet: nil), Piece(length: 18, d: 4, dots: 1, tuplet: nil),
        Piece(length: 12, d: 4, dots: 0, tuplet: nil), Piece(length: 9, d: 8, dots: 1, tuplet: nil),
        Piece(length: 6, d: 8, dots: 0, tuplet: nil), Piece(length: 3, d: 16, dots: 0, tuplet: nil),
    ]
    private static let tripletPieces = [
        Piece(length: 48, d: 1, dots: 0, tuplet: nil), Piece(length: 36, d: 2, dots: 1, tuplet: nil),
        Piece(length: 24, d: 2, dots: 0, tuplet: nil), Piece(length: 12, d: 4, dots: 0, tuplet: nil),
        Piece(length: 8, d: 4, dots: 0, tuplet: 3), Piece(length: 4, d: 8, dots: 0, tuplet: 3),
    ]

    /// El pulso termina en un punto de la rejilla (frontera de pulso o punto de la subdivisión de su pulso).
    private static func isValidEnd(_ tick: Int, track: TabTrack) -> Bool {
        let beat = tick / TabScore.ticksPerBeat
        let inBeat = tick % TabScore.ticksPerBeat
        if inBeat == 0 { return true }
        guard track.subdivisions.indices.contains(beat) else { return false }
        return inBeat % track.subdivisions[beat].tickStep == 0
    }

    private static func pickPiece(at start: Int, atMost limit: Int, track: TabTrack) -> Piece {
        let beat = start / TabScore.ticksPerBeat
        let sub = track.subdivisions.indices.contains(beat) ? track.subdivisions[beat] : .sixteenths
        let list = sub == .sixteenths ? sixteenthPieces : tripletPieces
        let aligned = start % TabScore.ticksPerBeat == 0
        for p in list where p.length <= limit {
            // En tresillos, solo se empieza una figura de pulso entero o más en un pulso.
            if sub == .eighthTriplets, p.length >= TabScore.ticksPerBeat, !aligned { continue }
            if isValidEnd(start + p.length, track: track) { return p }
        }
        return list[list.count - 1]   // el menor: siempre hay progreso
    }

    private static func convertBar(track: TabTrack, bar: TabBar, score: TabScore) -> ([JBeat], [AlphaTabBeatRef]) {
        let barStart = bar.firstBeat * TabScore.ticksPerBeat
        let barEnd = barStart + bar.beatCount * TabScore.ticksPerBeat
        let stringCount = track.tuning?.strings.count ?? 0
        var beats: [JBeat] = []
        var refs: [AlphaTabBeatRef] = []

        func emit(_ piece: Piece, at start: Int, notes: [(string: Int, fret: Int, id: Int, tech: TabTechniques, pitch: Int?)] = [],
                  hits: [DrumPiece] = [], ghostHits: [DrumPiece] = [], accents: [DrumPiece: TabAccent] = [:],
                  drumGraces: [(piece: DrumPiece, grace: TabGrace)] = []) {
            // Notas de adorno: un beat de adorno por `step`, del más lejano al inmediatamente anterior, cada nota en su
            // cuerda (longitud 0 en el mapa; un clic en una elige la nota principal que la lleva).
            let graces = notes.flatMap { n in
                n.tech.graces.map { g in
                    (s: g.string.map { jsonString(forScoreString: $0, stringCount: stringCount) } ?? n.string, id: n.id, g: g)
                }
            }.filter { (0..<stringCount).contains($0.s) }
            for step in Set(graces.map(\.g.step)).sorted(by: >) {
                var inStep: [(s: Int, id: Int, g: TabGrace)] = []
                for x in graces where x.g.step == step && !inStep.contains(where: { $0.s == x.s }) { inStep.append(x) }
                inStep.sort { $0.s < $1.s }
                let jg = JBeat(d: inStep[0].g.duration ?? AlphaTabExporter.graceDefaultDuration, notes: inStep.map { x in
                    var t = JTech()
                    t.dead = x.g.dead ? true : nil
                    t.hp = x.g.hammerPull ? true : nil
                    t.sout = x.g.slide ? TabSlideOut.legato.rawValue : nil
                    return JNote(s: x.s, f: x.g.fret, t: t.isBlank ? nil : t)
                }, grace: inStep[0].g.type.rawValue)
                beats.append(jg)
                refs.append(AlphaTabBeatRef(start: GridPoint(absoluteTick: start), length: 0,
                                            noteIDs: Dictionary(inStep.map { ($0.s, $0.id) }, uniquingKeysWith: { a, _ in a }),
                                            pieces: []))
            }
            if let first = drumGraces.first {
                // Flam: beat de adorno con la nota de percusión del adorno (o la del propio golpe si no es una pieza conocida).
                let gm = drumGraces.map { DrumPiece(rawValue: $0.grace.fret) ?? $0.piece }
                beats.append(JBeat(d: first.grace.duration ?? AlphaTabExporter.graceDefaultDuration,
                                   hits: gm.map(\.rawValue), grace: first.grace.type.rawValue))
                refs.append(AlphaTabBeatRef(start: GridPoint(absoluteTick: start), length: 0, noteIDs: [:],
                                            pieces: drumGraces.map(\.piece)))
            }
            var jb = JBeat(d: piece.d, dots: piece.dots > 0 ? piece.dots : nil, tuplet: piece.tuplet)
            var ids: [Int: Int] = [:]
            if !notes.isEmpty {
                jb.notes = notes.map { JNote(s: $0.string, f: $0.fret, p: $0.pitch, t: jTech($0.tech)) }
                for n in notes { ids[n.string] = n.id }
                let techs = notes.map(\.tech)
                jb.tap = techs.contains { $0.tapping } ? true : nil
                jb.trem = techs.lazy.compactMap(\.tremoloPicking).first?.rawValue
                jb.whammy = techs.lazy.compactMap(\.whammy).first.map(jBend)
                jb.pick = techs.lazy.compactMap(\.pickStroke).first?.rawValue
                jb.brush = techs.lazy.compactMap(\.brush).first?.rawValue
            }
            if !hits.isEmpty { jb.hits = hits.map(\.rawValue) }
            if !ghostHits.isEmpty { jb.ghosts = ghostHits.map(\.rawValue) }
            if !accents.isEmpty {
                jb.accents = Dictionary(uniqueKeysWithValues: accents.map { (String($0.key.rawValue), $0.value.rawValue) })
            }
            beats.append(jb)
            refs.append(AlphaTabBeatRef(start: GridPoint(absoluteTick: start), length: piece.length,
                                        noteIDs: ids, pieces: hits))
        }

        func fillRests(from a: Int, to b: Int) {
            var c = a
            while c < b {
                let p = pickPiece(at: c, atMost: b - c, track: track)
                emit(p, at: c)
                c += p.length
            }
        }

        // Grupos de ataques del compás: (tick, notas o piezas).
        struct Group { var tick: Int; var notes: [TabNote]; var hits: [DrumPiece]; var ghosts: [DrumPiece] = []
                      var accents: [DrumPiece: TabAccent] = [:]
                      var graces: [(piece: DrumPiece, grace: TabGrace)] = [] }
        var groups: [Int: Group] = [:]
        if track.kind == .drums {
            for h in track.hits where (barStart..<barEnd).contains(h.at.absoluteTick) {
                groups[h.at.absoluteTick, default: Group(tick: h.at.absoluteTick, notes: [], hits: [])].hits.append(h.piece)
                if h.ghost { groups[h.at.absoluteTick]?.ghosts.append(h.piece) }
                if let a = h.accent { groups[h.at.absoluteTick]?.accents[h.piece] = a }
                if let g = h.grace { groups[h.at.absoluteTick]?.graces.append((h.piece, g)) }
            }
        } else {
            for n in track.notes where (barStart..<barEnd).contains(n.start.absoluteTick) {
                groups[n.start.absoluteTick, default: Group(tick: n.start.absoluteTick, notes: [], hits: [])].notes.append(n)
            }
        }
        let ordered = groups.values.sorted { $0.tick < $1.tick }

        var cursor = barStart
        for (i, g) in ordered.enumerated() {
            if g.tick < cursor { continue }
            fillRests(from: cursor, to: g.tick)
            let nextOnset = i + 1 < ordered.count ? ordered[i + 1].tick : barEnd
            var wanted = nextOnset - g.tick
            if track.kind == .drums {
                let beat = g.tick / TabScore.ticksPerBeat
                let step = track.subdivisions.indices.contains(beat) ? track.subdivisions[beat].tickStep : 3
                wanted = min(wanted, step)
            } else {
                wanted = min(wanted, g.notes.map(\.duration).max() ?? wanted)
            }
            let piece = pickPiece(at: g.tick, atMost: max(wanted, 1), track: track)
            let count = track.tuning?.strings.count ?? 0
            let notes = g.notes.sorted { track.kind == .vocal ? $0.pitch < $1.pitch : $0.string > $1.string }.compactMap { n -> (string: Int, fret: Int, id: Int, tech: TabTechniques, pitch: Int?)? in
                // Voz: sin cuerdas ni trastes, solo la altura.
                if track.kind == .vocal { return (0, 0, n.id, n.techniques, n.pitch) }
                guard let fret = track.fret(of: n) else { return nil }
                return (jsonString(forScoreString: n.string, stringCount: count), fret, n.id, n.techniques, nil)
            }
            emit(piece, at: g.tick, notes: notes, hits: g.hits.sorted { $0.rawValue < $1.rawValue },
                 ghostHits: g.ghosts.sorted { $0.rawValue < $1.rawValue }, accents: g.accents,
                 drumGraces: g.graces.sorted { $0.piece.rawValue < $1.piece.rawValue })
            cursor = g.tick + piece.length
        }
        if cursor < barEnd { fillRests(from: cursor, to: barEnd) }
        return (beats, refs)
    }
}

extension TabBend {
    /// Puntos que alphaTab 1.9.0 lee por tipo al dibujar (`BendNoteHeadGroupGlyph`/`TabBendGlyph`, `bendPoints[i]`):
    /// bend-release lee el 0, el 1 (la cima) y el 3 (el final), como lo guarda Guitar Pro con la cima duplicada; los
    /// demás tipos (salvo custom, que los recorre) leen el 0 y el 1.
    static func alphaTabMinimumPoints(_ kind: Kind) -> Int {
        switch kind {
        case .bendRelease: 4
        case .custom: 0
        default: 2
        }
    }

    /// La curva con los puntos que alphaTab espera para su tipo: si faltan, se duplica la cima (el primer punto de
    /// valor máximo) en su misma posición, como hace Guitar Pro; la forma no cambia.
    func paddedForAlphaTab() -> TabBend {
        var pts = points
        guard let first = pts.first else { return self }
        if pts.count == 1 { pts.append(TabBendPoint(position: TabBend.maxPosition, value: first.value)) }
        while pts.count < Self.alphaTabMinimumPoints(type) {
            let top = pts.indices.max { pts[$0].value < pts[$1].value || (pts[$0].value == pts[$1].value && $0 > $1) }!
            // La cima no es el último punto: el final queda en el índice 3.
            let peak = top == pts.count - 1 ? max(0, pts.count - 2) : top
            pts.insert(pts[peak], at: peak + 1)
        }
        return TabBend(type: type, points: pts)
    }

    /// Curva con como mucho `maxPoints` puntos, conservando el tipo, el primero, el último y los puntos que más
    /// separan la curva de la recta entre los conservados (los picos primero).
    func simplified(maxPoints: Int) -> TabBend {
        guard points.count > maxPoints, maxPoints >= 2 else { return self }
        var keep: Set<Int> = [0, points.count - 1]
        while keep.count < maxPoints {
            let sorted = keep.sorted()
            var best: (index: Int, error: Double)?
            for (a, b) in zip(sorted, sorted.dropFirst()) {
                let pa = points[a], pb = points[b]
                for i in (a + 1)..<b {
                    let p = points[i]
                    let span = Double(pb.position - pa.position)
                    let t = span == 0 ? 0 : Double(p.position - pa.position) / span
                    let line = Double(pa.value) + t * Double(pb.value - pa.value)
                    let err = abs(Double(p.value) - line)
                    if best == nil || err > best!.error { best = (i, err) }
                }
            }
            guard let b = best else { break }
            keep.insert(b.index)
        }
        return TabBend(type: type, points: keep.sorted().map { points[$0] })
    }
}
