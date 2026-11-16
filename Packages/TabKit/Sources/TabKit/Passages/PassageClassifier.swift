/// Papel de una guitarra en un pasaje (mini-spec Fase 4, «Clasificación rítmica o solista»).
public enum GuitarRole: String, Codable, Sendable, CaseIterable {
    case rhythm
    case lead
    case silent
}

/// Pasaje de una guitarra: compases seguidos con el mismo papel, de borde de compás a borde de compás.
public struct GuitarPassage: Codable, Sendable, Equatable {
    public var start: Double
    public var end: Double
    public var role: GuitarRole
    /// 0…1: margen medio de la puntuación en sus compases (los compases absorbidos de otro papel cuentan 0).
    public var confidence: Double

    public init(start: Double, end: Double, role: GuitarRole, confidence: Double) {
        self.start = start
        self.end = end
        self.role = role
        self.confidence = confidence
    }
}

/// Rítmica, solista o sin guitarra a partir de las notas de Basic Pitch de una pista (mini-spec Fase 4,
/// «Clasificación rítmica o solista»; propuesta 2: ventana de 1 compás, pasajes de 2 como mínimo).
///
/// 1. Por compás: sin guitarra si apenas suena; si no, puntuación de rítmica (polifonía, acordes, registro) con
///    histéresis: solo se pasa de rítmica a melódico, o al revés, con un margen claro.
/// 2. Contexto de la pista: solista es solo un solo de verdad. Un tramo melódico es solo si dura varios compases y
///    la pista calla casi todo el tema, o entra tras un silencio largo, o la línea es muy clara; si no, es
///    acompañamiento (arpegios, arreglos, adornos) y cuenta como rítmica.
/// 3. Compases iguales seguidos forman pasajes de 2 compases como mínimo.
public enum PassageClassifier {
    // MARK: Constantes (calibradas con Platero y T1; mini-spec Fase 4)

    /// Propuesta 2 de la mini-spec Fase 4: pasajes de 2 compases como mínimo.
    static let minPassageBars = 2
    /// Un trozo antes del primer compás o tras el último más corto que esta fracción del compás mediano se suma
    /// a su vecino en lugar de ser un compás propio.
    static let partialBarFraction = 0.5
    /// Compás sin guitarra: suena (≥ 1 nota) menos de esta fracción del compás. Por encima de un roce suelto y de
    /// los restos de otra guitarra que deja la separación por panorama (en Platero C, mediana 0,19).
    static let silentActiveFraction = 0.25
    /// Polifonía media (sobre el tiempo que suena) que puntúa como acorde pleno; 1 nota puntúa 0.
    static let fullChordPolyphony = 2.5
    /// Registro (nota MIDI media ponderada por duración): por debajo de E3 puntúa rítmica plena, por encima de G4,
    /// solista plena (lineal entre ambas).
    static let rhythmRegisterMidi = 52.0
    static let leadRegisterMidi = 67.0
    /// Pesos de la puntuación de rítmica (suman 1): polifonía media, fracción de acorde (≥ 3 notas o power chord) y
    /// registro. La densidad se mide pero no puntúa: en Basic Pitch un rasgueo da tantas notas por segundo como
    /// una línea rápida.
    static let polyphonyWeight = 0.35
    static let chordFractionWeight = 0.45
    static let registerWeight = 0.20
    /// Puntuación de rítmica que separa acordes (por encima) de línea melódica (por debajo).
    static let rhythmDecision = 0.5
    /// Histéresis: para cambiar de acordes a línea, o al revés, la puntuación tiene que cruzar la frontera en más de
    /// este margen; dentro de la banda el compás sigue como el anterior.
    static let hysteresisMargin = 0.15
    /// Notas a la vez que cuentan como acorde pleno.
    static let chordNotes = 3
    /// Power chord: 2–3 notas cuyos intervalos con la más grave son quintas u octavas, con al menos una quinta
    /// (una octava sola es una línea doblada o un armónico de la nota, no un acorde).
    static let powerChordIntervals: Set<Int> = [7, 12, 19, 24]
    static let fifthIntervals: Set<Int> = [7, 19]

