import Foundation

/// Salida de las líneas de diagnóstico del núcleo de audio (Parte C de la ronda 7c: una línea por toma con los huecos de
/// la entrada). Sin destino (por omisión, y en el Mac) no escribe nada; el anfitrión de Windows lo apunta a `tfLog`.
public enum AudioKitLog {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var sink: (@Sendable (String) -> Void)?

    public static func setSink(_ newSink: (@Sendable (String) -> Void)?) { lock.withLock { sink = newSink } }

    static func write(_ line: String) {
        let s = lock.withLock { sink }
        s?(line)
    }

    /// Línea de una toma: contadores de E/S de la toma (diferencia entre el principio y el final) y huecos rellenados.
    static func takeLine(start: AudioIODiagnostics?, end: AudioIODiagnostics?, filledGaps: Int, filledFrames: Int,
                         sampleRate: Double) -> String {
        func delta(_ k: KeyPath<AudioIODiagnostics, Int>) -> Int { (end?[keyPath: k] ?? 0) - (start?[keyPath: k] ?? 0) }
        let ms = Double(filledFrames) / sampleRate * 1000
        return "audio.take| captureResets=\(delta(\.captureResets)) inGaps=\(delta(\.inputJumps)) "
            + "droppedCaptureFrames=\(delta(\.droppedCaptureFrames)) realigns=\(delta(\.captureRealigns)) "
            + "filledGaps=\(filledGaps) filledMs=\(String(format: "%.2f", ms))"
    }
}
