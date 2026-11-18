import Foundation

/// Pistas de Songsterr alineadas → `TabScore` (mini-spec Fase 5b, «Alineación»): la rejilla son los pulsos del
/// `BeatGrid` más el ajuste fino, con los compases de Songsterr como primeros pulsos de compás, y el tempo escrito es el
/// de Songsterr (`writtenTempos`), no el de la regla de la Fase 5. Las notas conservan cuerda, traste y afinación de
/// Songsterr (sin Viterbi); cada una cae en su pulso con su fracción de negra, cuantizada a la subdivisión del pulso
/// como en la Fase 5. Duración: hasta el final de la nota o el siguiente ataque de la pista (al menos un punto).
enum SongsterrScorePlacement {
    static func trackID(_ index: Int) -> String { "songsterr-\(index)" }

    static func build(tracks: [SongsterrTrack], beats: [Double], placement: Placement, refBars: [SongsterrBar],
                      duration: Double) throws -> (TabScore, [SongsterrTrackPlacement]) {
        let fine = placement.fine
        let line = BeatLine(beats)
        // Primeros pulsos de compás: el inicio de cada compás de Songsterr que cae dentro de los pulsos detectados.
        var downbeats: [Double] = []
        var downbeatBars: [Int] = []
        var quarterCounts: [Int: Int] = [:]
        for (j, bar) in refBars.enumerated() {
            let q = SongsterrAligner.quarters(bar.start)
            quarterCounts[Int((Double(bar.length) / Double(SongsterrTrack.ticksPerQuarter)).rounded()), default: 0] += 1
            guard placement.keeps(q: q, bar: j) else { continue }
            let g = placement.gridBeat(q: q, bar: j)
            if g >= 0 && g <= Double(beats.count - 1) {
                downbeats.append(line.time(g) + fine)
                downbeatBars.append(j)
            }
            // Pulsos que la grabación tiene de más tras el compás: un compás aparte con ellos, como en la rejilla del
            // metrónomo (`SongsterrBeatGrid.build`), sin compás de Songsterr.
            guard j + 1 < refBars.count, placement.keeps(q: q, bar: j),
                  placement.keeps(q: SongsterrAligner.quarters(refBars[j + 1].start), bar: j + 1) else { continue }
            let gEnd = placement.gridBeat(q: SongsterrAligner.quarters(bar.start + bar.length), bar: j)
            let gNext = placement.gridBeat(q: SongsterrAligner.quarters(refBars[j + 1].start), bar: j + 1)
            if (gNext - gEnd).rounded() >= 1, gEnd >= 0, gEnd <= Double(beats.count - 1) {
                downbeats.append(line.time(gEnd) + fine)
                downbeatBars.append(-1)
            }
        }
        let perBar = quarterCounts.max { ($0.value, -$0.key) < ($1.value, -$1.key) }?.key
        var score = try TabScore(beatTimes: BeatTimes(beats: beats.map { $0 + fine }, downbeats: downbeats,
                                                      beatsPerBar: perBar.map { max(1, $0) }),
                                 duration: duration)
        score.bars = writtenTempos(score, downbeats: downbeats, downbeatBars: downbeatBars, refBars: refBars)
        let times = score.beats.map(\.time)
        let prepended = TabScore.nearestIndex(times, beats[0] + fine)

        /// Segundos de un pulso fraccionario del `BeatGrid` en la rejilla de `score`; nil fuera.
        func time(_ g: Double, allowEnd: Bool) -> Double? {
            let s = g + Double(prepended)
            guard s >= 0 else { return nil }
            let b = Int(s.rounded(.down))
            if b >= times.count { return allowEnd && s <= Double(times.count) + 1e-9 ? score.endTime : nil }
            return times[b] + (s - Double(b)) * (score.beatStart(b + 1) - times[b])
        }

        var out = score
        var reports: [SongsterrTrackPlacement] = []
        let names = SongsterrTrack.resolvedNames(tracks)
        for (i, t) in tracks.enumerated() {
            var report = SongsterrTrackPlacement(id: trackID(i))
            if t.kind == .drums {
                var onsets: [DrumOnset] = []
                for h in t.hits {
                    let q = SongsterrAligner.quarters(h.start)
                    guard placement.keeps(q: q, bar: h.bar) else { report.droppedInExtraBeats += 1; continue }
                    guard let at = time(placement.gridBeat(q: q, bar: h.bar), allowEnd: false) else {
                        report.droppedOutsideGrid += 1
                        continue
                    }
                    onsets.append(DrumOnset(time: at, piece: h.piece, ghost: h.ghost, grace: h.grace,
                                             accent: h.accent))
                }
                out.upsert(TabTrackBuilder.drumTrack(id: report.id, name: names[i], source: nil, onsets: onsets, in: score))
                reports.append(report)
                continue
            }

            struct Placed { var start: Double; var end: Double; var string: Int; var pitch: Int; var techniques: TabTechniques }
            var placed: [Placed] = []
            for n in t.notes {
                let q = SongsterrAligner.quarters(n.start)
                guard placement.keeps(q: q, bar: n.bar) else { report.droppedInExtraBeats += 1; continue }
                guard let on = time(placement.gridBeat(q: q, bar: n.bar), allowEnd: false) else {
                    report.droppedOutsideGrid += 1
                    continue
                }
                let qEnd = SongsterrAligner.quarters(n.start + n.duration)
                let off = time(placement.gridBeat(q: qEnd, bar: n.bar), allowEnd: true) ?? score.endTime
                // Voz: sin cuerdas (la altura MIDI es lo que cuenta), todas en la 1.
                placed.append(Placed(start: on, end: off, string: t.kind == .vocal ? 1 : n.string, pitch: n.pitch,
                                     techniques: n.techniques))
            }
            let subdivisions = score.chooseSubdivisions(onsets: placed.map(\.start))
            var byStart: [Int: [(string: Int, pitch: Int, end: Int, techniques: TabTechniques)]] = [:]
            for p in placed {
                let start = score.snapTick(p.start, subdivisions: subdivisions, allowEnd: false, times: times)
                let end = score.snapTick(p.end, subdivisions: subdivisions, allowEnd: true, times: times)
                // En una voz, «misma cuerda» es misma altura.
                if byStart[start]?.contains(where: { $0.string == p.string && (t.kind != .vocal || $0.pitch == p.pitch) }) == true {
                    report.mergedOnGrid += 1
                    continue
                }
                byStart[start, default: []].append((p.string, p.pitch, end, p.techniques))
            }
            let attacks = byStart.keys.sorted()
            var notes: [TabNote] = []
            for (k, start) in attacks.enumerated() {
                let next = k + 1 < attacks.count ? attacks[k + 1] : score.totalTicks
                let step = subdivisions[start / TabScore.ticksPerBeat].tickStep
                for e in byStart[start] ?? [] {
                    var end = min(e.end, next)
                    if end <= start { end = min(start + step, next) }
                    notes.append(TabNote(id: 0, pitch: e.pitch, string: e.string, start: GridPoint(absoluteTick: start),
                                         duration: end - start, amplitude: 1, techniques: e.techniques))
                }
            }
            // La batería nunca tiene afinación (ni «Personalizada»); solo cuerdas.
            // La voz tampoco: solo pentagrama.
            let hasStrings = t.kind == .guitar || t.kind == .bass
            let tuning: Tuning? = hasStrings ? (t.tuning ?? Tuning.custom(strings: t.tuningStrings)) : nil
            report.customTuning = hasStrings && t.tuning == nil
            var track = TabTrack(id: report.id, name: names[i], kind: t.kind, tuning: tuning, source: nil,
                                 subdivisions: subdivisions, notes: notes,
                                 program: t.kind == .vocal ? t.instrumentId : nil)
            track.sortContents()
            for j in track.notes.indices { track.notes[j].id = j + 1 }
            out.upsert(track)
            reports.append(report)
        }
        return (out, reports)
    }

