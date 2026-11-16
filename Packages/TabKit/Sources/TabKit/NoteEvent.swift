/// Una nota transcrita: lo que devuelve `basic_pitch.inference.predict` en `note_events`, sin pitch bends.
public struct NoteEvent: Codable, Sendable, Hashable {
    /// Inicio y fin en segundos de canción (fin exclusivo).
    public var start: Double
    public var end: Double
    /// Nota MIDI (21 = A0 … 108 = C8).
    public var pitch: Int
    /// Media de la activación de frame durante la nota, 0…1.
    public var amplitude: Float

    public init(start: Double, end: Double, pitch: Int, amplitude: Float) {
        self.start = start
        self.end = end
        self.pitch = pitch
        self.amplitude = amplitude
    }

    public var duration: Double { end - start }
}
