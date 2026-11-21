import Foundation
import NativeDSP

/// Port de `output_to_notes_polyphonic` (basic-pitch 0.4.0, `note_creation.py`) con `infer_onsets` y
/// `melodia_trick`, sin límites de frecuencia, y de los tiempos de `model_output_to_notes`. Mismo orden de
/// operaciones y misma aritmética (float64 donde numpy promociona) para que las notas salgan idénticas; lo
/// comprueba `BasicPitchNotesTests` contra el original de Python.
enum BasicPitchNotes {
    typealias C = BasicPitchContract

    /// Una nota en fotogramas: [start, end), índice MIDI y amplitud.
    struct FrameNote: Equatable {
        var start: Int
        var end: Int
        var pitch: Int
        var amplitude: Float
    }

    static func noteEvents(_ post: Posteriorgram) -> [NoteEvent] {
        notes(note: post.note, onset: post.onset, frames: post.frames).map {
            NoteEvent(start: C.time(ofFrame: $0.start), end: C.time(ofFrame: $0.end), pitch: $0.pitch, amplitude: $0.amplitude)
        }
    }

    /// Mismo orden que Python: primero las notas con onset (de la última a la primera), luego las de melodia.
    static func notes(note: [Float], onset: [Float], frames n: Int,
                      onsetThreshold: Double = C.onsetThreshold,
                      frameThreshold: Double = C.frameThreshold,
                      minNoteFrames: Int = C.minimumNoteFrames,
                      energyTolerance: Int = C.energyTolerance) -> [FrameNote] {
        let p = C.nPitches
        precondition(note.count == n * p && onset.count == n * p)
        guard n > 0 else { return [] }
        let maxIdx = p - 1   // MAX_FREQ_IDX

        var energy = [Double](repeating: 0, count: n * p)   // remaining_energy (float64)
        DSP.convertElements(of: note, to: &energy)
        var out: [FrameNote] = []

        func amplitude(_ s: Int, _ e: Int, _ f: Int) -> Float {
            // np.mean(frames[s:e, f]) sobre float32
            var m: Float = 0
            note.withUnsafeBufferPointer { DSP.meanv($0.baseAddress! + s * p + f, p, &m, DSPLength(e - s)) }
            return m
        }

        // 1. Onsets: picos locales en el tiempo (scipy.signal.argrelmax, axis 0) ≥ umbral, hacia atrás en el tiempo.
        if let onsets = inferredOnsets(note: note, onset: onset, frames: n) {
            var peaks: [(t: Int, f: Int)] = []
            if n >= 3 {
                for t in 1..<(n - 1) {
                    for f in 0..<p {
                        let v = onsets[t * p + f]
                        if v > onsets[(t - 1) * p + f] && v > onsets[(t + 1) * p + f] && v >= onsetThreshold {
                            peaks.append((t, f))
                        }
                    }
                }
            }
            for (s, f) in peaks.reversed() {
                if s >= n - 1 { continue }
                var i = s + 1, k = 0
                while i < n - 1 && k < energyTolerance {
                    if energy[i * p + f] < frameThreshold { k += 1 } else { k = 0 }
                    i += 1
                }
                i -= k
                if i - s <= minNoteFrames { continue }
                for t in s..<i {
                    energy[t * p + f] = 0
                    if f < maxIdx { energy[t * p + f + 1] = 0 }
                    if f > 0 { energy[t * p + f - 1] = 0 }
                }
                out.append(FrameNote(start: s, end: i, pitch: f + C.midiOffset, amplitude: amplitude(s, i, f)))
            }
        }

        // 2. melodia_trick: mientras quede energía > umbral, desde el máximo (primer argmax en orden C) hacia
        //    delante y hacia atrás. El máximo por fila se mantiene al día para no recorrer la matriz entera.
        var rowMax = [Double](repeating: 0, count: n)
        func refreshRows(_ lo: Int, _ hi: Int) {
            energy.withUnsafeBufferPointer { e in
                for t in max(0, lo)...min(n - 1, hi) { DSP.maxvD(e.baseAddress! + t * p, 1, &rowMax[t], DSPLength(p)) }
            }
        }
        refreshRows(0, n - 1)
        func zero(_ t: Int, _ f: Int) {
            energy[t * p + f] = 0
            if f < maxIdx { energy[t * p + f + 1] = 0 }
            if f > 0 { energy[t * p + f - 1] = 0 }
        }
        while true {
            var iMid = 0
            for t in 1..<n where rowMax[t] > rowMax[iMid] { iMid = t }
            let top = rowMax[iMid]
            guard top > frameThreshold else { break }
            var f = 0
            while energy[iMid * p + f] != top { f += 1 }
            energy[iMid * p + f] = 0

            var i = iMid + 1, k = 0
            while i < n - 1 && k < energyTolerance {
                if energy[i * p + f] < frameThreshold { k += 1 } else { k = 0 }
                zero(i, f)
                i += 1
            }
            let lastForward = i - 1
            let iEnd = i - 1 - k

            i = iMid - 1
            k = 0
            while i > 0 && k < energyTolerance {
                if energy[i * p + f] < frameThreshold { k += 1 } else { k = 0 }
                zero(i, f)
                i -= 1
            }
            let firstBackward = i + 1
            let iStart = i + 1 + k
            refreshRows(min(firstBackward, iMid), max(lastForward, iMid))

            if iEnd - iStart <= minNoteFrames { continue }
            out.append(FrameNote(start: iStart, end: iEnd, pitch: f + C.midiOffset, amplitude: amplitude(iStart, iEnd, f)))
        }
        return out
    }

    /// `get_infered_onsets(n_diff=2)`: max(onset, min de las diferencias a 1 y 2 fotogramas, ≥ 0, reescalado al
    /// máximo de onset), en float64. Si las diferencias son todas 0, numpy divide 0/0 y todo queda NaN: no hay
    /// notas por onset (devuelve nil).
    static func inferredOnsets(note: [Float], onset: [Float], frames n: Int) -> [Double]? {
        let p = C.nPitches, nd = C.onsetDiffFrames
        var frames = [Double](repeating: 0, count: n * p)
        DSP.convertElements(of: note, to: &frames)
        var diff = [Double](repeating: 0, count: n * p)
        for t in nd..<max(nd, n) {   // filas 0..<n_diff a 0 (`frame_diff[:n_diff, :] = 0`)
            for f in 0..<p {
                let x = frames[t * p + f]
                var d = x - frames[(t - 1) * p + f]
                for back in 2...nd { d = min(d, x - frames[(t - back) * p + f]) }
                diff[t * p + f] = max(d, 0)
            }
        }
        let maxDiff = DSP.maximum(diff)
        guard maxDiff > 0 else { return nil }
        let maxOnset = Double(DSP.maximum(onset))
        var res = [Double](repeating: 0, count: n * p)
        DSP.convertElements(of: onset, to: &res)
        for i in 0..<(n * p) {
            res[i] = max(res[i], maxOnset * diff[i] / maxDiff)
        }
        return res
    }
}
