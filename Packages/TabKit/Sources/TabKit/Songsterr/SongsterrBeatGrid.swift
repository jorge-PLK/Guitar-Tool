import Foundation

/// Qué hizo `SongsterrBeatGrid.prepare` con el tempo del modelo de pulso frente al escrito de Songsterr.
public enum SongsterrTempoFold: String, Codable, Sendable {
    /// El modelo marca negras: sin cambios.
    case same
    /// El modelo marcaba blancas (mitad de tempo): se añade un pulso en medio de cada par.
    case doubled
    /// El modelo marcaba corcheas (doble de tempo): se queda uno de cada dos.
    case halved
}

/// Pulsos del `BeatGrid` llevados a negras de Songsterr, para `SongsterrAligner.align` y `SongsterrBeatGrid.build`.
public struct SongsterrPreparedBeats: Sendable, Equatable {
    public var beats: BeatTimes
    /// Tempo escrito principal de Songsterr (BPM de negra): el que más negras ocupa en el tema.
    public var writtenTempo: Double
    /// Mediana de los intervalos del modelo de pulso antes de corregir, en BPM.
    public var detectedTempo: Double
    public var fold: SongsterrTempoFold
    /// Pulsos que faltaban (intervalo de dos o más pulsos) y se han añadido.
    public var insertedBeats: Int
    /// Pulsos sobrantes (dos intervalos cortos que suman uno) que se han quitado.
    public var removedBeats: Int
}

/// Un compás de la rejilla corregida.
public struct SongsterrMeterBar: Sendable, Equatable {
    /// Segundos de canción de su primer pulso.
    public var start: Double
    /// Pulsos que tiene en la grabación (menos que el compás escrito si la grabación tiene pulsos de menos).
    public var beatCount: Int
    public var beatUnit: Int
    /// BPM de negra escrito en Songsterr.
    public var writtenTempo: Double
    /// Compás tocado de Songsterr (índice en `SongsterrTrack.bars`); nil en pulsos que la grabación tiene de más.
    public var playedBar: Int?
}

/// Rejilla del metrónomo con Songsterr: pulsos con tiempos reales del audio, compás y primer tiempo de Songsterr.
/// `beats` y `downbeats` van tal cual a `BeatGrid(beats:downbeats:)` (StudyKit).
public struct SongsterrMeterGrid: Sendable, Equatable {
    /// Ordenados; uno por pulso del compás escrito (negra en 4/4, corchea en 6/8).
    public var beats: [Double]
    /// Subconjunto de `beats`: el primero de cada compás.
    public var downbeats: [Double]
    /// Compases dentro del tramo de la tablatura, en orden.
    public var bars: [SongsterrMeterBar]
    /// Tempo del tema para mostrar (el escrito principal).
    public var writtenTempo: Double
    public var fold: SongsterrTempoFold
    /// Pulsos de la tablatura colocados con un ataque de batería cerca.
    public var anchoredBeats: Int
    /// Pulsos de la tablatura (sin los del modelo de pulso de antes y después de ella).
    public var tabBeats: Int
    /// Los primeros compases se han movido al desfase del bloque siguiente (ver `SongsterrBeatGrid.leadingShifts`).
    /// `SongsterrAligner` ya aplica esa regla a sus bloques, así que con una alineación suya sale false.
    public var introRealigned = false
}

