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
    private struct JNote: Encodable { var s: Int; var f: Int }
    private struct JBeat: Encodable {
        var d: Int
        var dots: Int?
        var tuplet: Int?
        var notes: [JNote]?
        var hits: [Int]?
    }
    private struct JTrack: Encodable {
        var name: String
        var kind: String
        var tuning: [Int]?
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
        for track in score.tracks {
            var jbars: [[JBeat]] = []
            var bmap: [[AlphaTabBeatRef]] = []
            for bar in score.bars {
                let (jb, refs) = convertBar(track: track, bar: bar, score: score)
                jbars.append(jb)
                bmap.append(refs)
            }
            jtracks.append(JTrack(name: track.name, kind: track.kind.rawValue,
                                  tuning: track.tuning.map { Array($0.strings.reversed()) }, bars: jbars))
            maps.append(bmap)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(JScore(title: title, artist: artist, bars: bars, tracks: jtracks))
        return AlphaTabScore(json: String(decoding: data, as: UTF8.self), trackIDs: score.tracks.map(\.id), beats: maps)
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
        var beats: [JBeat] = []
        var refs: [AlphaTabBeatRef] = []

        func emit(_ piece: Piece, at start: Int, notes: [(string: Int, fret: Int, id: Int)] = [], hits: [DrumPiece] = []) {
            var jb = JBeat(d: piece.d, dots: piece.dots > 0 ? piece.dots : nil, tuplet: piece.tuplet)
            var ids: [Int: Int] = [:]
            if !notes.isEmpty {
                jb.notes = notes.map { JNote(s: $0.string, f: $0.fret) }
                for n in notes { ids[n.string] = n.id }
            }
            if !hits.isEmpty { jb.hits = hits.map(\.rawValue) }
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
        struct Group { var tick: Int; var notes: [TabNote]; var hits: [DrumPiece] }
        var groups: [Int: Group] = [:]
        if track.kind == .drums {
            for h in track.hits where (barStart..<barEnd).contains(h.at.absoluteTick) {
                groups[h.at.absoluteTick, default: Group(tick: h.at.absoluteTick, notes: [], hits: [])].hits.append(h.piece)
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
            let notes = g.notes.sorted { $0.string > $1.string }.compactMap { n -> (Int, Int, Int)? in
                guard let fret = track.fret(of: n) else { return nil }
                return (jsonString(forScoreString: n.string, stringCount: count), fret, n.id)
            }
            emit(piece, at: g.tick, notes: notes, hits: g.hits.sorted { $0.rawValue < $1.rawValue })
            cursor = g.tick + piece.length
        }
        if cursor < barEnd { fillRests(from: cursor, to: barEnd) }
        return (beats, refs)
    }
}
