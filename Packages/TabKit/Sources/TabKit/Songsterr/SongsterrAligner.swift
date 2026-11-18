import Foundation

/// Stems que entran en la alineación y en el emparejamiento; el valor es el id de canal de la app.
public enum SongsterrStemRole: String, Codable, Sendable, CaseIterable {
    case guitarLeft = "guitar_L"
    case guitarRight = "guitar_R"
    case guitarLead = "guitar_lead"
    /// Stem de guitarra completo (antes de separar por panorama): contra él se alinean las pistas de guitarra.
    case guitar
    case bass
    case drums
}

/// Un bloque de compases tocados con su desfase propio.
public struct SongsterrAlignedBlock: Sendable, Equatable {
    /// Primer compás tocado (índice en `SongsterrTrack.bars`).
    public var firstBar: Int
    public var barCount: Int
    /// Pulsos sobre el desfase global.
    public var shift: Int
}

/// Diferencia de estructura entre la tablatura y la grabación, en el compás donde cambia el desfase.
public struct SongsterrStructureWarning: Sendable, Equatable {
    /// Primer compás tocado con el desfase nuevo (índice en `SongsterrTrack.bars`).
    public var bar: Int
    /// El mismo compás en la pista de Songsterr (índice antes de desplegar repeticiones).
    public var sourceMeasure: Int
    /// Segundos de canción donde empieza `bar` en la grabación.
    public var time: Double
    /// Pulsos que la grabación tiene de más (> 0) o de menos (< 0) que la tablatura justo antes de `bar`.
    public var beats: Int
    /// Si `beats` es un número entero de compases de `bar`: compases (repeticiones) de más o de menos, con signo.
    public var wholeBars: Int?
}

/// Propuesta de pista de Songsterr para un stem.
public struct SongsterrStemPair: Sendable, Equatable {
    public var role: SongsterrStemRole
    /// Índice en las pistas de entrada.
    public var track: Int
    /// Parecido con el audio, 0…1: coseno medio de croma (guitarra y bajo) o fracción de golpes con ataque en el
    /// stem (batería).
    public var confidence: Double
    /// `confidence` menos la mejor de las otras pistas candidatas para el mismo stem; nil si no había otra. Negativa
    /// cuando otra pista se parece más pero se queda en el otro lado (L y R no comparten pista).
    public var margin: Double?
}

/// Parecido de una pista con un stem candidato (para la lista editable).
public struct SongsterrPairCandidate: Sendable, Equatable {
    public var role: SongsterrStemRole
    public var track: Int
    /// nil si no hay bastante solape para medirlo (menos de 10 tramas con notas y audio).
    public var similarity: Double?
}

/// Pista de Songsterr propuesta para una sección de solo del stem solista (decisión de Jorge, 17/11/2026).
public struct SongsterrSoloPair: Sendable, Equatable {
    /// Segundos de canción de la sección (los `soloSpans` del proyecto).
    public var span: ClosedRange<Double>
    /// nil si ninguna pista de guitarra tiene medida en la sección.
    public var track: Int?
    /// Saliencia media (0…1) de las notas de la pista que empiezan en la sección, en la altura exacta, sobre el stem
    /// solista (`SongsterrPairing.soloSalience`).
    public var confidence: Double?
    /// `confidence` menos la mejor de las otras pistas; nil si no había otra medida.
    public var margin: Double?
    /// Todas las pistas de guitarra con su parecido en la sección (rol `.guitarLead`).
    public var candidates: [SongsterrPairCandidate]
}

/// Lo que pasó con las notas de una pista al llevarlas a la rejilla.
public struct SongsterrTrackPlacement: Sendable, Equatable {
    /// Id de la pista en `SongsterrAlignment.score` («songsterr-<índice>»).
    public var id: String
    /// Notas o golpes fuera de la rejilla del tema (antes del principio o pasado el final del audio).
    public var droppedOutsideGrid = 0
    /// Notas o golpes en pulsos que sobran en la tablatura (la grabación tiene menos): se quitan.
    public var droppedInExtraBeats = 0
    /// Notas que caen en el mismo punto y cuerda que otra al cuantizar (fusas, adornos): se quitan.
    public var mergedOnGrid = 0
    /// La afinación de Songsterr no es ningún preset: la pista queda con `TuningPreset.custom` y las alturas
    /// exactas de las cuerdas (mini-spec Fase 5b, decisión 7).
    public var customTuning = false
}

