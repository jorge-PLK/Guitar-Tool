import Foundation

/// JSON de una pista de Songsterr (el de su CDN, una revisión) → `SongsterrTrack` (mini-spec Fase 5b, «Código»,
/// parte 2). Guía: el conversor de `Metaphysics0/songsterr-downloader` (MIT) y `Probes/P5b-guitarra/eval_reference.py`.
///
/// Formato: `measures[]` con `signature` (vigente hasta el siguiente), `repeatStart`, `repeat` (veces que se toca),
/// `alternateEnding`, `marker` y `voices[].beats[]`; cada beat con `duration` = [num, den] de redonda (ya incluye
/// puntillos y tresillos), `rest`, `notes[]` (`string` 0 = la más aguda, `fret`, `tie`, adornos). `tuning` va de la
/// cuerda más aguda a la más grave. Batería: `instrumentId` 1024 y `fret` = nota de percusión GM. Tempo en
/// `automations.tempo[]` (`measure`, `position`, `bpm` de negra).
///
/// Técnicas (`TabTechniques`, ver `techniques(note:beat:)`): las claves de las pistas reales de El roce, Tornado Of
/// Souls y Aquellas cosas más las que lee el conversor de referencia. Las demás claves de beat o nota que no son de
/// ritmo ni de notación se cuentan como desconocidas, por nombre, en el aviso.
public enum SongsterrTrackConverter {
    /// Entra en la huella de las pistas importadas (mini-spec Fase 5b, «Datos»). 2: primer compás incompleto =
    /// anacrusa. 3: técnicas (bends, palm mute, ligados…).
    public static let version = 3

    /// `instrumentId` de batería en Songsterr.
    static let drumInstrumentId = 1024
    /// Programas GM de bajo (Acoustic Bass … Synth Bass 2).
    static let bassPrograms = 32...39
    /// Tempo si la pista no trae ninguno (el de MIDI por defecto).
    static let defaultTempo = 120.0
    /// Tope de compases tocados al desplegar repeticiones (un bucle mal formado no cuelga la app).
    static let maxPlayedBars = 20_000

    /// - Parameter isDrums: la marca `isDrums` del estado de la página, por si la pista no trae `instrumentId` 1024.
    public static func convert(_ data: Data, isDrums: Bool = false) throws -> SongsterrTrack {
        guard let json = try? JSONSerialization.jsonObject(with: data), let root = json as? [String: Any] else {
            throw SongsterrFormatError(reason: "la pista no es un objeto JSON")
        }
        guard let measures = root["measures"] as? [[String: Any]] else {
            throw SongsterrFormatError(reason: "la pista no tiene «measures»")
        }
        let instrumentId = int(root["instrumentId"])
        let instrumentName = root["instrument"] as? String ?? ""
        let kind: TabTrackKind
        if isDrums || instrumentId == drumInstrumentId || instrumentName.lowercased().contains("drum") {
            kind = .drums
        } else if bassPrograms.contains(instrumentId ?? -1) || instrumentName.lowercased().contains("bass") {
            kind = .bass
        } else {
            kind = .guitar
        }
        let tuning = (root["tuning"] as? [Any])?.compactMap(int) ?? []
        if kind != .drums && tuning.isEmpty {
            throw SongsterrFormatError(reason: "pista sin «tuning»")
        }

        var converter = Converter(kind: kind, tuning: kind == .drums ? [] : tuning)
        try converter.run(measures: measures, tempo: tempoPoints(root))
        converter.finish()
        return SongsterrTrack(name: root["name"] as? String ?? "", instrumentId: instrumentId,
                              songId: int(root["songId"]), revisionId: int(root["revisionId"]),
                              partId: int(root["partId"]), kind: kind, tuningStrings: converter.tuning,
                              bars: converter.bars, tempoChanges: converter.tempoChanges,
                              notes: converter.sortedNotes(), hits: converter.sortedHits(), report: converter.report)
    }