/// Rejilla del metrónomo a partir de la tablatura de Songsterr alineada (decisión de Jorge, 17/11/2026):
///
/// 1. `prepare`, antes de alinear: los pulsos del modelo se llevan a negras con el tempo escrito (corrige doble o
///    mitad) y se rellenan los pulsos perdidos sueltos (intervalos de 2× o más) y se quitan los sobrantes.
/// 2. `build`, tras alinear: cada pulso del compás escrito de cada compás tocado se coloca con el desfase de la
///    alineación (global y por bloques) sobre esos pulsos; los compases y su primer tiempo son los de Songsterr. Donde
///    la grabación tiene pulsos de más, entra un compás con esos pulsos; donde tiene de menos, el compás se acorta.
/// 3. Los tiempos siguen al audio, no a un BPM fijo: cada pulso busca el pico de la envolvente de ataques de la batería
///    a ±`onsetSearch` y se ajusta una recta local (tiempo real frente a tiempo escrito) en ±`fitHalfWidth` pulsos,
///    robusta a ataques fuera de sitio. Sin batería (o sin ataque claro) la recta pasa por los pulsos del modelo,
///    que quedan sin el escalón de 20 ms de sus tramas.
///
/// Antes y después de la tablatura se conservan los pulsos y compases del modelo. Sin Songsterr no se usa.
public enum SongsterrBeatGrid {
    // Reglas de `prepare`.
    /// Cociente periodo de negra escrito / periodo detectado que se toma como «el modelo marca corcheas» (doble de
    /// tempo).
    static let doubleTempoRatio = 1.7...2.4
    /// … y como «el modelo marca blancas» (mitad de tempo).
    static let halfTempoRatio = 0.42...0.6
    /// Un intervalo de entre estas veces la mediana local es un pulso perdido suelto. Solo se rellena uno: huecos
    /// mayores suelen ser un calderón o un corte (El roce, 239–241 s: 2,8× a 172 BPM).
    static let missingBeatRatio = 1.75...2.3
    /// Dos intervalos más cortos que esto por la mediana local que juntos dan uno (±`extraBeatTolerance`): sobra el
    /// pulso del medio.
    static let extraBeatRatio = 0.65
    static let extraBeatTolerance = 0.25
    /// Intervalos a cada lado para la mediana local.
    static let localSpan = 8

    // Reglas de `build`.
    /// Búsqueda del ataque de batería alrededor del pulso previsto: cubre el escalón de 20 ms del modelo y deja fuera
    /// la semicorchea a 200 BPM (75 ms).
    public static let onsetSearch = 0.050
    /// El pico vale al menos esto por la mediana de la envolvente en ±½ pulso, y al menos `minimumOnsetPeak` (la
    /// envolvente va dividida por su media).
    static let minimumOnsetContrast: Float = 2.0
    static let minimumOnsetPeak: Float = 0.5
    /// Pulsos a cada lado en la recta local (2 compases de 4/4 en total más el propio).
    public static let fitHalfWidth = 4
    /// Con menos ataques que esto en la ventana, la recta pasa por los pulsos del modelo en ±`modelFitHalfWidth`
    /// (el redondeo a tramas de 20 ms cambia despacio de un pulso a otro y una ventana corta no lo promedia).
    static let minimumFitOnsets = 3
    static let modelFitHalfWidth = 8
    /// Peso de un pulso del modelo frente a un ataque de batería en la recta.
    static let modelWeight = 0.1
    /// Ataques más lejos que esto de la primera recta no entran en la segunda.
    static let outlierTolerance = 0.025
    /// Separación mínima entre dos pulsos de la rejilla.
    static let minimumSpacing = 0.03

    // MARK: tempo escrito

    /// Tempo escrito principal: el BPM de negra que más negras ocupa en los compases tocados. nil sin compases.
    public static func writtenTempo(_ tracks: [SongsterrTrack]) -> Double? {
        guard let bars = referenceBars(tracks), !bars.isEmpty else { return nil }
        var weight: [Double: Double] = [:]
        for b in bars { weight[b.tempo, default: 0] += Double(b.length) / Double(SongsterrTrack.ticksPerQuarter) }
        return weight.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key
    }

    /// Compases de referencia: los de la primera pista que estima la alineación (todas las de una revisión los
    /// comparten), como `SongsterrAligner`.
    static func referenceBars(_ tracks: [SongsterrTrack]) -> [SongsterrBar]? {
        (tracks.first(where: SongsterrAligner.estimates) ?? tracks.first)?.bars
    }

    // MARK: 1. pulsos a negras