public enum SongsterrAlignmentError: Error, Equatable, Sendable {
    /// Ninguna pista de guitarra o bajo tiene stem con el que medirse.
    case nothingToAlign
}

/// Resultado de alinear las pistas de Songsterr con el audio.
public struct SongsterrAlignment: Sendable {
    /// Pulso del `BeatGrid` donde cae la negra 0 de la tablatura.
    public var offsetBeats: Int
    /// Ajuste fino en segundos (se suma a los tiempos de los pulsos).
    public var fineOffset: Double
    /// Desfase por bloques de `SongsterrAligner.blockBars` compases tocados (todos, se usen o no).
    public var blocks: [SongsterrAlignedBlock]
    /// Los bloques mejoran la saliencia media más de `SongsterrAligner.minimumBlockGain` sobre el desfase global.
    public var usesBlocks: Bool
    /// Saliencia media de las notas con el desfase global y con el de cada bloque.
    public var globalSalience: Double
    public var blockSalience: Double
    /// Vacío si no se usan los bloques.
    public var structureWarnings: [SongsterrStructureWarning]
    /// Rejilla del tema (pulsos del `BeatGrid` + ajuste fino, compases de Songsterr) con una pista por pista de entrada.
    public var score: TabScore
    /// Una por pista de entrada, en el mismo orden.
    public var placements: [SongsterrTrackPlacement]
    public var pairs: [SongsterrStemPair]
    public var candidates: [SongsterrPairCandidate]
    /// Pistas sin stem: entran en la tablatura como extra (mini-spec Fase 5b, decisión 5).
    public var extraTracks: [Int]

    /// Tiempos alineados (sin cuantizar) de cada pista, para la comprobación con el prototipo.
    var timedNotes: [[TimedNote]]
    /// Una por sección de solo, en orden de tiempo; vacío sin stem solista o sin secciones de solo. El solista no
    /// tiene entrada en `pairs`.
    public var soloPairs: [SongsterrSoloPair] = []
}

/// Nota con tiempo real del tema.
struct TimedNote: Equatable {
    var onset: Double
    var offset: Double
    /// −1 en batería.
    var pitch: Int
}

/// Alineación de pistas de Songsterr con el audio (mini-spec Fase 5b, «Alineación»; port de
/// `Probes/P5b-guitarra/eval_reference.py`). Las negras de la tablatura caen una a una en los pulsos del
/// `BeatGrid`:
///
/// 1. Desfase global entero en pulsos que maximiza la saliencia: valor del |CQT| normalizado por trama en la altura
///    exacta de cada nota, máximo de las 4 tramas desde su ataque, medio de todas las notas (guitarras contra el stem
///    de guitarra, bajo contra el de bajo).
/// 2. Ajuste fino en ms: el que deja los ataques de la tablatura sobre los picos de la envolvente de ataques del stem.
/// 3. Desfase por bloques de 4 compases tocados con Viterbi (la misma saliencia; cada cambio cuesta
///    `blockChangePenalty` más `blockChangePenaltyPerBeat` por pulso de salto), que se usa si mejora la saliencia
///    global; sus cambios son los avisos de estructura.
///
/// Sin DTW de croma ni alineación por ataques para el desfase: con rasgueo periódico confunden desfases de 2 negras.
///
/// Solo estiman las pistas de guitarra (programa GM 24–31 o sin programa) y bajo; voz, teclados y batería reciben el
/// mismo desfase y los mismos bloques. Límite: cada bloque se mueve como mucho ±12 pulsos sobre el global, así que una
/// repetición de más o de menos de más de 3 compases de 4/4 no se detecta (se ampliará si un tema lo pide).
public enum SongsterrAligner {
    /// Desfases globales probados, en pulsos (prototipo: `range(-48, 49)`), ampliados por `globalShifts(tabQuarters:beats:)`.
    static let globalShifts = -48...48

