import Foundation

/// Un stem de la tablatura del tema con el que se empareja una pista de Songsterr.
public struct SongsterrStemSlot: Sendable, Equatable {
    /// Id de la pista de tablatura del stem (`guitar-left`, `bass`, `drums`…).
    public var id: String
    public var name: String
    public var kind: TabTrackKind
    /// Papel con el que el alineador mide el stem.
    public var role: SongsterrStemRole

    public init(id: String, name: String, kind: TabTrackKind, role: SongsterrStemRole) {
        self.id = id
        self.name = name
        self.kind = kind
        self.role = role
    }
}

/// Pista de Songsterr elegida para un stem (`track` nil = transcripción automática).
public struct SongsterrAssignment: Sendable, Equatable {
    public var stemID: String
    /// Índice de la pista en las pistas del tema de Songsterr.
    public var track: Int?
    /// Parecido con el audio que midió el alineador; nil si no hay medida (p. ej. elegida a mano sin solape).
    public var confidence: Double?
    /// Solo el stem solista: pista de cada sección de solo (con `track` nil, la pista solista lleva solo las notas de
    /// Songsterr de estas secciones).
    public var solos: [SongsterrSoloAssignment]

    public init(stemID: String, track: Int?, confidence: Double?, solos: [SongsterrSoloAssignment] = []) {
        self.stemID = stemID
        self.track = track
        self.confidence = confidence
        self.solos = solos
    }

    /// Lleva notas de Songsterr: pista entera o alguna sección de solo con pista.
    public var usesSongsterr: Bool { track != nil || solos.contains { $0.track != nil } }
}

/// Pista de Songsterr elegida para una sección de solo del stem solista (`track` nil = sin notas de Songsterr ahí).
public struct SongsterrSoloAssignment: Sendable, Equatable {
    /// Segundos de canción de la sección.
    public var span: ClosedRange<Double>
    public var track: Int?
    public var confidence: Double?

    public init(span: ClosedRange<Double>, track: Int?, confidence: Double?) {
        self.span = span
        self.track = track
        self.confidence = confidence
    }
}

/// Una pista de Songsterr que se puede elegir para un stem.
public struct SongsterrTrackChoice: Sendable, Equatable {
    public var track: Int
    public var name: String
    public var similarity: Double?

    public init(track: Int, name: String, similarity: Double?) {
        self.track = track
        self.name = name
        self.similarity = similarity
    }
}

/// Resultado de aplicar el emparejamiento a la alineación.
public struct SongsterrImportResult: Sendable {
    /// Rejilla del tema con las pistas importadas: las emparejadas con el id del stem, las demás (extras) con su
    /// `songsterr-<índice>`.
    public var score: TabScore
    public var assignments: [SongsterrAssignment]
    /// Stems sin pareja: los transcribe la automática.
    public var automaticStemIDs: [String]
    /// Ids de las pistas extra (sin stem), que solo suenan con «Oír transcripción».
    public var extraTrackIDs: [String]
}

/// Emparejamiento editable entre los stems del tema y las pistas de Songsterr (mini-spec Fase 5b, decisiones 3 a 6),
/// sin ninguna dependencia de la app.
///
/// La propuesta inicial es la del alineador (`SongsterrAlignment.pairs`); un stem sin pareja queda en automática, salvo
/// bajo y batería cuando el tema trae una sola pista de ese tipo (la de Songsterr gana a la automática, decisión 6).
public struct SongsterrImportPlan: Sendable {
    public static let converterVersion = SongsterrTrackConverter.version

    public let slots: [SongsterrStemSlot]
    public let alignment: SongsterrAlignment
    public let tracks: [SongsterrTrack]
    public let songId: Int
    public let revisionId: Int
    public private(set) var assignments: [SongsterrAssignment]