    /// Pulsos del modelo llevados a negras de Songsterr. Pasar `beats` del resultado a `SongsterrAligner.align` y a
    /// `build`.
    public static func prepare(_ input: BeatTimes, writtenTempo: Double) -> SongsterrPreparedBeats {
        prepare(input, writtenTempo: writtenTempo, options: PrepareOptions())
    }

    /// Reglas de `prepare` que se pueden apagar (bisección en las puertas de la Fase 5b).
    struct PrepareOptions {
        /// Comparar también con el periodo del tema al quitar y rellenar pulsos.
        var periodCheck = true
        /// Repartir tramos irregulares (`regularize`).
        var regularize = true
    }

    static func prepare(_ input: BeatTimes, writtenTempo: Double, options: PrepareOptions) -> SongsterrPreparedBeats {
        var beats = dedupe(input.beats)
        let ibi = zip(beats.dropFirst(), beats).map { $0 - $1 }
        let median = ibi.isEmpty ? 0 : TabScore.median(ibi[...])
        let detected = median > 0 ? 60 / median : 0
        var fold = SongsterrTempoFold.same
        var inserted = 0, removed = 0
        guard beats.count >= 3, median > 0, writtenTempo > 0 else {
            return SongsterrPreparedBeats(beats: BeatTimes(beats: beats, downbeats: input.downbeats,
                                                           beatsPerBar: input.beatsPerBar),
                                          writtenTempo: writtenTempo, detectedTempo: detected, fold: fold,
                                          insertedBeats: 0, removedBeats: 0)
        }
        let ratio = (60 / writtenTempo) / median
        if halfTempoRatio.contains(ratio) {
            fold = .doubled
            var out: [Double] = []
            for (a, b) in zip(beats, beats.dropFirst()) { out += [a, (a + b) / 2] }
            out.append(beats[beats.count - 1])
            beats = out
        } else if doubleTempoRatio.contains(ratio) {
            fold = .halved
            // Se queda la paridad que contiene más downbeats (los compases empiezan en negra).
            let parity = input.downbeats.map { nearestIndex(beats, $0) % 2 }
            let odd = parity.filter { $0 == 1 }.count
            let start = odd > parity.count - odd ? 1 : 0
            beats = stride(from: start, to: beats.count, by: 2).map { beats[$0] }
        }

        // Pulsos sobrantes y perdidos, contra la mediana local de intervalos y contra el periodo del tema (la mediana
        // tras el pliegue): un tramo entero a doble o mitad de tempo (Tornado Of Souls: estribillos a 100 BPM y el
        // «Break» a corcheas con el tema a 200) tiene la mediana local también doblada o partida y solo lo ve el
        // periodo del tema.
        let foldedIBI = zip(beats.dropFirst(), beats).map { $0 - $1 }
        let period = TabScore.median(foldedIBI[...])
        var cleaned: [Double] = []
        var i = 0
        while i < beats.count {
            // Contra el último pulso que se queda: en una racha de corcheas se quita uno de cada dos, no todos.
            if let prev = cleaned.last, i + 1 < beats.count {
                let local = localMedian(beats, around: i)
                let d0 = beats[i] - prev, d1 = beats[i + 1] - beats[i]
                func extra(_ ref: Double) -> Bool {
                    d0 < extraBeatRatio * ref && d1 < extraBeatRatio * ref && abs((d0 + d1) / ref - 1) <= extraBeatTolerance
                }
                if extra(local) || (options.periodCheck && extra(period)) {
                    removed += 1
                    i += 1
                    continue
                }
            }
            cleaned.append(beats[i])
            i += 1
        }
        var filled: [Double] = []
        for k in cleaned.indices {
            if k > 0 {
                let d = cleaned[k] - cleaned[k - 1]
                if missingBeatRatio.contains(d / localMedian(cleaned, around: k))
                    || (options.periodCheck && missingBeatRatio.contains(d / period)) {
                    filled.append(cleaned[k - 1] + d / 2)
                    inserted += 1
                }
            }
            filled.append(cleaned[k])
        }
        if options.regularize {
            let (regular, net) = regularize(filled)
            if net > 0 { inserted += net } else { removed -= net }
            filled = regular
        }
        var downbeats: [Double] = []
        for d in input.downbeats.sorted() {
            let t = filled[nearestIndex(filled, d)]
            if downbeats.last != t { downbeats.append(t) }
        }
        return SongsterrPreparedBeats(beats: BeatTimes(beats: filled, downbeats: downbeats, beatsPerBar: input.beatsPerBar),
                                      writtenTempo: writtenTempo, detectedTempo: detected, fold: fold,
                                      insertedBeats: inserted, removedBeats: removed)
    }