    // MARK: - Repeticiones

    /// Orden en que se tocan los compases: `repeatStart` abre, `repeat` = n cierra y se toca n veces en total (sin
    /// `repeatStart`, vuelve al principio o al final de la repetición anterior), y un compás con `alternateEnding`
    /// solo suena en las pasadas de su lista (o máscara de bits).
    static func playOrder(_ measures: [[String: Any]]) throws -> [Int] {
        var order: [Int] = []
        var i = 0, start = 0, pass = 1
        var jumpedBack = false
        var sectionEnd: Int?
        while i < measures.count {
            let m = measures[i]
            let endings = alternateEndings(m["alternateEnding"])
            if !jumpedBack {
                if let e = sectionEnd, i > e, endings.isEmpty {
                    start = i; pass = 1; sectionEnd = nil
                }
                if (m["repeatStart"] as? Bool) == true, sectionEnd == nil {
                    start = i; pass = 1
                }
            }
            jumpedBack = false
            let count = int(m["repeat"]) ?? int(m["repeatCount"]) ?? 0
            if !endings.isEmpty && !endings.contains(pass) {
                if count > 0 { sectionEnd = max(sectionEnd ?? i, i) }
                i += 1
                continue
            }
            order.append(i)
            guard order.count <= maxPlayedBars else {
                throw SongsterrFormatError(reason: "repeticiones sin final")
            }
            if count > 1 && pass < count {
                pass += 1
                i = start
                jumpedBack = true
                continue
            }
            if count > 0 { sectionEnd = max(sectionEnd ?? i, i) }
            i += 1
        }
        return order
    }

    static func alternateEndings(_ value: Any?) -> Set<Int> {
        if let list = value as? [Any] { return Set(list.compactMap(int)) }
        if let mask = int(value), mask > 0 { return Set((0..<31).filter { mask & (1 << $0) != 0 }.map { $0 + 1 }) }
        return []
    }

    // MARK: - Tempo y batería

    struct TempoPoint { var measure: Int; var position: Int; var type: Int; var bpm: Double }

    static func tempoPoints(_ root: [String: Any]) -> [TempoPoint] {
        let list = (root["automations"] as? [String: Any])?["tempo"] as? [[String: Any]] ?? []
        return list.compactMap { p in
            guard let measure = int(p["measure"]), let bpm = double(p["bpm"]), bpm > 0 else { return nil }
            return TempoPoint(measure: measure, position: int(p["position"]) ?? 0, type: int(p["type"]) ?? 4, bpm: bpm)
        }
    }

    /// Nota de percusión GM → pieza. Todos los platos van a 49 y los toms a 47, como en la Fase 5 («Transcripción»);
    /// el charles abierto (46) tiene pieza propia desde la Fase 5b.
    static func drumPiece(gm: Int) -> DrumPiece? {
        switch gm {
        case 35, 36: return .kick
        case 37, 38, 39, 40: return .snare            // aro, caja, palmada, caja eléctrica
        case 42, 44: return .hiHat                    // cerrado, de pie
        case 46: return .openHiHat
        case 41, 43, 45, 47, 48, 50: return .tom
        case 49, 51, 52, 53, 55, 57, 59: return .crash  // crash, ride, china, campana del ride, splash
        default: return nil
        }
    }

    // MARK: - Lectura tolerante

    static func int(_ v: Any?) -> Int? {
        if let n = v as? Int { return n }
        if let d = v as? Double, d == d.rounded() { return Int(d) }
        return nil
    }

    static func double(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let n = v as? Int { return Double(n) }
        return nil
    }

    static func flag(_ v: Any?) -> Bool { (v as? Bool) == true }