    /// Contexto de pista. Un solo dura al menos estos compases seguidos de línea melódica (una frase de 1–2
    /// compases entre acordes es un adorno).
    static let minSoloBars = 4
    /// Dentro de un solo se toleran huecos sin guitarra de hasta estos compases.
    static let soloGapBars = 1
    /// Pista que calla casi todo: suena en menos de esta fracción de los compases. Ahí una línea melódica larga es
    /// un solo.
    static let sparseTrackFraction = 0.5
    /// Entrada tras un silencio largo: al menos estos compases sin guitarra justo antes del tramo melódico.
    static let longSilenceBars = 4
    /// Confianza media de línea melódica (margen bajo `rhythmDecision`) que exige un solo en una pista que suena
    /// casi todo el tema («prueba muy fuerte»): una línea aguda de notas sueltas, no arpegios en el registro de
    /// los acordes.
    static let strongLeadConfidence = 0.7
    /// Ídem si el tramo entra tras un silencio largo.
    static let afterSilenceLeadConfidence = 0.4

    // MARK: API

    /// `downbeats`: tiempos de primer pulso de compás (Fase 2), en segundos. `duration`: duración de la pista.
    /// Los pasajes cubren [0, duration] sin huecos.
    public static func classify(notes: [NoteEvent], downbeats: [Double], duration: Double) -> [GuitarPassage] {
        let bars = bars(downbeats: downbeats, duration: duration)
        guard !bars.isEmpty else { return [] }
        let measures = bars.map { features(notes: notes, start: $0.start, end: $0.end) }
        return passages(bars: bars, verdicts: contextual(barVerdicts(measures)))
    }

    // MARK: Compases

    struct Bar: Equatable {
        var start: Double
        var end: Double
    }

    /// Compases entre pulsos fuertes; el trozo antes del primero y tras el último es un compás propio si dura al
    /// menos `partialBarFraction` del compás mediano y, si no, se suma a su vecino.
    static func bars(downbeats: [Double], duration: Double) -> [Bar] {
        guard duration > 0 else { return [] }
        let inner = downbeats.filter { $0 > 0 && $0 < duration }.sorted()
        var edges = [0.0] + inner + [duration]
        let lengths = zip(edges, edges.dropFirst()).map { $1 - $0 }
        if lengths.count > 2 {
            let full = lengths.dropFirst().dropLast().sorted()
            let median = full[full.count / 2]
            if lengths.last! < partialBarFraction * median { edges.remove(at: edges.count - 2) }
            if lengths.first! < partialBarFraction * median { edges.remove(at: 1) }
        }
        return zip(edges, edges.dropFirst()).map { Bar(start: $0, end: $1) }
    }

    // MARK: Medidas por compás

    struct BarFeatures: Equatable {
        /// Fracción del compás en que suena al menos una nota.
        var activeFraction: Double
        /// Polifonía media sobre el tiempo que suena.
        var meanPolyphony: Double
        /// Fracción del tiempo que suena con ≥ 3 notas a la vez.
        var threeOrMoreFraction: Double
        /// Fracción del tiempo que suena con un power chord.
        var powerChordFraction: Double
        /// Notas que empiezan en el compás, por segundo.
        var density: Double
        /// Nota MIDI media ponderada por duración (0 si no suena nada).
        var register: Double
        /// Amplitud de Basic Pitch media ponderada por duración (0 si no suena nada). Informativa.
        var amplitude: Double = 0
    }

    static func features(notes: [NoteEvent], start a: Double, end b: Double) -> BarFeatures {
        let length = b - a
        var events: [(t: Double, delta: Int, pitch: Int)] = []
        var onsets = 0
        var pitchTime = 0.0, noteTime = 0.0, ampTime = 0.0
        for n in notes where n.end > a && n.start < b && n.end > n.start {
            let s = max(n.start, a), e = min(n.end, b)
            events.append((s, 1, n.pitch))
            events.append((e, -1, n.pitch))
            if n.start >= a { onsets += 1 }
            pitchTime += Double(n.pitch) * (e - s)
            ampTime += Double(n.amplitude) * (e - s)
            noteTime += e - s
        }
        // Fin antes que inicio en el mismo instante: notas seguidas no se solapan.
        events.sort { ($0.t, $0.delta) < ($1.t, $1.delta) }
        var active: [Int: Int] = [:]
        var activeTime = 0.0, polyTime = 0.0, threeTime = 0.0, powerTime = 0.0
        for (i, ev) in events.enumerated() {
            if i > 0 {
                let dt = ev.t - events[i - 1].t
                let count = active.values.reduce(0, +)
                if dt > 0 && count > 0 {
                    activeTime += dt
                    polyTime += dt * Double(count)
                    if count >= chordNotes { threeTime += dt }
                    if isPowerChord(Array(active.keys)) { powerTime += dt }
                }
            }
            active[ev.pitch, default: 0] += ev.delta
            if active[ev.pitch] == 0 { active[ev.pitch] = nil }
        }
        guard activeTime > 0 else {
            return BarFeatures(activeFraction: 0, meanPolyphony: 0, threeOrMoreFraction: 0, powerChordFraction: 0,
                               density: Double(onsets) / length, register: 0)
        }
        return BarFeatures(activeFraction: activeTime / length,
                           meanPolyphony: polyTime / activeTime,
                           threeOrMoreFraction: threeTime / activeTime,
                           powerChordFraction: powerTime / activeTime,
                           density: Double(onsets) / length,
                           register: pitchTime / noteTime,
                           amplitude: ampTime / noteTime)
    }