    /// Tramos irregulares que quedan tras quitar y rellenar pulsos sueltos (Tornado Of Souls: un pulso a medio
    /// intervalo, o 3 medios seguidos, en riffs de corcheas a 200 BPM): racha de intervalos fuera de
    /// `regularTolerance` de la mediana local entre dos pulsos regulares. Si el tramo dura un número entero de
    /// periodos (±`regularSpanTolerance`), sus pulsos se reparten iguales; si no (medio pulso de desfase que sigue, o un
    /// calderón), se deja. Huecos de más de `missingBeatRatio` no entran en una racha (corte o calderón).
    /// - Returns: los pulsos y cuántos hay de más (> 0) o de menos (< 0) que antes.
    static func regularize(_ beats: [Double]) -> (beats: [Double], net: Int) {
        guard beats.count >= 3 else { return (beats, 0) }
        var out: [Double] = [beats[0]]
        var net = 0
        var k = 1  // intervalo k: de beats[k − 1] a beats[k]
        while k < beats.count {
            let local = localMedian(beats, around: k)
            let r = (beats[k] - beats[k - 1]) / local
            guard abs(r - 1) > regularTolerance, r < missingBeatRatio.lowerBound else {
                out.append(beats[k])
                k += 1
                continue
            }
            func irregular(_ j: Int) -> Bool {
                let r = (beats[j] - beats[j - 1]) / local
                return abs(r - 1) > regularTolerance && r < missingBeatRatio.lowerBound
            }
            func runEnd(_ s: Int) -> Int {
                var e = s
                while e + 1 < beats.count, irregular(e + 1) { e += 1 }
                return e
            }
            func whole(_ e: Int) -> Bool {
                let x = (beats[e] - beats[k - 1]) / local
                return abs(x - x.rounded()) <= regularSpanTolerance
            }
            var e = runEnd(k)
            // Medio pulso de desfase que vuelve más adelante (0,5 … 0,5 o 1,5 … 0,5): el tramo entre los dos va a
            // contratiempo; se junta con la siguiente racha irregular si está a ≤ `phaseSlipSpan` intervalos y juntas
            // dan un número entero de periodos.
            if !whole(e), e + 2 < beats.count,
               let next = (e + 2..<min(beats.count, e + 2 + phaseSlipSpan)).first(where: irregular),
               whole(runEnd(next)) {
                e = runEnd(next)
            }
            let span = beats[e] - beats[k - 1]
            let n = (span / local).rounded()
            if n >= 1, abs(span / local - n) <= regularSpanTolerance, e + 1 < beats.count || n == Double(e - k + 1) {
                for m in 1...Int(n) { out.append(beats[k - 1] + span * Double(m) / n) }
                net += Int(n) - (e - k + 1)
            } else {
                out.append(contentsOf: beats[k...e])
            }
            k = e + 1
        }
        return (out, net)
    }
    /// Un intervalo a menos de esto (relativo) de la mediana local es regular.
    static let regularTolerance = 0.3
    /// Un tramo irregular se reparte si dura un número entero de periodos con este margen.
    static let regularSpanTolerance = 0.25
    /// Intervalos regulares que puede durar un tramo a contratiempo entre dos medios pulsos de desfase (4 compases de
    /// 4/4).
    static let phaseSlipSpan = 16