    /// Desfases globales para una tablatura de `tabQuarters` negras tocadas sobre `beats` pulsos: los del prototipo más
    /// la diferencia de duración hacia el lado que la explica. Una tablatura más larga que la grabación tiene compases
    /// que esta no (desfase negativo: Benito Kamelas, Songsterr 6187196 y 3490233, escribe 14 compases más de riff de
    /// intro, −56 pulsos, y con ±48 se quedaba en +8 con avisos de ±12 y 993 notas fuera); una más corta, al revés.
    static func globalShifts(tabQuarters: Double, beats: Int) -> ClosedRange<Int> {
        let extra = Int((tabQuarters - Double(beats)).rounded())
        return (globalShifts.lowerBound - max(0, extra))...(globalShifts.upperBound + max(0, -extra))
    }
    /// Ajuste fino: de −80 a +80 ms cada 5 ms (prototipo).
    static let fineShifts: [Double] = (0...32).map { -0.080 + 0.005 * Double($0) }
    /// Compases tocados por bloque (mini-spec Fase 5b, «Alineación»).
    public static let blockBars = 4
    /// Desfases por bloque sobre el global, en pulsos (prototipo: `range(-12, 13)`).
    static let blockShifts = -12...12
    /// Coste de cambiar de desfase entre bloques, en unidades de saliencia media (prototipo).
    static let blockChangePenalty = 0.02
    /// … más esto por cada pulso de salto. Con riffs que se repiten cada 2 compases (Tornado Of Souls a 200 BPM) la
    /// saliencia de un bloque desplazado 8 pulsos queda a 0,01–0,05 de la buena y el camino saltaba ±8 y volvía
    /// (−3 → +6 → −10 → −3): un salto de 8 cuesta ahora 0,06 y uno de 1 (pulso perdido de la rejilla) 0,025.
    static let blockChangePenaltyPerBeat = 0.005
    /// Un bloque necesita al menos estas notas de una pista para puntuar con ella (prototipo).
    static let minimumNotesPerBlock = 3
    /// Los bloques se usan si suben la saliencia media más que esto (prototipo).
    public static let minimumBlockGain = 0.01
    /// Tramas de CQT desde el ataque en las que se busca el máximo (prototipo).
    static let salienceFrames = 4

    /// Carga los stems (cualquier formato que lea AVFoundation) y alinea. CPU: llamar fuera del hilo principal.
    ///
    /// - Parameters:
    ///   - tracks: pistas convertidas de una misma revisión de Songsterr (mismos compases).
    ///   - beats: del `BeatGrid` del tema.
    ///   - stems: hacen falta `.guitar` (o alguno de los de guitarra) para las guitarras y `.bass` para el bajo;
    ///     L, R, solista y batería solo para el emparejamiento.
    ///   - soloSpans: tramos de solo del proyecto; el solista se compara solo dentro de ellos.
    public static func align(tracks: [SongsterrTrack], beats: BeatTimes, stems: [SongsterrStemRole: URL],
                             soloSpans: [ClosedRange<Double>] = []) throws -> SongsterrAlignment {
        var audio: [SongsterrStemRole: [Float]] = [:]
        for (role, url) in stems { audio[role] = try MonoAudio.load(url, sampleRate: SemitoneSpectrogram.sampleRate) }
        return try align(tracks: tracks, beats: beats, audio: audio, soloSpans: soloSpans)
    }