    /// Duración del beat en ticks: `duration` [num, den] de redonda; si falta, de `type`, `dots` y `tuplet`.
    static func beatTicks(_ beat: [String: Any]) -> (ticks: Int, exact: Bool)? {
        let whole = SongsterrTrack.ticksPerQuarter * 4
        if let d = beat["duration"] as? [Any], d.count == 2, let num = int(d[0]), let den = int(d[1]), num > 0, den > 0 {
            let scaled = whole * num
            return (Int((Double(scaled) / Double(den)).rounded()), scaled % den == 0)
        }
        guard let type = int(beat["type"]), type > 0 else { return nil }
        var value = Double(whole) / Double(type)
        let dots = int(beat["dots"]) ?? 0
        value *= 2 - pow(0.5, Double(max(0, dots)))
        if let n = int(beat["tuplet"]), n > 1 {
            value *= pow(2, floor(log2(Double(n)))) / Double(n)
        }
        let ticks = Int(value.rounded())
        return (ticks, abs(value - Double(ticks)) < 1e-9)
    }

    // MARK: - Técnicas

    /// Claves de beat que son de ritmo o de notación, o que se leen como técnica; las demás cuentan como desconocidas.
    /// `velocity` (dinámica), `text` y `chord` (nombre del acorde) no son adornos de nota y no entran en el aviso.
    static let knownBeatKeys: Set<String> = [
        "duration", "type", "dots", "dotted", "tuplet", "tupletStart", "tupletStop", "notes", "rest", "beamStart",
        "beamStop", "velocity", "text", "chord", "graceNote",
        "palmMute", "letRing", "vibrato", "wideVibrato", "vibratoWithTremoloBar", "pickStroke", "brushStroke",
        "upStroke", "downStroke", "tremolo",
    ]
    /// Ídem para las notas.
    static let knownNoteKeys: Set<String> = [
        "string", "fret", "tie", "rest",
        "bend", "slide", "harmonic", "harmonicFret", "dead", "ghost", "hp", "vibrato", "wideVibrato",
        "leftHandVibrato", "accentuated", "staccato", "palmMute", "letRing",
    ]
    /// `tone` de Songsterr por cuarto de tono: 100 = un tono, como en Guitar Pro (el de referencia divide entre 25).
    static let toneUnitsPerQuarterTone = 25.0

    /// Lo que se lee de una nota (con las técnicas de su beat).
    struct ReadTechniques {
        var techniques = TabTechniques()
        /// Curva del bend de esta nota sola (posición 0…60 de su duración); `techniques.bend` se pone al final,
        /// cuando se conocen las ligadas.
        var bend: [TabBendPoint]?
        var missing: [SongsterrOrnament] = []
        var unknownKeys: [String] = []
    }

