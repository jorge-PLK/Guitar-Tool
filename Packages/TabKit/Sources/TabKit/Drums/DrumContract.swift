/// Un golpe de batería: instante en segundos desde el principio del audio y nota MIDI de percusión GM
/// (bombo 35, caja 38, tom 47, charles 42, platos 49). La pista de batería de la partitura se construye con esto.
public struct TranscribedDrumHit: Sendable, Equatable, Hashable, Codable {
    public var time: Double
    public var midi: Int

    public init(time: Double, midi: Int) {
        self.time = time
        self.midi = midi
    }
}

/// Números de ADTOF Frame_RNN (puerto `xavriley/ADTOF-pytorch` 85c192e: `audio.py` y `post_processing.py`).
/// Mini-spec Fase 5, «Transcripción», Batería, y contrato de `docs/probes/P4-modelos.md`, «Batería (ADTOF)».
enum DrumContract {
    /// Preproceso: mono a 44,1 kHz, STFT 2048 con salto 441 (100 fps), `center=True` con ceros.
    static let sampleRate = 44_100.0
    static let fftSize = 2048
    static let hop = 441
    static let framesPerSecond = 100
    /// |X|[0:1024]: sin el bin de Nyquist.
    static let magnitudeBins = fftSize / 2
    /// Banco logarítmico estilo madmom: 12 bandas por octava de 20 Hz a 20 kHz → 84 bandas.
    static let bandsPerOctave = 12
    static let minFrequency = 20.0
    static let maxFrequency = 20_000.0
    static let bands = 84

    /// Entrada `spec` [1, T, 84, 1] f32 con T entre 100 y 60 000; salida `act` [1, T, 5].
    static let minModelFrames = 100
    static let maxModelFrames = 60_000
    /// Tramas de contexto a cada lado de un trozo cuando T > 60 000 (temas de más de 10 min). Elegido aquí, no
    /// viene de la spec: la GRU bidireccional tarda en olvidar. Medido en T1 frente a una pasada
    /// (`DrumHeavyModelTests.testChunkSeams`, trozos de 10 000): |Δ act| 7,3e-3 con 10 s (un golpe cambia),
    /// 3,7e-4 con 20 s y 2,8e-5 con 30 s (golpes iguales). 30 s deja la unión bajo la tolerancia de activación de
    /// la spec (1e-4) por un 10 % más de cálculo en trozos de 60 000.
    static let chunkContextFrames = 3000

    /// Columnas de `act`: bombo, caja, tom, charles, platos (MIDI de percusión GM).
    static let midiNotes = [35, 38, 47, 42, 49]
    static var classes: Int { midiNotes.count }
    /// `FRAME_RNN_THRESHOLDS`. En Float: numpy compara el `proc` float32 con el umbral pasado a float32.
    static let thresholds: [Float] = [0.22, 0.24, 0.32, 0.22, 0.30]
    /// `NotePeakPickingProcessor` (pre_avg 0,1 s, post_avg 0,01, pre_max 0,02, post_max 0,01, combine 0,02) a 100 fps.
    static let preAverageFrames = 10
    static let postAverageFrames = 1
    static let preMaxFrames = 2
    static let postMaxFrames = 1
    static let combineFrames = 2

    /// `T = 1 + floor(n / 441)`.
    static func frames(forSamples n: Int) -> Int { 1 + n / hop }
}