    /// Mediana de los intervalos a ±`localSpan` del pulso `i` sin contar los dos que lo tocan.
    static func localMedian(_ beats: [Double], around i: Int) -> Double {
        let lo = max(1, i - localSpan), hi = min(beats.count - 1, i + localSpan)
        var d: [Double] = []
        for k in lo...hi where k != i && k != i + 1 { d.append(beats[k] - beats[k - 1]) }
        if d.isEmpty { for k in 1..<beats.count { d.append(beats[k] - beats[k - 1]) } }
        return TabScore.median(d[...])
    }

    static func dedupe(_ beats: [Double]) -> [Double] {
        var out: [Double] = []
        for t in beats.sorted() where out.last.map({ t - $0 > 1e-6 }) ?? true { out.append(t) }
        return out
    }

    static func nearestIndex(_ a: [Double], _ x: Double) -> Int {
        var lo = 0, hi = a.count
        while lo < hi { let m = (lo + hi) / 2; if a[m] < x { lo = m + 1 } else { hi = m } }
        if lo == 0 { return 0 }
        if lo == a.count { return a.count - 1 }
        return x - a[lo - 1] <= a[lo] - x ? lo - 1 : lo
    }

    // MARK: 2–3. rejilla

    /// Rejilla corregida. CPU (lee la batería): fuera del hilo principal.
    ///
    /// - Parameters:
    ///   - prepared: lo que devolvió `prepare` (sus `beats` son los que se pasaron a `align`).
    ///   - tracks: las mismas pistas que se alinearon.
    ///   - drums: stem de batería; nil = los tiempos salen solo de los pulsos del modelo, suavizados.
    public static func build(prepared: SongsterrPreparedBeats, tracks: [SongsterrTrack], alignment: SongsterrAlignment,
                             drums: URL?) throws -> SongsterrMeterGrid {
        let samples = try drums.map { try MonoAudio.load($0, sampleRate: SemitoneSpectrogram.sampleRate) }
        return build(prepared: prepared, refBars: referenceBars(tracks) ?? [], offset: alignment.offsetBeats,
                     shifts: alignment.usesBlocks ? alignment.blocks.map(\.shift) : [],
                     drums: samples.map { Drums(samples: $0) })
    }

    /// Un pulso de la tablatura antes de llevarlo al audio.
    struct TabBeat {
        /// Pulso fraccionario del modelo (negras).
        var g: Double
        /// Negras que dura.
        var length: Double
        var tempo: Double
        var beatUnit: Int
        /// Compás tocado; nil = pulso que la grabación tiene de más.
        var bar: Int?
        /// Grupo de compás (cambia en cada compás, también entre los de más).
        var group: Int
        var first: Bool
    }