    /// Mapeo Songsterr → `TabTechniques` (claves vistas en las pistas reales o en el conversor de referencia):
    /// `palmMute`/`letRing` (beat o nota), vibrato (`vibrato`, `wideVibrato`, `leftHandVibrato` "slight"/"wide",
    /// `vibratoWithTremoloBar`), `bend.points` (`tone` 100 = un tono), `slide`, `hp`, `harmonic` + `harmonicFret`,
    /// `dead`, `ghost`, `accentuated` (2 = fuerte), `staccato`, `pickStroke` y `brushStroke.direction`.
    static func techniques(note n: [String: Any], beat b: [String: Any]) -> ReadTechniques {
        var out = ReadTechniques()
        var t = TabTechniques()
        t.palmMute = truthy(b["palmMute"]) || truthy(n["palmMute"])
        t.letRing = truthy(b["letRing"]) || truthy(n["letRing"])

        let lhv = (n["leftHandVibrato"] as? String)?.lowercased()
        let barVibrato = (b["vibratoWithTremoloBar"] as? String)?.lowercased()
        if truthy(n["wideVibrato"]) || truthy(b["wideVibrato"]) || lhv == "wide"
            || (b["vibratoWithTremoloBar"] != nil && barVibrato != "slight") {
            t.vibrato = .wide
        } else if truthy(n["vibrato"]) || truthy(b["vibrato"]) || truthy(n["leftHandVibrato"]) || barVibrato != nil {
            t.vibrato = .slight
        }

        if let points = (n["bend"] as? [String: Any])?["points"] as? [[String: Any]] {
            let read = points.compactMap { p -> TabBendPoint? in
                guard let pos = double(p["position"]), let tone = double(p["tone"]) else { return nil }
                let position = min(TabBend.maxPosition, max(0, Int(pos.rounded())))
                return TabBendPoint(position: position, value: Int((tone / toneUnitsPerQuarterTone).rounded()))
            }.sorted { $0.position < $1.position }
            if read.count >= 2 { out.bend = read }
        }

        if let slide = n["slide"] as? String {
            switch slide.lowercased() {
            case "shift": t.slideOut = .shift
            case "legato": t.slideOut = .legato
            case "below", "into_from_below": t.slideIn = .intoFromBelow
            case "above", "into_from_above": t.slideIn = .intoFromAbove
            case "downwards", "out_down": t.slideOut = .outDown
            case "upwards", "out_up": t.slideOut = .outUp
            default: out.missing.append(.unknownSlide)
            }
        }

        t.hammerPull = truthy(n["hp"])
        if let h = n["harmonic"] as? String {
            if let type = TabHarmonicType(rawValue: h.lowercased()) {
                t.harmonic = TabHarmonic(type: type, fret: double(n["harmonicFret"]))
            } else {
                out.missing.append(.unknownHarmonic)
            }
        }
        t.dead = truthy(n["dead"])
        t.ghost = truthy(n["ghost"])
        if truthy(n["accentuated"]) { t.accent = int(n["accentuated"]) == 2 ? .heavy : .normal }
        t.staccato = truthy(n["staccato"])
        t.pickStroke = (b["pickStroke"] as? String).flatMap { TabStrokeDirection(rawValue: $0.lowercased()) }
        let brush = (b["brushStroke"] as? [String: Any])?["direction"] ?? b["brushStroke"]
        t.brush = (brush as? String).flatMap { TabStrokeDirection(rawValue: $0.lowercased()) }
            ?? (truthy(b["upStroke"]) ? .down : truthy(b["downStroke"]) ? .up : nil)
        if let tremolo = b["tremolo"] {
            if let figure = figureDenominator(tremolo), let speed = TabTremoloSpeed(rawValue: figure) {
                t.tremoloPicking = speed
            } else {
                out.missing.append(.unknownTremolo)
            }
        }
        out.techniques = t

        out.unknownKeys = b.keys.filter { !knownBeatKeys.contains($0) }.sorted().map { "beat.\($0)" }
            + n.keys.filter { !knownNoteKeys.contains($0) }.sorted().map { "note.\($0)" }
        if !out.unknownKeys.isEmpty { out.missing.append(.unknownKey) }
        return out
    }

    /// Denominador de una figura [1, n] de redonda (o `n` suelto): 32 = fusa. nil si no es de numerador 1.
    static func figureDenominator(_ v: Any?) -> Int? {
        if let d = v as? [Any], d.count == 2, int(d[0]) == 1 { return int(d[1]) }
        return int(v)
    }

    /// Nota de adorno de Songsterr (`graceNote` "beforeBeat" | "onBeat" en el beat) → `TabGrace`; con `bend`, de bend.
    static func grace(note n: [String: Any], beat b: [String: Any], fret: Int) -> TabGrace {
        let type: TabGrace.Kind = n["bend"] != nil ? .bendGrace
            : (b["graceNote"] as? String)?.lowercased() == "beforebeat" ? .beforeBeat : .onBeat
        return TabGrace(fret: fret, type: type, duration: figureDenominator(b["duration"]) ?? int(b["type"]),
                        slide: n["slide"] != nil, hammerPull: truthy(n["hp"]), dead: truthy(n["dead"]))
    }