    /// Un tramo con tempo escrito de Songsterr lo conserva si su cociente con el medido en el tramo (mediana del real
    /// de sus compases) cabe en ±15 %; si no, lleva el medido (decisión de Jorge, 17/11/2026: El roce escribe 130 BPM
    /// en los últimos compases y la batería sigue a ~172).
    static let writtenTempoTolerance = 0.15

    /// Tempo escrito de cada compás desde Songsterr (en vez de la regla del 2 % de la Fase 5): cada compás que empieza
    /// en un compás de Songsterr toma su tempo escrito (entero), agrupado en tramos consecutivos del mismo tempo y
    /// comprobado con `writtenTempoTolerance`. Los compases sin compás de Songsterr (pulsos que la grabación tiene de
    /// más, rejilla antes y después de la tablatura) siguen el tempo del anterior, o del primer tramo al principio.
    /// Pulsos por compás y tiempos no cambian: siguen al audio.
    /// - Parameter downbeatBars: compás de Songsterr de cada downbeat; −1 = compás de pulsos de más.
    static func writtenTempos(_ score: TabScore, downbeats: [Double], downbeatBars: [Int],
                              refBars: [SongsterrBar]) -> [TabBar] {
        var bars = score.bars
        guard !bars.isEmpty, !downbeats.isEmpty else { return bars }
        let times = score.beats.map(\.time)
        var sourceAtBeat: [Int: Int] = [:]
        for (t, j) in zip(downbeats, downbeatBars) where j >= 0 { sourceAtBeat[TabScore.nearestIndex(times, t)] = j }
        let source = bars.map { sourceAtBeat[$0.firstBeat] }
        let actual = bars.indices.map { i -> Double in
            let end = i + 1 < bars.count ? bars[i + 1].start : score.endTime
            return 60 * Double(bars[i].beatCount) / max(1e-6, end - bars[i].start)
        }
        // Tramos: compases con compás de Songsterr y el mismo tempo escrito, seguidos (los de sin compás no cortan).
        var tempo = [Double?](repeating: nil, count: bars.count)
        var i = 0
        while i < bars.count {
            guard let j = source[i] else { i += 1; continue }
            let written = refBars[j].tempo
            var members = [i]
            var k = i + 1
            while k < bars.count {
                if let jk = source[k] {
                    guard refBars[jk].tempo == written else { break }
                    members.append(k)
                }
                k += 1
            }
            let measured = TabScore.median(members.map { actual[$0] }[...])
            let fits = measured > 0 && abs(written / measured - 1) <= writtenTempoTolerance
            let value = TabScore.writtenTempo(fits ? written : measured)
            for m in members { tempo[m] = value }
            i = k
        }
        guard let first = tempo.compactMap({ $0 }).first else { return bars }
        var current = first
        for b in bars.indices {
            if let t = tempo[b] { current = t }
            bars[b].tempo = current
        }
        return bars
    }
}