    /// - Parameters:
    ///   - audio: mono a `SemitoneSpectrogram.sampleRate`.
    ///   - perBeatPenalty: `blockChangePenaltyPerBeat` (otro valor solo para bisecar en las puertas).
    static func align(tracks: [SongsterrTrack], beats beatTimes: BeatTimes, audio: [SongsterrStemRole: [Float]],
                      soloSpans: [ClosedRange<Double>],
                      perBeatPenalty: Double = blockChangePenaltyPerBeat) throws -> SongsterrAlignment {
        var beats: [Double] = []
        for t in beatTimes.beats.sorted() where beats.last.map({ t - $0 > 1e-6 }) ?? true { beats.append(t) }
        guard beats.count >= 2 else { throw TabScoreError.notEnoughBeats }
        let line = BeatLine(beats)
        let stems = StemAnalysis(audio: audio)
        let duration = Double(audio.values.map(\.count).max() ?? 0) / SemitoneSpectrogram.sampleRate

        // Pistas de guitarra y bajo con su stem de referencia.
        var measured: [MeasuredTrack] = []
        for (i, t) in tracks.enumerated() where estimates(t) {
            guard let role = stems.referenceRole(for: t.kind) else { continue }
            measured.append(MeasuredTrack(index: i, role: role, notes: t.notes.map(AlignNote.init)))
        }
        guard !measured.isEmpty else { throw SongsterrAlignmentError.nothingToAlign }
        let maps = Dictionary(uniqueKeysWithValues: Set(measured.map(\.role)).map { ($0, stems.salience($0)) })

        // 1. Desfase global (sin ajuste fino, como el prototipo).
        func meanSalience(shift: Double, fine: Double) -> Double {
            measured.map { m in salience(m.notes[...], shift: shift, fine: fine, map: maps[m.role]!, line: line) }
                .reduce(0, +) / Double(measured.count)
        }
        let tabQuarters = tracks[measured[0].index].bars.map { Double($0.length) }.reduce(0, +)
            / Double(SongsterrTrack.ticksPerQuarter)
        var offset = 0, best = -Double.infinity
        for o in globalShifts(tabQuarters: tabQuarters, beats: beats.count) {
            let s = meanSalience(shift: Double(o), fine: 0)
            if s >= best { best = s; offset = o }  // empate: el mayor, como `sorted(reverse=True)`
        }

        // 2. Ajuste fino por la envolvente de ataques.
        let envelopes = Dictionary(uniqueKeysWithValues: Set(measured.map(\.role)).map { ($0, stems.envelope($0)) })
        let onsetQs = measured.map { m in uniqueStarts(tracks[m.index].notes) }
        var fine = 0.0, bestFine = -Double.infinity
        for f in fineShifts {
            var total = 0.0
            for (k, m) in measured.enumerated() {
                let env = envelopes[m.role]!
                let qs = onsetQs[k]
                var sum = 0.0
                for q in qs { sum += Double(env.value(at: line.time(q + Double(offset)) + f - OnsetEnvelope.peakAdvance)) }
                total += qs.isEmpty ? 0 : sum / Double(qs.count)
            }
            if total >= bestFine { bestFine = total; fine = f }
        }

        // 3. Bloques de compases tocados.
        let barCount = (measured.flatMap { $0.notes.map(\.bar) }.max() ?? 0) + 1
        let blockCount = (barCount + blockBars - 1) / blockBars
        let shifts = Array(blockShifts)
        var score = [[Double]](repeating: [Double](repeating: 0, count: shifts.count), count: blockCount)
        for m in measured {
            let byBlock = Dictionary(grouping: m.notes, by: { $0.bar / blockBars })
            for (b, sel) in byBlock where sel.count >= minimumNotesPerBlock {
                for (si, s) in shifts.enumerated() {
                    score[b][si] += salience(sel[...], shift: Double(offset + s), fine: fine, map: maps[m.role]!,
                                             line: line) / Double(measured.count)
                }
            }
        }
        var path = viterbi(score, penalty: blockChangePenalty, perStep: perBeatPenalty).map { shifts[$0] }
        func blockShift(ofBar bar: Int) -> Int { path.isEmpty ? 0 : path[min(max(0, bar / blockBars), path.count - 1)] }

        let globalSal = meanSalience(shift: Double(offset), fine: fine)
        let blockSal = measured.map { m in
            m.notes.map { n in
                salience([n][...], shift: Double(offset + blockShift(ofBar: n.bar)), fine: fine, map: maps[m.role]!,
                         line: line)
            }.reduce(0, +) / Double(m.notes.count)
        }.reduce(0, +) / Double(measured.count)
        let usesBlocks = blockSal > globalSal + minimumBlockGain

        // Compases de referencia: los de la primera pista medida (todas las de una revisión los comparten).
        let refBars = tracks[measured[0].index].bars
        let barStartQ = refBars.map { Double($0.start) / Double(SongsterrTrack.ticksPerQuarter) }
        // Primeros bloques sin contexto (compás de cuenta o anacrusa escritos como compás entero): la misma regla que la
        // rejilla del metrónomo (`SongsterrBeatGrid.leadingShifts`), para que tablatura y metrónomo empiecen igual.
        if usesBlocks {
            path = SongsterrBeatGrid.leadingShifts(path, offset: offset, barStartQ: barStartQ, model: beats,
                                                   downbeats: beatTimes.downbeats)
        }
        let blocks = path.enumerated().map { b, s in
            SongsterrAlignedBlock(firstBar: b * blockBars, barCount: min(blockBars, barCount - b * blockBars), shift: s)
        }
        let placement = Placement(offset: offset, fine: fine, shifts: usesBlocks ? path : [], barStartQ: barStartQ)

        var warnings: [SongsterrStructureWarning] = []
        if usesBlocks {
            for b in 1..<max(1, path.count) where path[b] != path[b - 1] {
                let bar = b * blockBars
                guard bar < refBars.count else { continue }
                let delta = path[b] - path[b - 1]
                let quarters = Double(refBars[bar].length) / Double(SongsterrTrack.ticksPerQuarter)
                let bars = Double(delta) / quarters
                warnings.append(SongsterrStructureWarning(
                    bar: bar, sourceMeasure: refBars[bar].sourceMeasure,
                    time: line.time(barStartQ[bar] + Double(offset + path[b])) + fine, beats: delta,
                    wholeBars: bars == bars.rounded() ? Int(bars) : nil))
            }
        }

        // Tiempos reales (los del prototipo) de todas las pistas.
        var timed: [[TimedNote]] = []
        for t in tracks {
            var out: [TimedNote] = []
            if t.kind == .drums {
                for h in t.hits where placement.keeps(q: quarters(h.start), bar: h.bar) {
                    let on = line.time(placement.gridBeat(q: quarters(h.start), bar: h.bar)) + fine
                    out.append(TimedNote(onset: on, offset: on, pitch: -1))
                }
            } else {
                for n in t.notes where placement.keeps(q: quarters(n.start), bar: n.bar) {
                    let on = line.time(placement.gridBeat(q: quarters(n.start), bar: n.bar)) + fine
                    let off = line.time(placement.gridBeat(q: quarters(n.start + n.duration), bar: n.bar)) + fine
                    out.append(TimedNote(onset: on, offset: max(off, on + 0.02), pitch: n.pitch))
                }
            }
            timed.append(out)
        }

        let pairing = SongsterrPairing.propose(tracks: tracks, timed: timed, stems: stems, soloSpans: soloSpans)
        let (tabScore, placements) = try SongsterrScorePlacement.build(
            tracks: tracks, beats: beats, placement: placement, refBars: refBars, duration: duration)

        return SongsterrAlignment(offsetBeats: offset, fineOffset: fine, blocks: blocks, usesBlocks: usesBlocks,
                                  globalSalience: globalSal, blockSalience: blockSal, structureWarnings: warnings,
                                  score: tabScore, placements: placements, pairs: pairing.pairs,
                                  candidates: pairing.candidates, extraTracks: pairing.extras, timedNotes: timed,
                                  soloPairs: pairing.soloPairs)
    }