    /// Activado: true, un número distinto de 0 o un texto no vacío (`accentuated` viene como 1).
    static func truthy(_ v: Any?) -> Bool {
        switch v {
        case let b as Bool: b
        case let n as Int: n != 0
        case let d as Double: d != 0
        case let s as String: !s.isEmpty
        default: false
        }
    }

    /// Un tramo de nota (la nota o una ligada) con su bend, en ticks desde el inicio de la nota.
    struct BendSegment {
        var offset: Int
        var length: Int
        var points: [TabBendPoint]?
    }

    /// Bend de una nota con sus ligadas: las curvas de cada tramo encadenadas sobre la duración total (0…60). Un tramo
    /// sin bend detrás de uno con bend lo mantiene (como una ligada en Guitar Pro); antes de ninguno, en 0.
    static func chainedBend(_ segments: [BendSegment], duration: Int) -> TabBend? {
        guard duration > 0, segments.contains(where: { $0.points != nil }) else { return nil }
        let scale = Double(TabBend.maxPosition) / Double(duration)
        func at(_ tick: Double) -> Int { min(TabBend.maxPosition, max(0, Int((tick * scale).rounded()))) }
        var points: [TabBendPoint] = []
        var held = 0
        for s in segments.sorted(by: { $0.offset < $1.offset }) {
            if let p = s.points {
                for q in p {
                    let tick = Double(s.offset) + Double(q.position) / Double(TabBend.maxPosition) * Double(s.length)
                    points.append(TabBendPoint(position: at(tick), value: q.value))
                }
                held = p.last?.value ?? held
            } else {
                points.append(TabBendPoint(position: at(Double(s.offset)), value: held))
                points.append(TabBendPoint(position: at(Double(s.offset + s.length)), value: held))
            }
        }
        if let first = points.first, first.position > 0 { points.insert(TabBendPoint(position: 0, value: first.value), at: 0) }
        if let last = points.last, last.position < TabBend.maxPosition {
            points.append(TabBendPoint(position: TabBend.maxPosition, value: last.value))
        }
        // Fuera repetidos y puntos en mitad de un tramo plano.
        var unique: [TabBendPoint] = []
        for p in points where unique.last != p { unique.append(p) }
        let tidy = unique.indices.filter { i in
            i == 0 || i == unique.count - 1
                || !(unique[i - 1].value == unique[i].value && unique[i + 1].value == unique[i].value)
        }.map { unique[$0] }
        return TabBend(points: tidy)
    }

    // MARK: - Recorrido

    private struct Converter {
        let kind: TabTrackKind
        let tuning: [Int]
        var bars: [SongsterrBar] = []
        var tempoChanges: [SongsterrTempoChange] = []
        var notes: [SongsterrNote] = []
        var hits: [SongsterrHit] = []
        var report = SongsterrImportReport()
        /// Última nota por (voz, cuerda) para las ligaduras; sigue entre compases.
        var lastOnString: [Int: Int] = [:]
        /// Tramos de bend de cada nota (paralelo a `notes`): la nota y sus ligadas.
        var bendSegments: [[BendSegment]] = []
        /// Batería: flam por (voz, pieza) esperando al golpe de su pieza.
        var pendingGrace: [Int: TabGrace] = [:]
        /// Guitarra y bajo: beats de adorno de cada voz, en orden, esperando al siguiente beat con notas; cada nota de
        /// adorno con su cuerda (índice de Songsterr, 0 = la más aguda).
        var pendingGraceBeats: [Int: [[(string: Int, grace: TabGrace)]]] = [:]

        mutating func missGrace() {
            report.ornaments[.graceNote, default: 0] += 1
            report.notesWithOrnaments += 1
        }

        init(kind: TabTrackKind, tuning: [Int]) {
            self.kind = kind
            self.tuning = tuning
        }

