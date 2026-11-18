/// Por qué se niega una edición.
public enum TabEditError: Error, Equatable, Sendable {
    case unknownTrack
    case unknownNote
    /// La operación no es para este tipo de pista (notas en batería, golpes en guitarra…).
    case wrongTrackKind
    case stringOutOfRange
    /// El traste saldría de 0–24.
    case fretOutOfRange
    /// Ya hay otra nota que empieza en ese punto en esa cuerda.
    case stringOccupied
    /// El punto no existe o no es de la subdivisión de su pulso.
    case invalidPosition
    /// Duración ≤ 0, más allá del final o acabando fuera de un punto de la rejilla.
    case invalidDuration
    /// Ligadura de duración sin una nota anterior de la misma cuerda y altura que acabe donde empieza esta.
    case noTieOrigin
}

/// Edición de una `TabScore` con deshacer y rehacer (mini-spec Fase 5, decisión 4). Cada operación guarda la pista
/// entera que cambia: deshacer la restaura tal cual, así que la partitura vuelve a ser idéntica.
public struct TabEditor: Sendable {
    /// Pasos que se recuerdan para deshacer.
    public static let undoLimit = 200

    public private(set) var score: TabScore
    private var undoStack: [TabTrack] = []
    private var redoStack: [TabTrack] = []