    /// Programas GM de guitarra (Acoustic Nylon … Guitar Harmonics).
    static let guitarPrograms = 24...31

    /// La pista entra en la estimación (desfase, fino y bloques) y en el emparejamiento: guitarra (programa GM de
    /// guitarra o sin programa) o bajo, con notas. Voz, teclados y batería no estiman: heredan la alineación y la
    /// batería va con su stem; lo demás sale como pista extra (decisión del coordinador, 16/11/2026).
    static func estimates(_ t: SongsterrTrack) -> Bool {
        guard !t.notes.isEmpty else { return false }
        switch t.kind {
        case .bass: return true
        case .guitar: return t.instrumentId.map { guitarPrograms.contains($0) } ?? true
        case .drums, .vocal: return false
        }
    }

    static func quarters(_ ticks: Int) -> Double { Double(ticks) / Double(SongsterrTrack.ticksPerQuarter) }

    /// Inicios distintos de una pista, en negras.
    static func uniqueStarts(_ notes: [SongsterrNote]) -> [Double] {
        var out: [Double] = []
        var last = Int.min
        for n in notes where n.start != last {
            out.append(quarters(n.start))
            last = n.start
        }
        return out
    }

    /// Saliencia media de las notas con `shift` negras de desfase y `fine` segundos (`salience` del prototipo).
    static func salience(_ notes: ArraySlice<AlignNote>, shift: Double, fine: Double, map: SalienceMap,
                         line: BeatLine) -> Double {
        guard !notes.isEmpty, map.frames >= salienceFrames else { return 0 }
        let rate = SemitoneSpectrogram.sampleRate / Double(SemitoneSpectrogram.hop)
        let lastFrame = map.frames - salienceFrames
        var sum = 0.0
        map.values.withUnsafeBufferPointer { v in
            for n in notes {
                let t = line.time(n.q + shift) + fine
                let x = t * rate
                let f = min(max(0, x.isFinite ? Int(max(-1e9, min(1e9, x))) : 0), lastFrame)
                let base = n.bin * map.frames + f
                var m = v[base]
                for d in 1..<salienceFrames { m = max(m, v[base + d]) }
                sum += Double(m)
            }
        }
        return sum / Double(notes.count)
    }