        mutating func run(measures: [[String: Any]], tempo points: [TempoPoint]) throws {
            var signatures: [(Int, Int)] = []
            var sig = (4, 4)
            for m in measures {
                if let s = m["signature"] as? [Any], s.count == 2, let n = int(s[0]), let d = int(s[1]), n > 0, d > 0,
                   (SongsterrTrack.ticksPerQuarter * 4) % d == 0 {
                    sig = (n, d)
                }
                signatures.append(sig)
            }
            let pointsByMeasure = Dictionary(grouping: points, by: \.measure)
            var tempo = defaultTempo
            var start = 0
            for (barIndex, mi) in try playOrder(measures).enumerated() {
                let m = measures[mi]
                var bar = SongsterrBar(sourceMeasure: mi, start: start, beatCount: signatures[mi].0,
                                       beatUnit: signatures[mi].1, tempo: tempo, marker: marker(m["marker"]))
                if barIndex == 0, let pickup = anacrusisBeats(m, bar: bar) { bar.beatCount = pickup }
                let barPoints = (pointsByMeasure[mi] ?? []).sorted { $0.position < $1.position }
                if barIndex == 0 && barPoints.first?.position ?? 1 > 0 {
                    tempoChanges.append(SongsterrTempoChange(bar: 0, position: 0, bpm: tempo))
                }
                for p in barPoints {
                    // Posición como fracción del compás = position / type, como el conversor de referencia
                    // (en los datos reales siempre es 0).
                    let fraction = p.position > 0 ? min(1, Double(p.position) / Double(max(1, p.type))) : 0
                    let position = Int((fraction * Double(bar.length)).rounded())
                    if position == 0 { bar.tempo = p.bpm }
                    if tempoChanges.last?.bpm != p.bpm {
                        tempoChanges.append(SongsterrTempoChange(bar: barIndex, position: position, bpm: p.bpm))
                    }
                    tempo = p.bpm
                }
                bars.append(bar)
                if !flag(m["rest"]) {
                    for (vi, voice) in (m["voices"] as? [[String: Any]] ?? []).enumerated() where !flag(voice["rest"]) {
                        try read(voice: voice, index: vi, bar: barIndex)
                    }
                }
                start += bar.length
            }
        }

        /// Compás incompleto al principio = anacrusa (decisión de Jorge, 17/11/2026): si la voz más larga del primer
        /// compás tocado dura menos que el compás y un número entero de pulsos, el compás tiene esos pulsos. nil si
        /// está completo, vacío o no cuadra en pulsos.
        func anacrusisBeats(_ m: [String: Any], bar: SongsterrBar) -> Int? {
            let voices = m["voices"] as? [[String: Any]] ?? []
            let content = voices.map { v in
                (v["beats"] as? [[String: Any]] ?? []).reduce(0) { sum, b in
                    b["graceNote"] != nil ? sum : sum + (beatTicks(b)?.ticks ?? 0)
                }
            }.max() ?? 0
            guard content > 0, content < bar.length, content % bar.beatLength == 0 else { return nil }
            return content / bar.beatLength
        }