    /// 2–3 notas distintas, intervalos con la grave en `powerChordIntervals` y al menos una quinta.
    static func isPowerChord(_ pitches: [Int]) -> Bool {
        guard (2...3).contains(pitches.count), let low = pitches.min() else { return false }
        let intervals = pitches.filter { $0 != low }.map { $0 - low }
        return intervals.allSatisfy(powerChordIntervals.contains) && intervals.contains(where: fifthIntervals.contains)
    }

    // MARK: Paso 1: decisión por compás

    struct Verdict: Equatable {
        var role: GuitarRole
        var confidence: Double
    }

    /// Puntuación de rítmica 0…1 (polifonía, acordes, registro).
    static func rhythmScore(_ f: BarFeatures) -> Double {
        let poly = clamp01((f.meanPolyphony - 1) / (fullChordPolyphony - 1))
        let chord = clamp01(max(f.threeOrMoreFraction, f.powerChordFraction))
        let register = clamp01((leadRegisterMidi - f.register) / (leadRegisterMidi - rhythmRegisterMidi))
        return polyphonyWeight * poly + chordFractionWeight * chord + registerWeight * register
    }

    /// Margen de la puntuación respecto a `rhythmDecision`, 0…1, hacia el papel dado.
    static func margin(_ r: Double, toward role: GuitarRole) -> Double {
        role == .rhythm ? clamp01((r - rhythmDecision) / (1 - rhythmDecision)) : clamp01((rhythmDecision - r) / rhythmDecision)
    }

    /// Sin guitarra si apenas suena; si no, acordes (`rhythm`) o línea melódica (`lead`, aún sin contexto) con
    /// histéresis respecto al último compás que sonó.
    static func barVerdicts(_ features: [BarFeatures]) -> [Verdict] {
        var last: GuitarRole?
        return features.map { f in
            if f.activeFraction < silentActiveFraction {
                return Verdict(role: .silent, confidence: 1 - f.activeFraction / silentActiveFraction)
            }
            let r = rhythmScore(f)
            let role: GuitarRole
            switch last {
            case .rhythm?: role = r < rhythmDecision - hysteresisMargin ? .lead : .rhythm
            case .lead?: role = r > rhythmDecision + hysteresisMargin ? .rhythm : .lead
            default: role = r >= rhythmDecision ? .rhythm : .lead
            }
            last = role
            return Verdict(role: role, confidence: margin(r, toward: role))
        }
    }

    // MARK: Paso 2: contexto de la pista