    /// Camino de máxima puntuación por bloques; cambiar de estado cuesta `penalty` más `perStep` por cada índice de
    /// distancia entre estados. Empates: el primer índice, como `argmax` de NumPy en el prototipo.
    static func viterbi(_ score: [[Double]], penalty: Double, perStep: Double = 0) -> [Int] {
        guard let first = score.first else { return [] }
        let n = first.count
        var acc = first
        var back = [[Int]](repeating: [Int](repeating: 0, count: n), count: score.count)
        for b in 1..<score.count {
            var next = [Double](repeating: 0, count: n)
            for i in 0..<n {
                var bestJ = 0, bestV = -Double.infinity
                for j in 0..<n {
                    let v = acc[j] - (i == j ? 0 : penalty + perStep * Double(abs(i - j)))
                    if v > bestV { bestV = v; bestJ = j }
                }
                back[b][i] = bestJ
                next[i] = score[b][i] + bestV
            }
            acc = next
        }
        var state = acc.indices.max { acc[$0] < acc[$1] || (acc[$0] == acc[$1] && $0 > $1) }!
        var path = [state]
        for b in stride(from: score.count - 1, to: 0, by: -1) {
            state = back[b][state]
            path.append(state)
        }
        return path.reversed()
    }
}

/// Nota reducida a lo que mide la saliencia.
struct AlignNote {
    /// Inicio en negras desde el principio del tema.
    var q: Double
    /// Bin del CQT (MIDI − 28, saturado a 0…83).
    var bin: Int
    /// Compás tocado.
    var bar: Int

    init(_ n: SongsterrNote) {
        q = SongsterrAligner.quarters(n.start)
        bin = min(max(0, n.pitch - SemitoneSpectrogram.lowestMIDI), SemitoneSpectrogram.binCount - 1)
        bar = n.bar
    }
}

struct MeasuredTrack {
    var index: Int
    var role: SongsterrStemRole
    var notes: [AlignNote]
}

struct SalienceMap {
    var values: [Float]
    var frames: Int
}

/// Negra de la tablatura → pulso del `BeatGrid` (fraccionario) con el desfase global y el de su bloque, y qué
/// notas caen en pulsos que sobran.
struct Placement {
    var offset: Int
    var fine: Double
    /// Desfase por bloque; vacío = solo el global.
    var shifts: [Int]
    var barStartQ: [Double]
    /// Por bloque: primer pulso (del `BeatGrid`) que ya ocupa un bloque posterior. Lo que caiga desde ahí sobra en
    /// la tablatura (la grabación tiene menos pulsos).
    var limits: [Double]

    init(offset: Int, fine: Double, shifts: [Int], barStartQ: [Double]) {
        self.offset = offset
        self.fine = fine
        self.shifts = shifts
        self.barStartQ = barStartQ
        var limits = [Double](repeating: .infinity, count: shifts.count)
        var running = Double.infinity
        for b in stride(from: shifts.count - 1, through: 0, by: -1) {
            limits[b] = running
            let bar = b * SongsterrAligner.blockBars
            if bar < barStartQ.count { running = min(running, barStartQ[bar] + Double(offset + shifts[b])) }
        }
        self.limits = limits
    }