    public init(alignment: SongsterrAlignment, tracks: [SongsterrTrack], slots: [SongsterrStemSlot],
                songId: Int, revisionId: Int) {
        self.alignment = alignment
        self.tracks = tracks
        self.slots = slots
        self.songId = songId
        self.revisionId = revisionId
        var out: [SongsterrAssignment] = []
        for slot in slots {
            if slot.role == .guitarLead {
                // Solista: solo las secciones de solo, cada una con su pista (sin secciones, automática).
                let solos = alignment.soloPairs.map { p in
                    let ok = p.track.map { tracks.indices.contains($0) && Self.compatible(tracks[$0].kind, slot.kind) } ?? false
                    return SongsterrSoloAssignment(span: p.span, track: ok ? p.track : nil, confidence: ok ? p.confidence : nil)
                }
                out.append(SongsterrAssignment(stemID: slot.id, track: nil, confidence: nil, solos: solos))
                continue
            }
            if let pair = alignment.pairs.first(where: { $0.role == slot.role }), tracks.indices.contains(pair.track),
               Self.compatible(tracks[pair.track].kind, slot.kind) {
                out.append(SongsterrAssignment(stemID: slot.id, track: pair.track, confidence: pair.confidence))
                continue
            }
            let same = tracks.indices.filter { tracks[$0].kind == slot.kind }
            if slot.kind != .guitar, same.count == 1 {
                out.append(SongsterrAssignment(stemID: slot.id, track: same[0], confidence: nil))
            } else {
                out.append(SongsterrAssignment(stemID: slot.id, track: nil, confidence: nil))
            }
        }
        assignments = out
    }

    static func compatible(_ track: TabTrackKind, _ slot: TabTrackKind) -> Bool { track == slot }

    // MARK: Edición

    public func assignment(for stemID: String) -> SongsterrAssignment? { assignments.first { $0.stemID == stemID } }

    /// Pistas que se pueden elegir para el stem (las de su mismo tipo), con el parecido medido.
    public func choices(for stemID: String) -> [SongsterrTrackChoice] {
        guard let slot = slots.first(where: { $0.id == stemID }) else { return [] }
        return tracks.indices.filter { Self.compatible(tracks[$0].kind, slot.kind) }.map { i in
            let sim = alignment.candidates.first { $0.role == slot.role && $0.track == i }?.similarity
            return SongsterrTrackChoice(track: i, name: tracks[i].name, similarity: sim)
        }
    }

    /// Elige la pista de un stem (`nil` = transcripción automática). Ignora stems o pistas que no valen.
    @discardableResult
    public mutating func assign(stemID: String, track: Int?) -> Bool {
        guard let k = assignments.firstIndex(where: { $0.stemID == stemID }),
              let slot = slots.first(where: { $0.id == stemID }) else { return false }
        guard let track else {
            assignments[k].track = nil
            assignments[k].confidence = nil
            return true
        }
        guard tracks.indices.contains(track), Self.compatible(tracks[track].kind, slot.kind) else { return false }
        // El solista no lleva pistas enteras (duplicaría las de L o R): solo secciones, con `assign(stemID:solo:track:)`.
        guard slot.role != .guitarLead else { return false }
        assignments[k].track = track
        assignments[k].confidence = alignment.pairs.first { $0.role == slot.role && $0.track == track }?.confidence
            ?? alignment.candidates.first { $0.role == slot.role && $0.track == track }?.similarity
        return true
    }

    /// Pistas que se pueden elegir para una sección de solo del stem (las de su tipo), con el parecido en la sección.
    public func soloChoices(for stemID: String, solo: Int) -> [SongsterrTrackChoice] {
        guard let slot = slots.first(where: { $0.id == stemID }), alignment.soloPairs.indices.contains(solo) else { return [] }
        let pair = alignment.soloPairs[solo]
        return tracks.indices.filter { Self.compatible(tracks[$0].kind, slot.kind) }.map { i in
            SongsterrTrackChoice(track: i, name: tracks[i].name,
                                 similarity: pair.candidates.first { $0.track == i }?.similarity)
        }
    }

