/// Activaciones → golpes: `NotePeakPickingProcessor` del puerto de ADTOF, por columna y a 100 fps
/// (contrato de `docs/probes/P4-modelos.md`, «Batería (ADTOF)», fila «Picos»).
enum DrumPeaks {
    typealias C = DrumContract

    /// Golpes de unas activaciones [T][5] en orden C, ordenados por (tiempo, nota) como `hits.json`.
    static func hits(activations act: [Float], frames: Int) -> [TranscribedDrumHit] {
        let k = C.classes
        precondition(act.count == frames * k, "activaciones de \(act.count) valores, se esperaban \(frames) × \(k)")
        var found = [(frame: Int, midi: Int)]()
        for c in 0..<k {
            let column = (0..<frames).map { act[$0 * k + c] }
            for t in peakFrames(column, threshold: C.thresholds[c]) { found.append((t, C.midiNotes[c])) }
        }
        found.sort { ($0.frame, $0.midi) < ($1.frame, $1.midi) }
        return found.map { TranscribedDrumHit(time: Double($0.frame) / Double(C.framesPerSecond), midi: $0.midi) }
    }

    /// `p = max(0, a − media móvil)`: media de 12 tramas (10 antes, 1 después) con los bordes repitiendo el extremo.
    /// El original convoluciona en float32 con un núcleo float32 de 1/12; aquí se acumula en Double con ese mismo
    /// núcleo y se redondea a float32 (diferencia de 1 ulp como mucho; el test mide el margen frente a umbrales).
    static func processed(_ a: [Float]) -> [Float] {
        let n = a.count, pre = C.preAverageFrames, post = C.postAverageFrames
        guard n > 0 else { return [] }
        let kernel = Double(Float(1) / Float(pre + 1 + post))
        var p = [Float](repeating: 0, count: n)
        for t in 0..<n {
            var s = 0.0
            for j in (t - pre)...(t + post) { s += Double(a[min(max(j, 0), n - 1)]) * kernel }
            p[t] = max(0, a[t] - Float(s))
        }
        return p
    }

    /// Tramas con golpe de una columna: máximo local en 4 tramas (2 antes, 1 después, bordes repitiendo el extremo)
    /// con `p ≥ umbral`; los picos a ≤ 2 tramas del anterior forman grupo y queda el de mayor `p` (el primero si
    /// empatan).
    static func peakFrames(_ a: [Float], threshold: Float) -> [Int] {
        let p = processed(a)
        let n = p.count
        var peaks = [Int]()
        for t in 0..<n where p[t] >= threshold {
            var m = p[t]
            for j in (t - C.preMaxFrames)...(t + C.postMaxFrames) { m = max(m, p[min(max(j, 0), n - 1)]) }
            if p[t] >= m { peaks.append(t) }
        }
        var kept = [Int]()
        var group = [Int]()
        func close() {
            guard var best = group.first else { return }
            for i in group.dropFirst() where p[i] > p[best] { best = i }
            kept.append(best)
        }
        for t in peaks {
            if let last = group.last, t - last > C.combineFrames {
                close()
                group = []
            }
            group.append(t)
        }
        close()
        return kept
    }
}