    func block(ofBar bar: Int) -> Int? {
        shifts.isEmpty ? nil : min(max(0, bar / SongsterrAligner.blockBars), shifts.count - 1)
    }

    func gridBeat(q: Double, bar: Int) -> Double {
        q + Double(offset + (block(ofBar: bar).map { shifts[$0] } ?? 0))
    }

    func keeps(q: Double, bar: Int) -> Bool {
        guard let b = block(ofBar: bar) else { return true }
        return gridBeat(q: q, bar: bar) < limits[b] - 1e-9
    }
}

/// Pulsos del `BeatGrid` como función continua de la negra (`Grid.time` del prototipo): interpolación lineal
/// dentro de la rejilla y, fuera, el periodo mediano de los 16 primeros o últimos pulsos.
struct BeatLine {
    let beats: [Double]
    let stepStart: Double
    let stepEnd: Double

    init(_ beats: [Double]) {
        self.beats = beats
        func medianStep(_ s: ArraySlice<Double>) -> Double {
            TabScore.median(zip(s.dropFirst(), s).map { $0 - $1 }[...])
        }
        stepStart = medianStep(beats.prefix(16))
        stepEnd = medianStep(beats.suffix(16))
    }

    func time(_ q: Double) -> Double {
        let n = beats.count
        let i = Int(max(-1e9, min(1e9, q.rounded(.down))))
        if i < 0 { return beats[0] + q * stepStart }
        if i >= n - 1 { return beats[n - 1] + (q - Double(n - 1)) * stepEnd }
        return beats[i] + (q - Double(i)) * (beats[i + 1] - beats[i])
    }
}

/// Análisis de los stems, calculado una vez por stem.
final class StemAnalysis {
    let audio: [SongsterrStemRole: [Float]]
    private var spectra: [SongsterrStemRole: SemitoneSpectrogram] = [:]
    private var envelopes: [SongsterrStemRole: OnsetEnvelope] = [:]
    private var mixedGuitar: [Float]?

    init(audio: [SongsterrStemRole: [Float]]) {
        self.audio = audio
    }

    static let guitarParts: [SongsterrStemRole] = [.guitarLeft, .guitarRight, .guitarLead]

    /// Stem contra el que se alinea una pista: el de bajo, o el de guitarra completo (o la suma de L, R y solista).
    func referenceRole(for kind: TabTrackKind) -> SongsterrStemRole? {
        switch kind {
        case .bass: return audio[.bass] != nil ? .bass : nil
        case .guitar: return audio[.guitar] != nil || Self.guitarParts.contains { audio[$0] != nil } ? .guitar : nil
        case .drums: return audio[.drums] != nil ? .drums : nil
        case .vocal: return nil   // las voces no se miden contra ningún stem (Fase 5c, decisión 4)
        }
    }

    func samples(_ role: SongsterrStemRole) -> [Float] {
        if let a = audio[role] { return a }
        guard role == .guitar else { return [] }
        if let m = mixedGuitar { return m }
        let parts = Self.guitarParts.compactMap { audio[$0] }
        var mix = [Float](repeating: 0, count: parts.map(\.count).max() ?? 0)
        for p in parts { for i in p.indices { mix[i] += p[i] } }
        mixedGuitar = mix
        return mix
    }

    func spectrum(_ role: SongsterrStemRole) -> SemitoneSpectrogram {
        if let s = spectra[role] { return s }
        let s = SemitoneSpectrogram(samples: samples(role))
        spectra[role] = s
        return s
    }

    func salience(_ role: SongsterrStemRole) -> SalienceMap {
        let s = spectrum(role)
        return SalienceMap(values: s.salience(), frames: s.frameCount)
    }

    func envelope(_ role: SongsterrStemRole) -> OnsetEnvelope {
        if let e = envelopes[role] { return e }
        let e = OnsetEnvelope(samples: samples(role), sampleRate: SemitoneSpectrogram.sampleRate)
        envelopes[role] = e
        return e
    }
}
