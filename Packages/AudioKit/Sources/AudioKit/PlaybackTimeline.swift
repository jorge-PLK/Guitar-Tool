import Foundation
#if canImport(os)
import os
#endif

// MARK: - TimePitch: cuantización de la velocidad y latencia

/// Ajuste del par Varispeed + TimePitch para una velocidad pedida.
///
/// Medido en render offline (P6, Fase 2), 44,1 y 48 kHz: `AVAudioUnitTimePitch` con overlap 8 avanza la
/// entrada en saltos enteros sobre un salto de salida de 256 muestras, así que la velocidad real es
/// `round(rate·256)/256` (0,7 → 0,69922: 10 s darían 14,302 s). Se programa esa velocidad cuantizada en el
/// TimePitch y la diferencia la pone un `AVAudioUnitVarispeed` delante (≤ 0,4 %), cuyo cambio de tono se
/// compensa en el TimePitch. Si la velocidad es representable, el Varispeed va en `bypass`, que deja la
/// señal intacta pero conserva su retardo (activo a rate 1 filtra un impulso; en bypass, no).
struct TimePitchSetting: Equatable, Sendable {
    /// Paso de la velocidad del TimePitch (medido; ver arriba).
    static let rateQuantum = 256.0
    /// Retardo del Varispeed, en muestras (medido con un impulso: 47 a 44,1, 48 y 96 kHz, también a rate 1;
    /// `PlayerHostingTests.testVarispeedDelayIsModelledAtEachSampleRate`).
    static let varispeedDelayFrames = 47.0
    /// Desplazamiento del TimePitch recién reiniciado: `k·(1 − 1/rate)` muestras de salida (ajuste lineal
    /// medido 0,5…2,0 a 48 kHz; residuo ≤ 3 ms, fluctúa ±1,5 ms con la fase de cada evento frente a la trama).
    static let centeringFrames = 437.0

    let rate: Double
    let timePitchRate: Float
    let varispeedRate: Float
    /// Desde que el stem entra al Varispeed hasta que sale del TimePitch, en muestras de salida.
    let latencyFrames: Double

    init(rate: Double) {
        let r = min(max(rate, StudyPlayerConstants.rateRange.lowerBound), StudyPlayerConstants.rateRange.upperBound)
        let q = (r * Self.rateQuantum).rounded() / Self.rateQuantum
        self.rate = r
        timePitchRate = Float(q)
        varispeedRate = q == r ? 1 : Float(r / q)
        latencyFrames = Self.varispeedDelayFrames + Self.centeringFrames * (1 - 1 / r)
    }

    /// Tono del TimePitch para unos cents pedidos, descontando el que sube o baja el Varispeed.
    func timePitchCents(for cents: Double) -> Float {
        Float(cents - 1_200 * log2(Double(varispeedRate)))
    }
}

// MARK: - Plan de programación (bucle sin huecos)

/// Lo que se programa en todos los players a la vez.
enum SchedulePiece: Equatable, Sendable {
    /// Tramo del fichero `[songStart, songStart + frames)`.
    case body(songStart: Int64, frames: Int64)
    /// Fundido cruzado de `2h` muestras: sale `[from, from + 2h)` y entra `[to − h, to + h)`.
    /// La canción sigue en `to + h`. En el bucle `from = b − h`, `to = a`: el corte queda en `b → a`
    /// y la vuelta dura exactamente `b − a`.
    case crossfade(from: Int64, to: Int64)
}

/// Decide qué programar a continuación. Valor puro; lo usa `StemScheduler` en su cola.
struct SchedulePlanner: Equatable, Sendable {
    var length: Int64
    var chunkFrames: Int64
    var halfFade: Int64
    var songPos: Int64
    /// `[a, b)` en muestras.
    var loop: Range<Int64>?

    mutating func next() -> SchedulePiece? {
        if let loop {
            let cut = loop.upperBound - halfFade
            if songPos >= cut {
                let from = songPos
                songPos = loop.lowerBound + halfFade
                return .crossfade(from: from, to: loop.lowerBound)
            }
            let n = min(chunkFrames, cut - songPos)
            defer { songPos += n }
            return .body(songStart: songPos, frames: n)
        }
        guard songPos < length else { return nil }
        let n = min(chunkFrames, length - songPos)
        defer { songPos += n }
        return .body(songStart: songPos, frames: n)
    }

    /// Tramos de canción que ocupa una pieza (el fundido se parte en su centro).
    func spans(of piece: SchedulePiece, at cum: Int64) -> [ScheduledSpan] {
        switch piece {
        case let .body(s, n):
            return [ScheduledSpan(cumStart: cum, songStart: s, length: n)]
        case let .crossfade(from, to):
            return [ScheduledSpan(cumStart: cum, songStart: from, length: halfFade),
                    ScheduledSpan(cumStart: cum + halfFade, songStart: to, length: halfFade)]
        }
    }
}

