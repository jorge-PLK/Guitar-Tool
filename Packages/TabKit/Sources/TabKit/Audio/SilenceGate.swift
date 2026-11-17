import Accelerate

/// Puerta de silencio para notas transcritas, independiente del modelo: quita las notas que caen donde el stem está
/// en silencio (Fase 5b, «Limpieza de lo que da Basic Pitch»).
///
/// Nivel: RMS por tramos de 10 ms, en dBFS respecto a 1,0 (un seno a plena escala da −3 dBFS). Se quita la nota si
/// - su ataque es silencio: el tramo más fuerte entre `start − attackLead` y `start + attackSpan` queda por debajo
///   del umbral (el margen delante cubre el adelanto de hasta dos fotogramas de Basic Pitch, 23 ms), o
/// - la mayor parte de su duración es silencio: menos de la mitad de sus tramos llega al umbral.
public enum SilenceGate {
    /// Umbral en dBFS (RMS de 10 ms). Medido en los stems de «El roce de tu cuerpo» (RMS de 50 ms, 250 s):
    /// - silencio digital: `guitar_lead` es cero exacto de 0 a 158,2 s (−∞);
    /// - ruido de fondo de la separación: la intro de 0 a 3,5 s está por debajo de −75,7 dBFS en guitar_L/R y bajo,
    ///   las pausas (24,8–27 s, 224,7–225,4 s) bajan a −95/−105 dBFS y no pasan de −61,8; `vocals` sin voz vive
    ///   entre −100 y −136 dBFS (percentiles 25/10/5: −111/−120/−123);
    /// - tocando: percentil 5 de guitar_L −34,2 dBFS, de guitar_R −30,5, del bajo −27,9; percentil 1 del solo −24,1.
    /// −60 deja 15 dB sobre el ruido de la intro y 26 dB bajo lo más flojo que se toca. Basic Pitch normaliza cada
    /// ventana de 2 s, así que inventa notas incluso con ruido a −90 dBFS (ONNX: 30 ataques > 0,5 en una ventana).
    public static let thresholdDBFS: Float = -60
    /// Tramo de medida: 10 ms.
    static let blockSeconds = 0.010
    /// Ventana del ataque alrededor de `start`: 25 ms antes y 50 ms después.
    static let attackLead = 0.025
    static let attackSpan = 0.050
    /// Fracción mínima de la duración por encima del umbral.
    static let minimumAudibleFraction = 0.5

    /// Notas que sobreviven, en el mismo orden. `audio`: mono, el mismo que se transcribió.
    public static func filter(_ notes: [NoteEvent], audio: [Float], sampleRate: Double,
                              thresholdDBFS: Float = thresholdDBFS) -> [NoteEvent] {
        guard !notes.isEmpty else { return [] }
        let levels = Levels(audio: audio, sampleRate: sampleRate)
        let floor = powf(10, thresholdDBFS / 20)
        return notes.filter { n in
            let attack = levels.maxRMS(from: n.start - attackLead, to: n.start + attackSpan)
            guard attack >= floor else { return false }
            return levels.fractionAtLeast(floor, from: n.start, to: n.end) >= minimumAudibleFraction
        }
    }

    /// RMS por tramo de `blockSeconds`.
    struct Levels {
        let rms: [Float]
        let blockSeconds: Double

        init(audio: [Float], sampleRate: Double) {
            let size = max(1, Int((sampleRate * SilenceGate.blockSeconds).rounded()))
            blockSeconds = Double(size) / sampleRate
            let count = (audio.count + size - 1) / size
            var rms = [Float](repeating: 0, count: count)
            audio.withUnsafeBufferPointer { a in
                for b in 0..<count {
                    let lo = b * size, n = min(size, audio.count - lo)
                    vDSP_rmsqv(a.baseAddress! + lo, 1, &rms[b], vDSP_Length(n))
                }
            }
            self.rms = rms
        }

        /// Tramos que tocan [from, to) (al menos uno, recortado al audio); vacío si cae entero fuera.
        func blocks(from: Double, to: Double) -> Range<Int> {
            let lo = max(0, Int((from / blockSeconds).rounded(.down)))
            let hi = min(rms.count, max(lo + 1, Int((to / blockSeconds).rounded(.up))))
            return lo < hi ? lo..<hi : 0..<0
        }

        func maxRMS(from: Double, to: Double) -> Float {
            let r = blocks(from: from, to: to)
            return r.isEmpty ? 0 : rms[r].max()!
        }

        func fractionAtLeast(_ floor: Float, from: Double, to: Double) -> Double {
            let r = blocks(from: from, to: to)
            guard !r.isEmpty else { return 0 }
            return Double(rms[r].lazy.filter { $0 >= floor }.count) / Double(r.count)
        }
    }
}
