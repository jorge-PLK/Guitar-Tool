/// Golpe de batería detectado (tiempo en segundos de canción y pieza).
public struct DrumOnset: Sendable, Equatable {
    public var time: Double
    public var piece: DrumPiece

    public init(time: Double, piece: DrumPiece) {
        self.time = time
        self.piece = piece
    }
}

/// Avisos de la construcción de una pista (o de un cambio de afinación).
public struct TabBuildReport: Sendable, Equatable {
    /// Notas subidas o bajadas una octava por salirse del registro de la afinación.
    public var shiftedOctave: Int
    /// Notas quitadas: más notas que cuerdas, unísonos tras el cambio de octava o acordes sin digitación posible.
    public var droppedNotes: Int

    public init(shiftedOctave: Int = 0, droppedNotes: Int = 0) {
        self.shiftedOctave = shiftedOctave
        self.droppedNotes = droppedNotes
    }
}

/// De notas o golpes a una pista de `TabScore` sobre su rejilla (mini-spec Fase 5, «Transcripción»).
public enum TabTrackBuilder {
    /// Versión de las reglas de cuantización y digitación; entra en la huella de cada pista.
    public static let parametersVersion = 1

    /// Pista de guitarra o bajo desde las notas de Basic Pitch.
    ///
    /// Rejilla: subdivisión por pulso con menor error, ataques al punto más cercano, duración hasta el final de la
    /// nota o el siguiente ataque de la pista (cuantizada, al menos un punto). Bajo: una nota por ataque, la de más
    /// amplitud. Cuerdas y trastes por Viterbi (`Fingering`).
    public static func pitchedTrack(id: String, name: String, kind: TabTrackKind, tuning: Tuning,
                                    source: TrackSourceFingerprint?, notes events: [NoteEvent],
                                    in score: TabScore) -> (track: TabTrack, report: TabBuildReport) {
        precondition(kind != .drums, "pitchedTrack es para guitarra o bajo")
        let times = score.beats.map(\.time)
        let subdivisions = score.chooseSubdivisions(onsets: events.map(\.start))

        struct Q { var pitch: Int; var start: Int; var end: Int; var amplitude: Float }
        var byStart: [Int: [Q]] = [:]
        for e in events {
            let start = score.snapTick(e.start, subdivisions: subdivisions, allowEnd: false, times: times)
            let end = score.snapTick(e.end, subdivisions: subdivisions, allowEnd: true, times: times)
            let q = Q(pitch: e.pitch, start: start, end: end, amplitude: e.amplitude)
            var group = byStart[start, default: []]
            if kind == .bass {
                if let best = group.first, best.amplitude >= q.amplitude { continue }
                group = [q]
            } else if let j = group.firstIndex(where: { $0.pitch == q.pitch }) {
                group[j].amplitude = max(group[j].amplitude, q.amplitude)
                group[j].end = max(group[j].end, q.end)
            } else {
                group.append(q)
            }
            byStart[start] = group
        }

        let attacks = byStart.keys.sorted()
        var chords: [[Q]] = []
        for (i, start) in attacks.enumerated() {
            let next = i + 1 < attacks.count ? attacks[i + 1] : score.totalTicks
            let step = subdivisions[start / TabScore.ticksPerBeat].tickStep
            chords.append(byStart[start, default: []].map { q in
                var q = q
                q.end = min(q.end, next)
                if q.end <= q.start { q.end = min(q.start + step, next) }
                return q
            })
        }

        var flat: [Q] = []
        let inputs = chords.map { chord in
            chord.map { q -> Fingering.Input in
                flat.append(q)
                return Fingering.Input(pitch: q.pitch, amplitude: q.amplitude, ref: flat.count - 1)
            }
        }
        let result = Fingering.assign(chords: inputs, tuning: tuning)
        var notes: [TabNote] = []
        for placed in result.chords.flatMap({ $0 }) {
            let q = flat[placed.ref]
            notes.append(TabNote(id: 0, pitch: placed.pitch, string: placed.string,
                                 start: GridPoint(absoluteTick: q.start), duration: q.end - q.start,
                                 amplitude: q.amplitude))
        }
        var track = TabTrack(id: id, name: name, kind: kind, tuning: tuning, source: source,
                             subdivisions: subdivisions, notes: notes)
        track.sortContents()
        for i in track.notes.indices { track.notes[i].id = i + 1 }
        return (track, TabBuildReport(shiftedOctave: result.shiftedOctave, droppedNotes: result.dropped))
    }

    /// Pista de batería: subdivisión por pulso con los golpes, cada golpe al punto más cercano; un golpe por pieza
    /// y punto.
    public static func drumTrack(id: String, name: String, source: TrackSourceFingerprint?,
                                 onsets: [DrumOnset], in score: TabScore) -> TabTrack {
        let times = score.beats.map(\.time)
        let subdivisions = score.chooseSubdivisions(onsets: onsets.map(\.time))
        var hits = Set<TabDrumHit>()
        for o in onsets {
            let tick = score.snapTick(o.time, subdivisions: subdivisions, allowEnd: false, times: times)
            hits.insert(TabDrumHit(piece: o.piece, at: GridPoint(absoluteTick: tick)))
        }
        var track = TabTrack(id: id, name: name, kind: .drums, tuning: nil, source: source,
                             subdivisions: subdivisions, hits: Array(hits))
        track.sortContents()
        return track
    }

    /// La misma pista con otra afinación: mismas notas, inicios y duraciones; cuerdas y trastes de nuevo por Viterbi.
    /// Solo cambian de altura las notas que no caben en la nueva afinación (una octava, contadas en el aviso).
    static func retuned(_ track: TabTrack, to tuning: Tuning) -> (track: TabTrack, report: TabBuildReport) {
        var byStart: [Int: [Int]] = [:]
        for (i, n) in track.notes.enumerated() { byStart[n.start.absoluteTick, default: []].append(i) }
        let inputs = byStart.keys.sorted().map { start in
            byStart[start, default: []].map {
                Fingering.Input(pitch: track.notes[$0].pitch, amplitude: track.notes[$0].amplitude, ref: $0)
            }
        }
        let result = Fingering.assign(chords: inputs, tuning: tuning)
        var out = track
        out.tuning = tuning
        out.notes = result.chords.flatMap { $0 }.map { placed in
            var n = track.notes[placed.ref]
            n.pitch = placed.pitch
            n.string = placed.string
            return n
        }
        out.sortContents()
        return (out, TabBuildReport(shiftedOctave: result.shiftedOctave, droppedNotes: result.dropped))
    }
}