    /// Tramos melódicos (con huecos sin guitarra de hasta `soloGapBars`): solo si duran `minSoloBars` y la pista
    /// calla casi todo, o entran tras `longSilenceBars` sin guitarra con línea clara, o la línea es muy clara. Los
    /// demás son acompañamiento → rítmica, o, en una pista que calla casi todo, fragmentos sueltos → sin guitarra
    /// (confianza: 1 − la de línea). Los huecos de un solo pasan a solista.
    static func contextual(_ verdicts: [Verdict]) -> [Verdict] {
        var out = verdicts
        let sounding = Double(verdicts.filter { $0.role != .silent }.count) / Double(max(verdicts.count, 1))
        let sparse = sounding < sparseTrackFraction
        for run in melodicRuns(verdicts) {
            let leadBars = run.filter { verdicts[$0].role == .lead }
            let conf = leadBars.reduce(0.0) { $0 + verdicts[$1].confidence } / Double(max(leadBars.count, 1))
            var silenceBefore = 0
            var i = run.lowerBound - 1
            while i >= 0 && verdicts[i].role == .silent { silenceBefore += 1; i -= 1 }
            let afterSilence = silenceBefore >= longSilenceBars
            let solo = run.count >= minSoloBars
                && (sparse || conf >= strongLeadConfidence || (afterSilence && conf >= afterSilenceLeadConfidence))
            for b in run {
                if solo {
                    if verdicts[b].role == .silent { out[b] = Verdict(role: .lead, confidence: 0) }
                } else if verdicts[b].role == .lead {
                    // Pista que suena: adorno de acompañamiento. Pista que calla casi todo: fragmento suelto (restos de
                    // otra guitarra o ruido de la separación), sin guitarra.
                    out[b] = Verdict(role: sparse ? .silent : .rhythm, confidence: 1 - verdicts[b].confidence)
                }
            }
        }
        return out
    }

    /// Rangos de compases `lead` seguidos, unidos a través de huecos `silent` de hasta `soloGapBars`.
    static func melodicRuns(_ verdicts: [Verdict]) -> [Range<Int>] {
        var runs: [Range<Int>] = []
        var i = 0
        while i < verdicts.count {
            guard verdicts[i].role == .lead else { i += 1; continue }
            var end = i + 1
            while true {
                var j = end
                while j < verdicts.count && verdicts[j].role == .lead { j += 1 }
                end = j
                var gap = 0
                while j < verdicts.count && verdicts[j].role == .silent && gap < soloGapBars + 1 { j += 1; gap += 1 }
                if gap > 0 && gap <= soloGapBars && j < verdicts.count && verdicts[j].role == .lead { end = j } else { break }
            }
            runs.append(i..<end)
            i = end
        }
        return runs
    }

    // MARK: Paso 3: pasajes

    /// Compases iguales seguidos forman un pasaje. Mientras haya pasajes de menos de `minPassageBars` (y más de
    /// uno en total), el de menor confianza media se absorbe: si sus dos vecinos coinciden, se unen los tres; si no,
    /// pasa al vecino más largo (empate: el anterior).
    static func passages(bars: [Bar], verdicts: [Verdict]) -> [GuitarPassage] {
        precondition(bars.count == verdicts.count)
        var roles = verdicts.map(\.role)
        while true {
            let runs = runLengths(roles)
            guard runs.count > 1 else { break }
            let short = runs.indices.filter { runs[$0].count < minPassageBars }
            guard let pick = short.min(by: { meanConfidence(runs[$0], verdicts) < meanConfidence(runs[$1], verdicts) })
            else { break }
            let prev = pick > 0 ? runs[pick - 1] : nil
            let next = pick + 1 < runs.count ? runs[pick + 1] : nil
            let target: GuitarRole
            switch (prev, next) {
            case let (p?, n?): target = n.count > p.count ? n.role : p.role
            case let (p?, nil): target = p.role
            case let (nil, n?): target = n.role
            default: target = runs[pick].role
            }
            for i in runs[pick].range { roles[i] = target }
        }
        return runLengths(roles).map { run in
            let agree = run.range.reduce(0.0) { $0 + (verdicts[$1].role == run.role ? verdicts[$1].confidence : 0) }
            return GuitarPassage(start: bars[run.range.lowerBound].start, end: bars[run.range.upperBound - 1].end,
                                 role: run.role, confidence: agree / Double(run.count))
        }
    }

    struct Run {
        var role: GuitarRole
        var range: Range<Int>
        var count: Int { range.count }
    }

    static func runLengths(_ roles: [GuitarRole]) -> [Run] {
        guard !roles.isEmpty else { return [] }
        var out: [Run] = []
        var s = 0
        for i in 1...roles.count where i == roles.count || roles[i] != roles[s] {
            out.append(Run(role: roles[s], range: s..<i))
            s = i
        }
        return out
    }

    private static func meanConfidence(_ run: Run, _ verdicts: [Verdict]) -> Double {
        run.range.reduce(0.0) { $0 + verdicts[$1].confidence } / Double(run.count)
    }

    private static func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }
}