        mutating func read(voice: [String: Any], index vi: Int, bar barIndex: Int) throws {
            let bar = bars[barIndex]
            var position = 0
            for beat in voice["beats"] as? [[String: Any]] ?? [] {
                let beatNotes = (beat["notes"] as? [[String: Any]] ?? []).filter { !flag($0["rest"]) && $0["fret"] != nil }
                if beat["graceNote"] != nil {
                    // Espera al siguiente beat con notas de la voz (puede ser del compás siguiente). En batería, al
                    // golpe de su misma pieza (flam).
                    var graceBeat: [(string: Int, grace: TabGrace)] = []
                    for n in beatNotes {
                        let slot = kind == .drums ? int(n["fret"]).flatMap(drumPiece).map(\.rawValue) : int(n["string"])
                        guard let slot, let fret = int(n["fret"]) else {
                            missGrace()
                            continue
                        }
                        if kind != .drums {
                            if !tuning.indices.contains(slot) || graceBeat.contains(where: { $0.string == slot }) {
                                missGrace()
                            } else {
                                graceBeat.append((slot, grace(note: n, beat: beat, fret: fret)))
                            }
                        } else if pendingGrace.updateValue(grace(note: n, beat: beat, fret: fret),
                                                           forKey: vi * 1000 + slot) != nil {
                            missGrace()
                        }
                    }
                    if !graceBeat.isEmpty { pendingGraceBeats[vi, default: []].append(graceBeat) }
                    continue
                }
                guard let (ticks, exact) = beatTicks(beat) else {
                    throw SongsterrFormatError(reason: "beat sin duración")
                }
                if !exact { report.inexactDurations += 1 }
                var mains: [Int] = []
                if !flag(beat["rest"]) {
                    for n in beatNotes {
                        if let i = add(note: n, beat: beat, voice: vi, bar: bar, barIndex: barIndex, position: position,
                                       ticks: ticks) {
                            mains.append(i)
                        }
                    }
                }
                attachGraces(voice: vi, to: mains)
                // Las de esta voz que no encontraron golpe de su pieza en este beat se pierden.
                for key in pendingGrace.keys where key / 1000 == vi {
                    pendingGrace[key] = nil
                    missGrace()
                }
                position += ticks
            }
        }

        /// Índice en `notes` de la nota nueva (nil si es golpe, ligada o se quita).
        mutating func add(note n: [String: Any], beat: [String: Any], voice vi: Int, bar: SongsterrBar, barIndex: Int,
                          position: Int, ticks: Int) -> Int? {
            guard let fret = int(n["fret"]) else { return nil }
            var read = techniques(note: n, beat: beat)
            let start = bar.start + position
            if kind == .drums {
                if flag(n["tie"]) { return nil }
                guard position < bar.length else { report.invalidNotes += 1; return nil }
                guard let piece = drumPiece(gm: fret) else { report.unknownDrumNotes += 1; return nil }
                if read.bend != nil || read.techniques.kinds.contains(where: { $0 != .ghost && $0 != .accent }) {
                    read.missing.append(.drumTechnique)
                }
                count(missing: read)
                hits.append(SongsterrHit(bar: barIndex, position: position, start: start, piece: piece,
                                         ghost: read.techniques.ghost,
                                         grace: pendingGrace.removeValue(forKey: vi * 1000 + piece.rawValue),
                                         accent: read.techniques.accent))
                return nil
            }
            count(missing: read)
            guard let s = int(n["string"]), tuning.indices.contains(s) else { report.invalidNotes += 1; return nil }
            let key = vi * 1000 + s
            if flag(n["tie"]), let prev = lastOnString[key] {
                notes[prev].duration = max(notes[prev].duration, start + ticks - notes[prev].start)
                notes[prev].techniques.absorbTied(read.techniques)
                bendSegments[prev].append(BendSegment(offset: start - notes[prev].start, length: ticks, points: read.bend))
                return nil
            }
            guard position < bar.length else { report.invalidNotes += 1; return nil }
            if !Tuning.fretRange.contains(fret) { report.fretsOutOfRange += 1 }
            notes.append(SongsterrNote(bar: barIndex, position: position, start: start, duration: ticks,
                                       string: s + 1, fret: fret, pitch: tuning[s] + fret, techniques: read.techniques))
            bendSegments.append([BendSegment(offset: 0, length: ticks, points: read.bend)])
            lastOnString[key] = notes.count - 1
            return notes.count - 1
        }

