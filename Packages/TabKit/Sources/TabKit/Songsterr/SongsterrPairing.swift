import Foundation

/// Propuesta de pista de Songsterr para cada stem (mini-spec Fase 5b, decisión 3 y «Código», parte 3), como la
/// asignación de `Probes/P5b-guitarra/eval_reference.py` pero solo por croma:
///
/// - Guitarra y bajo: coseno medio entre el croma del stem (tramas de 2048 muestras) y el de las notas alineadas de
///   la pista, en las tramas con notas y audio.
/// - Izquierda y derecha: cada una su mejor pista; si salen la misma y hay más de una pista de guitarra, la pareja de
///   pistas distintas que más suma. El stem de guitarra completo solo es destino si no hay L ni R.
/// - Solista (decisión de Jorge, 17/11/2026): no lleva una pista entera sino las notas de cada sección de solo, y la
///   pista se elige en cada sección por separado (`soloPairs`) por la saliencia de sus notas en la altura exacta
///   dentro de ella (`soloSalience`), no por croma; puede repetir la de L o R (Songsterr suele llevar el solo dentro
///   de una de las guitarras).
/// - Batería: la pista de batería con más golpes que caen en un ataque del stem de batería.
/// - Las pistas que no quedan con ningún stem son extra.
enum SongsterrPairing {
    /// Tramas de CQT por trama de croma: 8 × 256 = 2048 muestras, el hop de `chroma_cqt` del prototipo.
    static let chromaPool = 8
    /// Menos tramas comparables que estas: sin medida (prototipo).
    static let minimumFrames = 10
    /// Menos notas de una pista dentro de una sección de solo que estas: sin medida (el mismo mínimo que las tramas
    /// de croma; elección de implementación, la mini-spec no lo fija).
    static let minimumSoloNotes = 10
    /// Un golpe de batería «cae en un ataque» si la envolvente del stem pasa de su media en ±50 ms (la tolerancia
    /// de ataque de las métricas de la Fase 5b).
    static let drumWindow = 0.050

    struct Result {
        var pairs: [SongsterrStemPair]
        var candidates: [SongsterrPairCandidate]
        var extras: [Int]
        var soloPairs: [SongsterrSoloPair] = []
    }