    /// Elige la pista de una sección de solo (`nil` = sin notas de Songsterr en ella). Ignora lo que no vale.
    @discardableResult
    public mutating func assign(stemID: String, solo: Int, track: Int?) -> Bool {
        guard let k = assignments.firstIndex(where: { $0.stemID == stemID }),
              let slot = slots.first(where: { $0.id == stemID }), assignments[k].solos.indices.contains(solo) else { return false }
        guard let track else {
            assignments[k].solos[solo].track = nil
            assignments[k].solos[solo].confidence = nil
            return true
        }
        guard tracks.indices.contains(track), Self.compatible(tracks[track].kind, slot.kind) else { return false }
        assignments[k].solos[solo].track = track
        assignments[k].solos[solo].confidence = alignment.soloPairs.indices.contains(solo)
            ? alignment.soloPairs[solo].candidates.first { $0.track == track }?.similarity : nil
        return true
    }

    /// Todo en automática (el tema sigue con la transcripción de la Fase 5).
    public mutating func useAutomaticForAll() {
        for k in assignments.indices {
            assignments[k].track = nil
            assignments[k].confidence = nil
            for s in assignments[k].solos.indices { assignments[k].solos[s].track = nil; assignments[k].solos[s].confidence = nil }
        }
    }

    // MARK: Lectura

    /// Stems que transcribe la automática (sin pareja ni secciones de solo con pista).
    public var automaticStemIDs: [String] { assignments.filter { !$0.usesSongsterr }.map(\.stemID) }

    /// Pistas de Songsterr que no usa ningún stem (voz, teclados, una tercera guitarra…).
    public var extraTracks: [Int] {
        let used = Set(assignments.compactMap(\.track))
        return tracks.indices.filter { !used.contains($0) }
    }

    /// Id de la pista extra en la tablatura.
    public static func extraID(_ index: Int) -> String { "songsterr-\(index)" }

    /// Avisos de la importación en español: diferencias de estructura (en qué compases), adornos que `TabScore` no
    /// representa (contados) y notas que no cupieron.
    public var warnings: [String] {
        var out: [String] = []
        for w in alignment.structureWarnings {
            let bar = w.bar + 1
            let at = Self.clock(w.time)
            if let whole = w.wholeBars, whole != 0 {
                let n = abs(whole)
                let unit = n == 1 ? "compás" : "compases"
                out.append(whole > 0
                    ? "Compás \(bar) (\(at)): la grabación tiene \(n) \(unit) de más que la tablatura de Songsterr."
                    : "Compás \(bar) (\(at)): a la grabación le faltan \(n) \(unit) respecto a la tablatura de Songsterr.")
            } else {
                let n = abs(w.beats)
                let unit = n == 1 ? "pulso" : "pulsos"
                out.append(w.beats > 0
                    ? "Compás \(bar) (\(at)): la grabación tiene \(n) \(unit) de más."
                    : "Compás \(bar) (\(at)): a la grabación le faltan \(n) \(unit).")
            }
        }
        let used = Set(assignments.compactMap(\.track) + assignments.flatMap { $0.solos.compactMap(\.track) })
            .union(extraTracks)
        let ornaments = used.reduce(0) { $0 + tracks[$1].report.notesWithOrnaments }
        if ornaments > 0 {
            var byKind: [SongsterrOrnament: Int] = [:]
            var keys: [String: Int] = [:]
            for i in used {
                byKind.merge(tracks[i].report.ornaments, uniquingKeysWith: +)
                keys.merge(tracks[i].report.unknownKeys, uniquingKeysWith: +)
            }
            let detail = SongsterrOrnament.allCases.compactMap { o -> String? in
                guard let n = byKind[o] else { return nil }
                if o == .unknownKey {
                    let names = keys.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
                    return names.isEmpty ? "\(Self.label(o)) \(n)" : "\(Self.label(o)) \(n) (\(names))"
                }
                return "\(Self.label(o)) \(n)"
            }
            out.append("\(ornaments) notas con adornos que la tablatura aún no representa se importaron sin ellos"
                + (detail.isEmpty ? "." : ": \(detail.joined(separator: ", "))."))
        }
        let unknownDrums = used.reduce(0) { $0 + tracks[$1].report.unknownDrumNotes }
        if unknownDrums > 0 { out.append("\(unknownDrums) golpes de percusión sin pieza equivalente se omitieron.") }
        let dropped = used.reduce(0) { sum, i in
            let p = alignment.placements.indices.contains(i) ? alignment.placements[i] : nil
            return sum + (p?.droppedOutsideGrid ?? 0) + (p?.droppedInExtraBeats ?? 0)
        }
        if dropped > 0 { out.append("\(dropped) notas quedaron fuera del audio del tema y se quitaron.") }
        return out
    }

