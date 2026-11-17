/// Números de basic-pitch 0.4.0 (`constants.py`, `inference.py`, `note_creation.py`), modelo ICASSP 2022 (`nmp`).
/// Mini-spec Fase 4, «Clasificación rítmica o solista»: Basic Pitch con su modelo Core ML oficial.
enum BasicPitchContract {
    /// `AUDIO_SAMPLE_RATE`.
    static let sampleRate = 22_050.0
    /// `FFT_HOP`: muestras por fotograma de salida.
    static let fftHop = 256
    /// `AUDIO_N_SAMPLES` = 22 050 · 2 − 256: muestras de una ventana de entrada.
    static let windowSamples = 43_844
    /// `ANNOT_N_FRAMES` = (22 050 div 256) · 2: fotogramas que saca el modelo por ventana.
    static let windowFrames = 172
    /// `ANNOTATIONS_FPS` = 22 050 div 256.
    static let framesPerSecond = 86
    /// `run_inference`: 30 fotogramas de solape entre ventanas.
    static let overlapFrames = 30
    static let overlapSamples = overlapFrames * fftHop
    static let hopSamples = windowSamples - overlapSamples
    /// `unwrap_output`: se quitan 15 fotogramas al principio y al final de cada ventana.
    static let trimFrames = overlapFrames / 2
    static let keptFramesPerWindow = windowFrames - 2 * trimFrames
    /// `ANNOTATIONS_N_SEMITONES`: 88 teclas de piano, A0 = MIDI 21 (`MIDI_OFFSET`).
    static let nPitches = 88
    static let midiOffset = 21

    /// Valores por defecto de `basic_pitch.inference.predict`.
    static let onsetThreshold = 0.5
    static let frameThreshold = 0.3
    static let minimumNoteLengthMs = 127.70
    /// `int(np.round(127.70 / 1000 · (22 050 / 256)))` = 11 fotogramas.
    static var minimumNoteFrames: Int {
        Int((minimumNoteLengthMs / 1000 * (sampleRate / Double(fftHop))).rounded(.toNearestOrEven))
    }
    /// Pico por debajo del cual una ventana no pasa por el modelo y da posteriorgramas a cero: −120 dBFS.
    /// `NormalizedLog` de basic-pitch normaliza cada ventana con `divide_no_nan`, pero el `nmp.mlpackage` oficial lo
    /// convirtió en `real_div`: con una ventana muda el espectrograma es constante y queda 0/0. Medido en Fase 5b
    /// frente a ONNX (la referencia): ventana de ceros en Core ML CPU+GPU → note 0,84 de media (máx 0,900) y onset
    /// 0,659 en las 88 notas (las notas fantasma de amplitud 0,86–0,90 de `guitar_lead`); ONNX → note ≤ 0,161,
    /// onset ≤ 0,169. Core ML se aparta de ONNX con picos ≤ −140 dBFS (ruido) o ≤ −130 (impulso) y coincide a ≤ 0,004
    /// desde −130 (ruido). Con picos ≤ −120 dBFS ONNX da note ≤ 0,242 < `frameThreshold`, sin notas: los ceros dan
    /// las mismas notas que la referencia.
    static let silentWindowPeak: Float = 1e-6

    /// `output_to_notes_polyphonic(energy_tol=11)` y `get_infered_onsets(n_diff=2)`.
    static let energyTolerance = 11
    static let onsetDiffFrames = 2

    /// `model_frames_to_time`: desfase por ventana, (256 / 22 050) · (172 − 43 844 / 256) + 0,0018 («magic number»
    /// de basic-pitch, que corrige con ventanas de 172 el corrimiento real de 188 muestras cada 142 fotogramas).
    static let windowTimeOffset = (Double(fftHop) / sampleRate)
        * (Double(windowFrames) - Double(windowSamples) / Double(fftHop)) + 0.0018

    /// Tiempo en segundos del fotograma `j` de la salida desenrollada, como `model_frames_to_time`.
    static func time(ofFrame j: Int) -> Double {
        Double(j * fftHop) / sampleRate - windowTimeOffset * Double(j / windowFrames)
    }

    /// `unwrap_output`: fotogramas que quedan para `n` muestras de audio, floor(n · 86 / 22 050).
    static func outputFrames(forSamples n: Int) -> Int {
        Int((Double(n) * (Double(framesPerSecond) / sampleRate)).rounded(.down))
    }
}
