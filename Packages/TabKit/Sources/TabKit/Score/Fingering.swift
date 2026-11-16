/// Cuerdas y trastes por Viterbi sobre la secuencia de acordes (mini-spec Fase 5, «Cuerdas y trastes»): cada nota
/// en una cuerda distinta, trastes 0–24, coste por apertura de la mano (más de 4 trastes muy penalizado), por salto
/// de posición entre acordes y una preferencia leve por trastes bajos y cuerdas al aire.
enum Fingering {
    /// Cualquier nota pisada cuesta esto más `fretCost` por traste: las cuerdas al aire salen algo más baratas.
    static let frettedCost = 0.1
    static let fretCost = 0.05
    /// Apertura (traste pisado más alto menos el más bajo) hasta `maxComfortSpan`.
    static let spanCost = 0.3
    /// «Más de 4 trastes muy penalizado».
    static let maxComfortSpan = 4
    static let wideSpanPenalty = 50.0
    static let wideSpanPerFret = 5.0
    /// Cuerda sin tocar entre la más grave y la más aguda del acorde (rasgueo con cuerda muerta en medio).
    /// Decisión de implementación: sin ella el power chord de Sol (3-5-5) sale como 3-x-0-0; con 2,0 aún salía así
    /// entre E5 y A5 por el coste de salto.
    static let skippedStringCost = 3.0
    /// Por traste de diferencia entre la posición media de dos acordes seguidos (los que solo tienen cuerdas al
    /// aire no tienen posición y no cuestan salto).
    static let positionJumpCost = 0.3
    /// Candidatos por acorde que entran en Viterbi (los de menor coste propio).
    static let candidatesPerChord = 48

    struct Input: Sendable {
        var pitch: Int
        var amplitude: Float
        /// Referencia del llamador (índice en su lista).
        var ref: Int
    }

    struct Placed: Sendable, Equatable {
        var ref: Int
        var pitch: Int
        var string: Int
    }

    struct Result: Sendable {
        /// Por acorde, las notas que quedan con su cuerda.
        var chords: [[Placed]]
        /// Notas subidas o bajadas de octava por salirse del registro de la afinación.
        var shiftedOctave: Int
        /// Notas quitadas: más notas que cuerdas, unísonos tras el cambio de octava o acordes sin digitación posible.
        var dropped: Int
    }

    struct Candidate {
        var strings: [Int]          // paralela a `notes`
        var cost: Double
        var position: Double?
    }

    static func assign(chords: [[Input]], tuning: Tuning) -> Result {
        var shifted = 0, dropped = 0
        var prepared: [[Input]] = []
        var candidates: [[Candidate]] = []

        for chord in chords {
            // Registro: octava arriba o abajo hasta caber.
            var notes: [Input] = []
            for var n in chord {
                if n.pitch < tuning.lowestPitch || n.pitch > tuning.highestPitch { shifted += 1 }
                while n.pitch < tuning.lowestPitch { n.pitch += 12 }
                while n.pitch > tuning.highestPitch { n.pitch -= 12 }
                if let j = notes.firstIndex(where: { $0.pitch == n.pitch }) {
                    dropped += 1
                    if n.amplitude > notes[j].amplitude { notes[j] = n }
                } else {
                    notes.append(n)
                }
            }
            // Más notas que cuerdas: fuera las de menos amplitud.
            notes.sort { ($0.amplitude, $0.pitch) > ($1.amplitude, $1.pitch) }
            while notes.count > tuning.strings.count { notes.removeLast(); dropped += 1 }
            var cands = enumerate(notes, tuning: tuning)
            while cands.isEmpty && !notes.isEmpty {
                notes.removeLast()
                dropped += 1
                cands = enumerate(notes, tuning: tuning)
            }
            prepared.append(notes)
            candidates.append(cands)
        }

        // Viterbi.
        var total: [[Double]] = []
        var back: [[Int]] = []
        for (i, cands) in candidates.enumerated() {
            guard i > 0, !total[i - 1].isEmpty else {   // primero, o tras un acorde vacío: sin transición
                total.append(cands.map(\.cost))
                back.append(Array(repeating: -1, count: cands.count))
                continue
            }
            let prev = candidates[i - 1]
            var row: [Double] = [], ptr: [Int] = []
            for c in cands {
                var best = Double.infinity, arg = 0
                for (j, p) in prev.enumerated() {
                    let v = total[i - 1][j] + transition(p, c)
                    if v < best { best = v; arg = j }
                }
                row.append(best + c.cost)
                ptr.append(arg)
            }
            total.append(row)
            back.append(ptr)
        }

        var choice = Array(repeating: -1, count: candidates.count)
        var i = candidates.count - 1
        var next = -1
        while i >= 0 {
            if candidates[i].isEmpty {
                next = -1
            } else if next >= 0 {
                choice[i] = next
            } else {
                choice[i] = total[i].indices.min { total[i][$0] < total[i][$1] } ?? 0
            }
            if choice[i] >= 0 { next = back[i][choice[i]] }
            i -= 1
        }

        let placed = prepared.enumerated().map { i, notes -> [Placed] in
            guard choice[i] >= 0 else { return [] }
            let strings = candidates[i][choice[i]].strings
            return zip(notes, strings).map { Placed(ref: $0.ref, pitch: $0.pitch, string: $1) }
        }
        return Result(chords: placed, shiftedOctave: shifted, dropped: dropped)
    }

    static func transition(_ a: Candidate, _ b: Candidate) -> Double {
        guard let pa = a.position, let pb = b.position else { return 0 }
        return positionJumpCost * abs(pa - pb)
    }

    /// Todas las asignaciones de cuerdas distintas con trastes 0–24, las `candidatesPerChord` más baratas.
    static func enumerate(_ notes: [Input], tuning: Tuning) -> [Candidate] {
        guard !notes.isEmpty else { return [] }
        let n = tuning.strings.count
        var out: [Candidate] = []
        var used = Array(repeating: false, count: n + 1)
        var current = Array(repeating: 0, count: notes.count)

        func go(_ k: Int) {
            if k == notes.count {
                out.append(score(current, notes: notes, tuning: tuning))
                return
            }
            for s in 1...n where !used[s] {
                let fret = notes[k].pitch - tuning.strings[s - 1]
                guard Tuning.fretRange.contains(fret) else { continue }
                used[s] = true
                current[k] = s
                go(k + 1)
                used[s] = false
            }
        }
        go(0)
        out.sort { $0.cost != $1.cost ? $0.cost < $1.cost : $0.strings.lexicographicallyPrecedes($1.strings) }
        return Array(out.prefix(candidatesPerChord))
    }

    static func score(_ strings: [Int], notes: [Input], tuning: Tuning) -> Candidate {
        var cost = 0.0
        var fretted: [Int] = []
        for (note, s) in zip(notes, strings) {
            let fret = note.pitch - tuning.strings[s - 1]
            if fret > 0 {
                cost += frettedCost + fretCost * Double(fret)
                fretted.append(fret)
            }
        }
        if let lo = fretted.min(), let hi = fretted.max() {
            let span = hi - lo
            cost += span <= maxComfortSpan
                ? spanCost * Double(span)
                : spanCost * Double(maxComfortSpan) + wideSpanPenalty + wideSpanPerFret * Double(span - maxComfortSpan)
        }
        if let lo = strings.min(), let hi = strings.max() {
            cost += skippedStringCost * Double(hi - lo + 1 - strings.count)
        }
        let position = fretted.isEmpty ? nil : Double(fretted.reduce(0, +)) / Double(fretted.count)
        return Candidate(strings: strings, cost: cost, position: position)
    }
}