    static func propose(tracks: [SongsterrTrack], timed: [[TimedNote]], stems: StemAnalysis,
                        soloSpans: [ClosedRange<Double>]) -> Result {
        let has = { (r: SongsterrStemRole) in stems.audio[r] != nil }
        // El solista no se empareja con una pista entera: cada sección de solo por separado (`soloPairs`).
        var guitarTargets = [SongsterrStemRole.guitarLeft, .guitarRight].filter(has)
        if !has(.guitarLeft) && !has(.guitarRight) && stems.referenceRole(for: .guitar) != nil {
            guitarTargets.insert(.guitar, at: 0)
        }
        let guitars = tracks.indices.filter {
            tracks[$0].kind == .guitar && SongsterrAligner.estimates(tracks[$0]) && !timed[$0].isEmpty
        }
        let basses = tracks.indices.filter { tracks[$0].kind == .bass && !timed[$0].isEmpty }
        let drums = tracks.indices.filter { tracks[$0].kind == .drums && !timed[$0].isEmpty }

        var candidates: [SongsterrPairCandidate] = []
        var sim: [SongsterrStemRole: [Int: Double]] = [:]
        func measure(_ role: SongsterrStemRole, _ list: [Int], _ f: (Int) -> Double?) {
            for t in list {
                let s = f(t)
                candidates.append(SongsterrPairCandidate(role: role, track: t, similarity: s))
                if let s { sim[role, default: [:]][t] = s }
            }
        }
        var chromaCache: [SongsterrStemRole: (values: [Float], frames: Int)] = [:]
        func chroma(_ role: SongsterrStemRole) -> (values: [Float], frames: Int) {
            if let c = chromaCache[role] { return c }
            let c = stems.spectrum(role).chroma(pool: chromaPool)
            chromaCache[role] = c
            return c
        }
        for role in guitarTargets {
            measure(role, guitars) { chromaSimilarity(chroma(role), notes: timed[$0], spans: []) }
        }
        var soloPairs: [SongsterrSoloPair] = []
        if has(.guitarLead), !soloSpans.isEmpty {
            let map = stems.salience(.guitarLead)
            for span in soloSpans.sorted(by: { $0.lowerBound < $1.lowerBound }) {
                let sims = guitars.map { t in
                    SongsterrPairCandidate(role: .guitarLead, track: t,
                                           similarity: soloSalience(map, notes: timed[t], span: span))
                }
                soloPairs.append(soloPair(span: span, candidates: sims))
            }
        }
        if has(.bass) { measure(.bass, basses) { chromaSimilarity(chroma(.bass), notes: timed[$0], spans: []) } }
        if has(.drums) {
            let env = stems.envelope(.drums)
            measure(.drums, drums) { drumAgreement(env, hits: timed[$0]) }
        }

        func best(_ role: SongsterrStemRole, excluding: Set<Int> = []) -> Int? {
            (sim[role] ?? [:]).filter { !excluding.contains($0.key) }
                .max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key
        }
        var chosen: [SongsterrStemRole: Int] = [:]
        for role in guitarTargets + [.bass, .drums] { chosen[role] = best(role) }
        if let l = chosen[.guitarLeft], let r = chosen[.guitarRight], l == r,
           let sl = sim[.guitarLeft], let sr = sim[.guitarRight] {
            var bestPair: (Int, Int)?
            var bestSum = -Double.infinity
            for a in guitars { for b in guitars where a != b {
                guard let x = sl[a], let y = sr[b], x + y > bestSum else { continue }
                bestSum = x + y
                bestPair = (a, b)
            } }
            if let (a, b) = bestPair { chosen[.guitarLeft] = a; chosen[.guitarRight] = b }
        }

        var pairs: [SongsterrStemPair] = []
        for role in SongsterrStemRole.allCases {
            guard let t = chosen[role], let s = sim[role]?[t] else { continue }
            let others = (sim[role] ?? [:]).filter { $0.key != t }.map(\.value)
            pairs.append(SongsterrStemPair(role: role, track: t, confidence: s, margin: others.max().map { s - $0 }))
        }
        let used = Set(pairs.map(\.track))
        return Result(pairs: pairs, candidates: candidates, extras: tracks.indices.filter { !used.contains($0) },
                      soloPairs: soloPairs)
    }

    /// Pista de una sección de solo: la de más parecido (empate: la de menor índice); sin ninguna medida, ninguna.
    static func soloPair(span: ClosedRange<Double>, candidates: [SongsterrPairCandidate]) -> SongsterrSoloPair {
        let measured = candidates.compactMap { c in c.similarity.map { (track: c.track, sim: $0) } }
        guard let best = measured.max(by: { $0.sim < $1.sim || ($0.sim == $1.sim && $0.track > $1.track) }) else {
            return SongsterrSoloPair(span: span, track: nil, confidence: nil, margin: nil, candidates: candidates)
        }
        let others = measured.filter { $0.track != best.track }.map(\.sim)
        return SongsterrSoloPair(span: span, track: best.track, confidence: best.sim,
                                 margin: others.max().map { best.sim - $0 }, candidates: candidates)
    }