    /// - Parameter shifts: desfase por bloque de la alineación; vacío si no usa bloques.
    static func build(prepared: SongsterrPreparedBeats, refBars: [SongsterrBar], offset: Int, shifts: [Int],
                      drums: Drums?) -> SongsterrMeterGrid {
        let model = dedupe(prepared.beats.beats)
        let modelDownbeats = prepared.beats.downbeats
        let empty = SongsterrMeterGrid(beats: model, downbeats: modelDownbeats, bars: [],
                                       writtenTempo: prepared.writtenTempo, fold: prepared.fold, anchoredBeats: 0,
                                       tabBeats: 0, introRealigned: false)
        guard model.count >= 2, !refBars.isEmpty else { return empty }
        let line = BeatLine(model)
        let tpq = Double(SongsterrTrack.ticksPerQuarter)
        let barStartQ = refBars.map { Double($0.start) / tpq }
        // El ajuste fino de la alineación es el de las notas (ataque de guitarra frente a tramas de CQT); los pulsos
        // del metrónomo se quedan en los del modelo y el audio.
        let leading = leadingShifts(shifts, offset: offset, barStartQ: barStartQ, model: model,
                                    downbeats: modelDownbeats)
        let placement = Placement(offset: offset, fine: 0, shifts: leading, barStartQ: barStartQ)

        // Pulsos escritos de cada compás tocado que la grabación tiene.
        var tab: [TabBeat] = []
        for (j, bar) in refBars.enumerated() {
            let length = Double(bar.beatLength) / tpq
            for k in 0..<bar.beatCount {
                let q = barStartQ[j] + Double(k) * length
                guard placement.keeps(q: q, bar: j) else { continue }
                tab.append(TabBeat(g: placement.gridBeat(q: q, bar: j), length: length, tempo: bar.tempo,
                                   beatUnit: bar.beatUnit, bar: j, group: j, first: k == 0))
            }
        }
        // Pulsos de más en la grabación: un compás con ellos.
        var withExtra: [TabBeat] = []
        var extraGroup = refBars.count
        for (n, b) in tab.enumerated() {
            withExtra.append(b)
            guard n + 1 < tab.count else { continue }
            let gap = tab[n + 1].g - b.g
            let extra = Int(((gap - b.length) / b.length).rounded())
            guard extra >= 1 else { continue }
            for m in 1...extra {
                withExtra.append(TabBeat(g: b.g + Double(m) * b.length, length: b.length, tempo: b.tempo,
                                         beatUnit: b.beatUnit, bar: nil, group: extraGroup, first: m == 1))
            }
            extraGroup += 1
        }
        // Tramo de la grabación: desde un compás antes del primer pulso del modelo hasta medio pulso tras el último.
        let firstPeriod = line.time(1) - line.time(0)
        let lastPeriod = model[model.count - 1] - model[model.count - 2]
        let firstBarSpan = Double(refBars[0].length) / tpq * firstPeriod
        let lo = max(0, model[0] - firstBarSpan), hi = model[model.count - 1] + 0.5 * lastPeriod
        let kept = withExtra.filter { (lo...hi).contains(line.time($0.g)) }
        guard kept.count >= 2 else { return empty }

        // Tiempo escrito de cada pulso (segundos a los tempos de Songsterr, contando solo los que suenan).
        var written = [Double](repeating: 0, count: kept.count)
        for n in 1..<kept.count {
            written[n] = written[n - 1] + kept[n - 1].length * 60 / max(1, kept[n - 1].tempo)
        }
        let predicted = kept.map { line.time($0.g) }
        var anchored = 0
        let onsets: [Double?] = predicted.indices.map { n in
            guard let drums else { return nil }
            let period = n + 1 < predicted.count ? predicted[n + 1] - predicted[n] : predicted[n] - predicted[n - 1]
            let t = onset(near: predicted[n], period: period, drums: drums)
            if t != nil { anchored += 1 }
            return t
        }
        var times = predicted.indices.map { n in
            fit(at: n, written: written, onsets: onsets, predicted: predicted)
        }
        for n in 1..<times.count where times[n] < times[n - 1] + minimumSpacing {
            times[n] = times[n - 1] + minimumSpacing
        }

        // Compases.
        var bars: [SongsterrMeterBar] = []
        var downbeats: [Double] = []
        var open: Int?
        for (n, b) in kept.enumerated() {
            if n == 0 || b.group != kept[n - 1].group {
                open = nil
                // Un compás cuyo primer pulso quedó antes del tramo no tiene primer tiempo.
                if b.first {
                    bars.append(SongsterrMeterBar(start: times[n], beatCount: 0, beatUnit: b.beatUnit,
                                                  writtenTempo: b.tempo, playedBar: b.bar))
                    downbeats.append(times[n])
                    open = b.group
                }
            }
            if open == b.group { bars[bars.count - 1].beatCount += 1 }
        }

        // Fuera de la tablatura, los pulsos del modelo.
        let first = times[0], last = times[times.count - 1]
        let before = model.filter { $0 < first - 0.6 * firstPeriod }
        let after = model.filter { $0 > last + 0.6 * lastPeriod }
        let outside = Set(before + after)
        let allBeats = before + times + after
        let allDownbeats = modelDownbeats.filter { outside.contains($0) && $0 < first } + downbeats
            + modelDownbeats.filter { outside.contains($0) && $0 > last }
        return SongsterrMeterGrid(beats: allBeats, downbeats: allDownbeats, bars: bars,
                                  writtenTempo: prepared.writtenTempo, fold: prepared.fold, anchoredBeats: anchored,
                                  tabBeats: kept.count, introRealigned: leading != shifts)
    }

