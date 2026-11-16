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