    /// Parecido de una pista con el stem solista dentro de una sección de solo: saliencia media de sus notas que
    /// empiezan en `span` (|CQT| normalizado por trama en la altura exacta de la nota, máximo de las
    /// `SongsterrAligner.salienceFrames` tramas desde el ataque; la medida del desfase). nil con menos de
    /// `minimumSoloNotes` notas en la sección.
    ///
    /// Altura exacta y no croma: en El roce (Solo 1, 158,3–183,5 s) la rítmica de Fito se cuela en el stem solista y
    /// sus acordes cubren más croma que el solo (Fito 0,393, Uoho 0,349), pero por trama la nota más fuerte es la del
    /// solo: Uoho 0,755 frente a Fito 0,036 (`SongsterrSoloPairRoceTests`).
    static func soloSalience(_ map: SalienceMap, notes all: [TimedNote], span: ClosedRange<Double>) -> Double? {
        let frames = SongsterrAligner.salienceFrames
        let notes = all.filter { $0.pitch >= 0 && span.lowerBound <= $0.onset && $0.onset < span.upperBound }
        guard notes.count >= minimumSoloNotes, map.frames >= frames else { return nil }
        let rate = SemitoneSpectrogram.sampleRate / Double(SemitoneSpectrogram.hop)
        var sum = 0.0
        map.values.withUnsafeBufferPointer { v in
            for n in notes {
                let bin = min(max(0, n.pitch - SemitoneSpectrogram.lowestMIDI), SemitoneSpectrogram.binCount - 1)
                let f = min(max(0, Int(n.onset * rate)), map.frames - frames)
                var m = v[bin * map.frames + f]
                for d in 1..<frames { m = max(m, v[bin * map.frames + f + d]) }
                sum += Double(m)
            }
        }
        return sum / Double(notes.count)
    }

    /// `chroma_corr` del prototipo: croma de las notas (una unidad por nota y trama sonando) frente al del stem, coseno
    /// por trama y media en las tramas con notas y audio (y dentro de `spans`, si hay).
    static func chromaSimilarity(_ chroma: (values: [Float], frames: Int), notes all: [TimedNote],
                                 spans: [ClosedRange<Double>]) -> Double? {
        let fps = SemitoneSpectrogram.sampleRate / Double(SemitoneSpectrogram.hop * chromaPool)
        let n = chroma.frames
        func inSpan(_ t: Double) -> Bool { spans.isEmpty || spans.contains { $0.lowerBound <= t && t < $0.upperBound } }
        let notes = all.filter { $0.pitch >= 0 && inSpan($0.onset) }
        var roll = [Float](repeating: 0, count: 12 * n)
        for note in notes {
            let a = max(0, Int(note.onset * fps)), b = max(Int(note.offset * fps), a + 1)
            guard a < n else { continue }
            let pc = note.pitch % 12
            for f in a..<min(b, n) { roll[pc * n + f] += 1 }
        }
        var total = 0.0, count = 0
        for f in 0..<n where inSpan(Double(f) / fps) {
            var dot: Float = 0, na: Float = 0, nb: Float = 0, rollSum: Float = 0, peak: Float = 0
            for c in 0..<12 {
                let x = chroma.values[c * n + f], y = roll[c * n + f]
                dot += x * y; na += x * x; nb += y * y; rollSum += y; peak = max(peak, x)
            }
            guard rollSum > 0, peak > 0 else { continue }
            total += Double(dot / ((na.squareRoot() + 1e-9) * (nb.squareRoot() + 1e-9)))
            count += 1
        }
        return count < minimumFrames ? nil : total / Double(count)
    }

    /// Fracción de golpes (distintos) con la envolvente del stem por encima de su media en ±`drumWindow`.
    static func drumAgreement(_ env: OnsetEnvelope, hits: [TimedNote]) -> Double? {
        var times: [Double] = []
        for h in hits.map(\.onset).sorted() where times.last.map({ h - $0 > 0.03 }) ?? true { times.append(h) }
        guard !times.isEmpty, !env.values.isEmpty else { return nil }
        let step = 1 / env.frameRate
        var hit = 0
        for t in times {
            var x = t - drumWindow
            var found = false
            while x <= t + drumWindow && !found {
                if env.value(at: x) > 1 { found = true }
                x += step
            }
            if found { hit += 1 }
        }
        return Double(hit) / Double(times.count)
    }
}