    /// Desfase de los primeros bloques. Antes del primer cambio de desfase de la alineación la grabación no tiene
    /// contexto: un cambio ahí suele ser un compás de cuenta o una anacrusa que Songsterr escribe como compás entero
    /// (El roce: el compás 1 son dos silencios de negra en 4/4), y la saliencia de un intro de acordes largos no lo
    /// distingue. Si con el desfase del bloque siguiente caen más inicios de compás sobre downbeats del modelo de
    /// pulso que con el suyo, los primeros bloques toman el del siguiente.
    static func leadingShifts(_ shifts: [Int], offset: Int, barStartQ: [Double], model: [Double],
                              downbeats: [Double]) -> [Int] {
        guard let change = shifts.firstIndex(where: { $0 != shifts[0] }) else { return shifts }
        let isDownbeat = Set(downbeats.map { nearestIndex(model, $0) })
        let bars = 0..<min(change * SongsterrAligner.blockBars, barStartQ.count)
        func votes(_ s: Int) -> Int {
            bars.filter { j in
                let g = (barStartQ[j] + Double(offset + s)).rounded()
                return g >= 0 && g < Double(model.count) && isDownbeat.contains(Int(g))
            }.count
        }
        guard votes(shifts[change]) > votes(shifts[0]) else { return shifts }
        var out = shifts
        for b in 0..<change { out[b] = shifts[change] }
        return out
    }

    /// Stem de batería: muestras y envolvente de ataques.
    struct Drums {
        let samples: [Float]
        let sampleRate: Double
        let envelope: OnsetEnvelope

        init(samples: [Float], sampleRate: Double = SemitoneSpectrogram.sampleRate) {
            self.samples = samples
            self.sampleRate = sampleRate
            envelope = OnsetEnvelope(samples: samples, sampleRate: sampleRate)
        }
    }

    // Ataque fino, a nivel de muestra, alrededor del pico de la envolvente (tramas de 5,8 ms).
    /// Ventana de la energía corta (centrada).
    static let energyWindow = 0.001
    /// Se busca el ataque fino a ±esto del grueso.
    static let fineSearch = 0.015
    /// Nivel previo: la mediana de la energía en los `floorSpan` s antes de la búsqueda fina.
    static let floorSpan = 0.010
    /// El ataque es el último cruce, antes del máximo, de suelo + `attackLevel`·(máximo − suelo) en energía (−7 dB
    /// de amplitud sobre el suelo).
    static let attackLevel = 0.2

    /// Ataque de batería junto a `time`: el pico más fuerte de la envolvente a ±`onsetSearch` (nil si no destaca) y,
    /// desde él, el cruce de nivel de la energía corta.
    static func onset(near time: Double, period: Double, drums: Drums) -> Double? {
        let env = drums.envelope
        let v = env.values
        guard !v.isEmpty else { return nil }
        func frame(_ t: Double) -> Int { Int(((t - OnsetEnvelope.peakAdvance - env.start) * env.frameRate).rounded()) }
        let a = max(1, frame(time - onsetSearch)), b = min(v.count - 2, frame(time + onsetSearch))
        guard a <= b else { return nil }
        var best = a
        for i in a...b where v[i] > v[best] { best = i }
        let ca = max(0, frame(time - period / 2)), cb = min(v.count - 1, frame(time + period / 2))
        guard ca < cb else { return nil }
        let around = v[ca...cb].sorted()
        let floor = around[around.count / 2]
        guard v[best] >= minimumOnsetPeak, v[best] >= minimumOnsetContrast * floor else { return nil }
        let coarse = env.start + Double(best) / env.frameRate + OnsetEnvelope.peakAdvance
        return fineAttack(near: coarse, drums: drums) ?? coarse
    }

