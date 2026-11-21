import Foundation

/// Plan de tramos de imagen de una toma (mini-spec Fase 6, «Punch-in»), puro y portable (plan, «Fase 7c», paso 7, parte
/// 7.9): lo usan `TakePreview` y `LoadedTakeVideo` en el Mac (AVFoundation) y en Windows (Media Foundation + Direct2D).
///
/// Base en todo el tramo de la toma, cada punch encima en el suyo (el último manda) y cada tramo recortado a lo que su
/// fichero tiene. Tiempo de los tramos: 0 = `songStart`; el fotograma con PTS `p` (tiempo del tema) se ve en
/// `p − desfase`.
public enum TakePreviewPlan {
    /// Un punch tal como lo ve el plan: su tramo (tiempo del tema), lo que su fichero tiene (PTS; `nil`: sin imagen) y
    /// su desfase.
    public struct Punch: Sendable, Equatable {
        public var start: Double
        public var end: Double
        public var available: ClosedRange<Double>?
        public var offset: Double

        public init(start: Double, end: Double, available: ClosedRange<Double>?, offset: Double) {
            self.start = start
            self.end = end
            self.available = available
            self.offset = offset
        }
    }

    /// Tramos para una toma de `duration` s desde `songStart`, con la base disponible en `base` (PTS) y desfase
    /// `baseOffset`.
    public static func pieces(songStart: Double, duration: Double, base: ClosedRange<Double>?, baseOffset: Double,
                              punches: [Punch]) -> [PreviewPiece] {
        // Intervalos en tiempo del tema con su fuente (-1 = base).
        var spans: [(a: Double, b: Double, src: Int)] = [(songStart, songStart + duration, -1)]
        for (i, p) in punches.enumerated() {
            let a = max(p.start, songStart), b = min(p.end, songStart + duration)
            guard b > a else { continue }
            var next: [(a: Double, b: Double, src: Int)] = []
            for s in spans {
                if s.b <= a || s.a >= b { next.append(s); continue }
                if s.a < a { next.append((s.a, a, s.src)) }
                if s.b > b { next.append((b, s.b, s.src)) }
            }
            next.append((a, b, i))
            spans = next.sorted { $0.a < $1.a }
        }
        var out: [PreviewPiece] = []
        for s in spans {
            let available = s.src < 0 ? base : punches[s.src].available
            let offset = s.src < 0 ? baseOffset : punches[s.src].offset
            guard let available else { continue }
            // Fichero: [a + o, b + o) recortado a donde hay imagen.
            let lo = max(s.a + offset, available.lowerBound), hi = min(s.b + offset, available.upperBound)
            guard hi > lo else { continue }
            out.append(PreviewPiece(start: lo - offset - songStart, end: hi - offset - songStart,
                                    source: s.src < 0 ? .base : .punch(s.src), sourceStart: lo))
        }
        return out
    }
}