        /// Reparte los beats de adorno pendientes de la voz entre las notas nuevas del beat (`mains`, índices en
        /// `notes`): cada nota de adorno va en la de su cuerda o, si no la hay (rastrillo, adorno ante otra cuerda),
        /// en la de la cuerda más cercana (a igual distancia, la más aguda) con su cuerda en `TabGrace.string`.
        /// Sin notas nuevas (silencio o solo ligadas) se pierden.
        mutating func attachGraces(voice vi: Int, to mains: [Int]) {
            guard let graceBeats = pendingGraceBeats.removeValue(forKey: vi) else { return }
            guard !mains.isEmpty else {
                for gb in graceBeats { for _ in gb { missGrace() } }
                return
            }
            for (k, gb) in graceBeats.enumerated() {
                for (s, g) in gb {
                    let string = s + 1
                    let owner = mains.first { notes[$0].string == string } ?? mains.min {
                        (abs(notes[$0].string - string), notes[$0].string) < (abs(notes[$1].string - string), notes[$1].string)
                    }!
                    var placed = g
                    placed.step = graceBeats.count - k
                    if notes[owner].string != string { placed.string = string }
                    notes[owner].techniques.graces.append(placed)
                }
            }
        }

        /// Cuenta lo que no se pudo representar de una nota (o ligada, o golpe).
        mutating func count(missing read: ReadTechniques) {
            for o in read.missing { report.ornaments[o, default: 0] += 1 }
            if !read.missing.isEmpty { report.notesWithOrnaments += 1 }
            for k in read.unknownKeys { report.unknownKeys[k, default: 0] += 1 }
        }

        /// Bends encadenados con las ligadas y recuento de técnicas importadas.
        mutating func finish() {
            // Notas de adorno al final del tema.
            for _ in pendingGrace.values { missGrace() }
            for gb in pendingGraceBeats.values.joined() { for _ in gb { missGrace() } }
            pendingGrace = [:]
            pendingGraceBeats = [:]
            for i in notes.indices {
                notes[i].techniques.bend = chainedBend(bendSegments[i], duration: notes[i].duration)
                for k in notes[i].techniques.kinds { report.techniques[k, default: 0] += 1 }
            }
            for h in sortedHits() {
                if h.ghost { report.techniques[.ghost, default: 0] += 1 }
                if h.grace != nil { report.techniques[.grace, default: 0] += 1 }
                if h.accent != nil { report.techniques[.accent, default: 0] += 1 }
            }
        }

        func marker(_ v: Any?) -> String? {
            if let s = v as? String { return s }
            return (v as? [String: Any])?["text"] as? String
        }

        func sortedNotes() -> [SongsterrNote] {
            notes.sorted { ($0.start, $0.string) < ($1.start, $1.string) }
        }

        /// Uno por pieza y punto: fantasma solo si lo son todos los que caen ahí.
        func sortedHits() -> [SongsterrHit] {
            var out: [SongsterrHit] = []
            for h in hits.sorted(by: { ($0.start, $0.piece.rawValue) < ($1.start, $1.piece.rawValue) }) {
                if let last = out.last, last.start == h.start, last.piece == h.piece {
                    out[out.count - 1].ghost = last.ghost && h.ghost
                    out[out.count - 1].grace = last.grace ?? h.grace
                    out[out.count - 1].accent = TabAccent.stronger(last.accent, h.accent)
                } else {
                    out.append(h)
                }
            }
            return out
        }
    }
}

extension TabTechniques {
    /// Suma las técnicas de una ligada a su nota: las que siguen sonando (palm mute, let ring, vibrato, el ligado o
    /// el slide hacia la siguiente nota) pasan; las del ataque (ghost, muerta, acento, púa…) son las de la nota. El
    /// bend va aparte (`SongsterrTrackConverter.chainedBend`).
    mutating func absorbTied(_ tied: TabTechniques) {
        palmMute = palmMute || tied.palmMute
        letRing = letRing || tied.letRing
        if tied.vibrato == .wide || vibrato == nil { vibrato = tied.vibrato ?? vibrato }
        hammerPull = hammerPull || tied.hammerPull
        slideOut = tied.slideOut ?? slideOut
        harmonic = harmonic ?? tied.harmonic
        tremoloPicking = tremoloPicking ?? tied.tremoloPicking
    }
}