// MARK: - Reloj de reproducción

/// Tramo programado: `length` muestras de canción desde `songStart`, que entran al Varispeed en la
/// muestra acumulada `cumStart` de la pasada.
struct ScheduledSpan: Equatable, Sendable {
    var cumStart: Int64
    var songStart: Int64
    var length: Int64
    var cumEnd: Int64 { cumStart + length }
}

struct ClickFrame: Equatable, Sendable {
    var songFrame: Double
    var accent: Bool
}

/// Estado compartido entre el hilo de render (fuente del metrónomo), la cola del programador y el
/// actor principal. Una pasada empieza en cada `play`, `seek` o cambio de velocidad.
///
/// Correspondencia (todo en muestras): la salida `y` oye la muestra acumulada
/// `k = (y − runStartFrame − latencyFrames) · rate`, y `k` se traduce a canción con `spans`.
struct ClockState: Sendable {
    var running = false
    /// El primer render tras arrancar fija `runStartFrame` (players y metrónomo empiezan en ese ciclo).
    var pendingStart = false
    var runStartFrame: Double = 0
    var lastRenderStart: Double = 0
    var lastRenderFrames: Double = 0
    var lastRenderHostTime: UInt64 = 0
    var rate: Double = 1
    var latencyFrames: Double = 0
    var startSongFrame: Double = 0
    var spans: [ScheduledSpan] = []
    var clicks: [ClickFrame] = []
    var metronomeOn = false
    var metronomeGain: Float = 1
    /// Reproductor alojado en una sesión de `AudioIO`: muestra de la sesión menos muestra del motor
    /// (`HostedRenderer`). `nil` fuera de una sesión o antes del primer bloque.
    var hostOffset: Double?

    func cumFrame(atOutput y: Double) -> Double {
        (y - runStartFrame - latencyFrames) * rate
    }

    func outputFrame(atCum k: Double) -> Double {
        runStartFrame + latencyFrames + k / rate
    }

    func songFrame(atCum k: Double) -> Double {
        guard let first = spans.first, k > Double(first.cumStart) else {
            return spans.first.map { Double($0.songStart) } ?? startSongFrame
        }
        // Último tramo con cumStart <= k.
        var lo = 0, hi = spans.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if Double(spans[mid].cumStart) <= k { lo = mid } else { hi = mid - 1 }
        }
        let s = spans[lo]
        return Double(s.songStart) + min(k - Double(s.cumStart), Double(s.length))
    }

    func songFrame(atOutput y: Double) -> Double {
        songFrame(atCum: cumFrame(atOutput: y))
    }

    /// Clics cuyo inicio cae en `[from, to)` (muestras de salida), en el orden en que suenan.
    func forEachClick(outputFrom from: Double, to: Double, _ body: (Double, Bool) -> Void) {
        guard !clicks.isEmpty, to > from else { return }
        let k0 = cumFrame(atOutput: from), k1 = cumFrame(atOutput: to)
        for span in spans where Double(span.cumEnd) > k0 && Double(span.cumStart) < k1 {
            let c = Double(span.cumStart), s = Double(span.songStart)
            let lowSong = s + max(0, k0 - c)
            let highSong = s + min(Double(span.length), k1 - c)
            var i = Self.lowerBound(clicks, lowSong)
            while i < clicks.count, clicks[i].songFrame < highSong {
                body(outputFrame(atCum: c + clicks[i].songFrame - s), clicks[i].accent)
                i += 1
            }
        }
    }

    private static func lowerBound(_ a: [ClickFrame], _ x: Double) -> Int {
        var lo = 0, hi = a.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if a[mid].songFrame < x { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// Olvida tramos que ya sonaron hace más de `keepFrames`.
    mutating func prune(keepFrames: Double) {
        guard !pendingStart else { return }
        let k = cumFrame(atOutput: lastRenderStart - keepFrames)
        if let n = spans.firstIndex(where: { Double($0.cumEnd) > k }), n > 0 {
            spans.removeFirst(n)
        }
    }
}

/// Envoltorio con cerrojo del `ClockState`. El hilo de render entra en secciones cortas y sin reservas
/// de memoria (cerrojo injusto de Darwin, con donación de prioridad).
final class PlaybackClock: Sendable {
    private let state = StateLock(initialState: ClockState())

    func read<R>(_ body: (ClockState) -> R) -> R {
        state.withLockUnchecked { body($0) }
    }

    func update<R>(_ body: (inout ClockState) -> R) -> R {
        state.withLockUnchecked { body(&$0) }
    }
}