    /// Nombre en el aviso de un adorno sin representar.
    static func label(_ o: SongsterrOrnament) -> String {
        switch o {
        case .graceNote: "notas de adorno sin nota principal (se quitan)"
        case .unknownSlide: "slides de tipo desconocido"
        case .unknownHarmonic: "armónicos de tipo desconocido"
        case .unknownTremolo: "trémolos de púa de figura desconocida"
        case .drumTechnique: "técnicas en golpes de batería"
        case .unknownKey: "otros"
        }
    }

    /// «m:ss» de un instante, como en los avisos (para «Solo n (m:ss)»).
    public static func clockText(_ t: Double) -> String { clock(t) }

    static func clock(_ t: Double) -> String {
        let s = Int(t.rounded())
        return "\(s / 60):" + (s % 60 < 10 ? "0" : "") + "\(s % 60)"
    }

    // MARK: Resultado

    /// Aplica el emparejamiento: renombra `songsterr-<i>` al id del stem (una pista elegida por dos stems se copia
    /// en cada uno) y deja las no usadas como extras. Todas llevan la huella de la importación.
    public func build() -> SongsterrImportResult {
        var score = alignment.score
        let byID = Dictionary(uniqueKeysWithValues: score.tracks.map { ($0.id, $0) })
        func stamp(_ i: Int) -> ImportedTrackStamp {
            ImportedTrackStamp(songId: songId, revisionId: revisionId, converterVersion: Self.converterVersion,
                               partId: tracks[i].partId)
        }
        var out: [TabTrack] = []
        for a in assignments {
            if a.track == nil, let slot = slots.first(where: { $0.id == a.stemID }),
               var t = soloTrack(a.solos, in: score, byID: byID) {
                t.id = slot.id
                t.name = slot.name
                t.imported = stamp(a.solos.first { $0.track != nil }!.track!)
                out.append(t)
                continue
            }
            guard let i = a.track, var t = byID[Self.extraID(i)], let slot = slots.first(where: { $0.id == a.stemID }) else { continue }
            t.id = slot.id
            t.name = slot.name
            t.source = nil
            t.imported = stamp(i)
            out.append(t)
        }
        var extraIDs: [String] = []
        for i in extraTracks {
            guard var t = byID[Self.extraID(i)] else { continue }
            t.source = nil
            t.imported = stamp(i)
            out.append(t)
            extraIDs.append(t.id)
        }
        score.tracks = out
        return SongsterrImportResult(score: score, assignments: assignments, automaticStemIDs: automaticStemIDs,
                                     extraTrackIDs: extraIDs)
    }

    /// Pista solista: de cada sección de solo con pista, las notas de esa pista que empiezan dentro de la sección
    /// (`span.lowerBound ≤ inicio < span.upperBound`), con su subdivisión de pulso. Fuera de los solos, vacía.
    /// Afinación: la de la primera sección con pista. nil si ninguna sección tiene pista.
    func soloTrack(_ solos: [SongsterrSoloAssignment], in score: TabScore, byID: [String: TabTrack]) -> TabTrack? {
        let used = solos.compactMap { s in s.track.flatMap { byID[Self.extraID($0)] }.map { (span: s.span, track: $0) } }
        guard let first = used.first?.track else { return nil }
        var subdivisions = first.subdivisions
        var notes: [TabNote] = []
        for (span, src) in used {
            for n in src.notes {
                let t = score.time(of: n.start)
                guard span.lowerBound <= t, t < span.upperBound else { continue }
                notes.append(n)
                let beat = n.start.beat
                if subdivisions.indices.contains(beat), src.subdivisions.indices.contains(beat) {
                    subdivisions[beat] = src.subdivisions[beat]
                }
            }
        }
        var track = TabTrack(id: first.id, name: first.name, kind: first.kind, tuning: first.tuning, source: nil,
                             subdivisions: subdivisions, notes: notes)
        track.sortContents()
        for j in track.notes.indices { track.notes[j].id = j + 1 }
        return track
    }
}