    /// Cruce de nivel de la energía corta (`energyWindow`) a ±`fineSearch` de `coarse`, interpolado entre muestras.
    static func fineAttack(near coarse: Double, drums: Drums) -> Double? {
        let x = drums.samples, sr = drums.sampleRate
        let w = max(2, Int(energyWindow * sr))
        let lo = Int(((coarse - fineSearch - floorSpan) * sr).rounded()) - w
        let hi = Int(((coarse + fineSearch) * sr).rounded()) + w
        guard lo >= 0, hi < x.count else { return nil }
        // Energía media en una ventana centrada de w muestras, por suma acumulada.
        var cum = [Double](repeating: 0, count: hi - lo + 2)
        for i in lo...hi { cum[i - lo + 1] = cum[i - lo] + Double(x[i]) * Double(x[i]) }
        let half = w / 2
        let first = lo + half, last = hi - (w - half)
        guard last > first else { return nil }
        let e = (first...last).map { i in (cum[i - lo + w - half] - cum[i - lo - half]) / Double(w) }
        func index(_ t: Double) -> Int { min(max(0, Int((t * sr).rounded()) - first), e.count - 1) }
        let s0 = index(coarse - fineSearch), s1 = index(coarse + fineSearch)
        var peak = s0
        for i in s0...s1 where e[i] > e[peak] { peak = i }
        let floorValues = e[index(coarse - fineSearch - floorSpan)..<max(index(coarse - fineSearch - floorSpan) + 1, s0)].sorted()
        let floor = floorValues[floorValues.count / 2]
        guard e[peak] > 4 * floor else { return nil }
        let level = floor + attackLevel * (e[peak] - floor)
        var i = peak
        while i > s0, e[i - 1] >= level { i -= 1 }
        guard i > s0 else { return nil }
        // Entre las muestras i−1 (bajo el nivel) e i (sobre él).
        let frac = (level - e[i - 1]) / max(1e-30, e[i] - e[i - 1])
        return (Double(first + i - 1) + frac) / sr
    }

    /// Recta ponderada de tiempo real frente a tiempo escrito en ±`fitHalfWidth` pulsos, evaluada en el pulso `n`:
    /// ataques con peso 1 (los que se alejan más de `outlierTolerance` de una primera recta fuera) y pulsos del modelo
    /// con peso `modelWeight` donde no hay ataque.
    static func fit(at n: Int, written: [Double], onsets: [Double?], predicted: [Double]) -> Double {
        var lo = max(0, n - fitHalfWidth), hi = min(written.count - 1, n + fitHalfWidth)
        if onsets[lo...hi].filter({ $0 != nil }).count < minimumFitOnsets {
            lo = max(0, n - modelFitHalfWidth)
            hi = min(written.count - 1, n + modelFitHalfWidth)
        }
        var pts: [(x: Double, y: Double, w: Double, onset: Bool)] = []
        for k in lo...hi {
            if let o = onsets[k] { pts.append((written[k] - written[n], o, 1, true)) }
            else { pts.append((written[k] - written[n], predicted[k], modelWeight, false)) }
        }
        func line(_ p: [(x: Double, y: Double, w: Double, onset: Bool)]) -> (a: Double, b: Double)? {
            var sw = 0.0, sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0
            for q in p { sw += q.w; sx += q.w * q.x; sy += q.w * q.y; sxx += q.w * q.x * q.x; sxy += q.w * q.x * q.y }
            guard sw > 0 else { return nil }
            let den = sw * sxx - sx * sx
            guard abs(den) > 1e-12 else { return (sy / sw, 0) }
            let b = (sw * sxy - sx * sy) / den
            return ((sy - b * sx) / sw, b)
        }
        guard let first = line(pts) else { return predicted[n] }
        let robust = pts.filter { !$0.onset || abs($0.y - (first.a + first.b * $0.x)) <= outlierTolerance }
        return (line(robust) ?? first).a
    }
}