    public init(score: TabScore) {
        self.score = score
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    // MARK: Guitarra y bajo

    /// Cambia el traste de la nota en su cuerda (cambia su altura).
    public mutating func setFret(_ fret: Int, trackID: String, noteID: Int) throws {
        try editNote(trackID: trackID, noteID: noteID) { track, i in
            guard Tuning.fretRange.contains(fret) else { throw TabEditError.fretOutOfRange }
            track.notes[i].pitch = track.tuning!.strings[track.notes[i].string - 1] + fret
        }
    }

    /// Pasa la nota a otra cuerda con la misma altura.
    public mutating func moveNote(trackID: String, noteID: Int, toString string: Int) throws {
        try editNote(trackID: trackID, noteID: noteID) { track, i in
            let strings = track.tuning!.strings
            guard (1...strings.count).contains(string) else { throw TabEditError.stringOutOfRange }
            guard Tuning.fretRange.contains(track.notes[i].pitch - strings[string - 1]) else {
                throw TabEditError.fretOutOfRange
            }
            let note = track.notes[i]
            if track.notes.contains(where: { $0.id != note.id && $0.start == note.start && $0.string == string }) {
                throw TabEditError.stringOccupied
            }
            track.notes[i].string = string
        }
    }

    public mutating func deleteNote(trackID: String, noteID: Int) throws {
        try editNote(trackID: trackID, noteID: noteID) { track, i in track.notes.remove(at: i) }
    }

    /// Cambia la duración (ticks) de la nota.
    public mutating func setDuration(_ duration: Int, trackID: String, noteID: Int) throws {
        let score = self.score
        try editNote(trackID: trackID, noteID: noteID) { track, i in
            try Self.checkDuration(duration, from: track.notes[i].start, track: track, score: score)
            track.notes[i].duration = duration
        }
    }

    /// Añade una nota en `string` y `fret`, en `start` con `duration` ticks. Devuelve su id.
    @discardableResult
    public mutating func addNote(trackID: String, string: Int, fret: Int, at start: GridPoint, duration: Int,
                                 amplitude: Float = 1) throws -> Int {
        let score = self.score
        var newID = 0
        try edit(trackID: trackID) { track in
            guard track.kind != .drums, let strings = track.tuning?.strings else { throw TabEditError.wrongTrackKind }
            guard (1...strings.count).contains(string) else { throw TabEditError.stringOutOfRange }
            guard Tuning.fretRange.contains(fret) else { throw TabEditError.fretOutOfRange }
            guard start.tick >= 0, start.tick < TabScore.ticksPerBeat,
                  score.isValidPoint(start.absoluteTick, subdivisions: track.subdivisions, allowEnd: false)
            else { throw TabEditError.invalidPosition }
            try Self.checkDuration(duration, from: start, track: track, score: score)
            if track.notes.contains(where: { $0.start == start && $0.string == string }) {
                throw TabEditError.stringOccupied
            }
            newID = (track.notes.map(\.id).max() ?? 0) + 1
            track.notes.append(TabNote(id: newID, pitch: strings[string - 1] + fret, string: string, start: start,
                                       duration: duration, amplitude: amplitude))
            track.sortContents()
        }
        return newID
    }

    /// Cambia la afinación de la pista: reasigna cuerdas y trastes conservando las alturas.
    @discardableResult
    public mutating func setTuning(_ tuning: Tuning, trackID: String) throws -> TabBuildReport {
        var report = TabBuildReport()
        try edit(trackID: trackID) { track in
            guard track.kind == .guitar || track.kind == .bass else { throw TabEditError.wrongTrackKind }
            (track, report) = TabTrackBuilder.retuned(track, to: tuning)
        }
        return report
    }

    // MARK: Batería

    /// Pone (`present` true) o quita el golpe de `piece` en `point`. Sin cambio no ocupa un paso de deshacer.
    public mutating func setHit(_ piece: DrumPiece, at point: GridPoint, present: Bool, trackID: String) throws {
        let score = self.score
        try edit(trackID: trackID) { track in
            guard track.kind == .drums else { throw TabEditError.wrongTrackKind }
            guard point.tick >= 0, point.tick < TabScore.ticksPerBeat,
                  score.isValidPoint(point.absoluteTick, subdivisions: track.subdivisions, allowEnd: false)
            else { throw TabEditError.invalidPosition }
            let hit = TabDrumHit(piece: piece, at: point)
            if present {
                if !track.hits.contains(where: { $0.isSameHit(as: hit) }) { track.hits.append(hit) }
            } else {
                track.hits.removeAll { $0.isSameHit(as: hit) }
            }
            track.sortContents()
        }
    }

    // MARK: Deshacer

    @discardableResult
    public mutating func undo() -> Bool {
        guard let previous = undoStack.popLast(), let i = score.trackIndex(id: previous.id) else { return false }
        redoStack.append(score.tracks[i])
        score.tracks[i] = previous
        return true
    }

    @discardableResult
    public mutating func redo() -> Bool {
        guard let next = redoStack.popLast(), let i = score.trackIndex(id: next.id) else { return false }
        undoStack.append(score.tracks[i])
        score.tracks[i] = next
        return true
    }

    // MARK: Internos

    mutating func edit(trackID: String, _ body: (inout TabTrack) throws -> Void) throws {
        guard let i = score.trackIndex(id: trackID) else { throw TabEditError.unknownTrack }
        var track = score.tracks[i]
        try body(&track)
        guard track != score.tracks[i] else { return }
        undoStack.append(score.tracks[i])
        if undoStack.count > Self.undoLimit { undoStack.removeFirst() }
        redoStack.removeAll()
        score.tracks[i] = track
    }

    private mutating func editNote(trackID: String, noteID: Int,
                                   _ body: (inout TabTrack, Int) throws -> Void) throws {
        try edit(trackID: trackID) { track in
            guard track.kind != .drums, track.tuning != nil else { throw TabEditError.wrongTrackKind }
            guard let i = track.notes.firstIndex(where: { $0.id == noteID }) else { throw TabEditError.unknownNote }
            try body(&track, i)
            track.sortContents()
        }
    }

    private static func checkDuration(_ duration: Int, from start: GridPoint, track: TabTrack,
                                      score: TabScore) throws {
        let end = start.absoluteTick + duration
        guard duration > 0, end <= score.totalTicks,
              score.isValidPoint(end, subdivisions: track.subdivisions, allowEnd: true)
        else { throw TabEditError.invalidDuration }
    }
}
