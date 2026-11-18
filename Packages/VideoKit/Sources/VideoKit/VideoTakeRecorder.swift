import Foundation

/// Lo que pasó con un fotograma en una toma.
public struct FrameRecord: Sendable, Equatable {
    public var sequence: Int
    public var hostSeconds: Double
    public var arrivalHostSeconds: Double
    /// Tiempo del tema calculado (PTS sin desfase); `nil` antes del ancla.
    public var songTime: Double?
    public var written: Bool
}

/// Regularidad de las marcas de una cámara (para `tf-video sync` y el informe de la toma).
public struct FrameTiming: Sendable, Equatable {
    /// Fotogramas que faltan según los huecos entre marcas (intervalo redondeado a periodos nominales).
    public var droppedFromGaps: Int
    /// fps medidos con las marcas (recta por mínimos cuadrados contra el número de fotograma).
    public var measuredFPS: Double
    /// Reloj de fotogramas frente al nominal, en ppm (positivo: más rápido).
    public var cameraClockPPM: Double
    /// Residuo de las marcas frente a esa recta: máximo absoluto y RMS, en segundos.
    public var jitterMax: Double
    public var jitterRMS: Double

    /// `nil` con menos de tres marcas.
    public static func analyze(hostTimes t: [Double], nominalFPS: Double) -> FrameTiming? {
        guard t.count >= 3, nominalFPS > 0 else { return nil }
        let period = 1 / nominalFPS
        var k = [0.0]
        for i in 1..<t.count { k.append(k[i - 1] + max(1, ((t[i] - t[i - 1]) / period).rounded())) }
        // Recta t = a + p·k con Welford sobre valores relativos al primero.
        var n = 0.0, mk = 0.0, mt = 0.0, ckk = 0.0, ckt = 0.0
        for (ki, ti) in zip(k, t) {
            let x = ki, y = ti - t[0]
            n += 1
            let dk = x - mk
            mk += dk / n
            let dt = y - mt
            mt += dt / n
            ckk += dk * (x - mk)
            ckt += dk * (y - mt)
        }
        let p = ckt / ckk
        var worst = 0.0, sq = 0.0
        for (ki, ti) in zip(k, t) {
            let r = (ti - t[0]) - (mt + (ki - mk) * p)
            worst = max(worst, abs(r))
            sq += r * r
        }
        return FrameTiming(droppedFromGaps: Int(k.last!) - (t.count - 1), measuredFPS: 1 / p,
                           cameraClockPPM: (period / p - 1) * 1e6, jitterMax: worst, jitterRMS: (sq / n).squareRoot())
    }
}

/// Informe de sincronía de una toma (mini-spec Fase 6; lo da `tf-video sync` y `record`).
public struct VideoSyncReport: Sendable, Equatable {
    public var framesReceived: Int
    public var framesWritten: Int
    /// Sin tiempo del tema: antes del ancla o sin reloj del audio todavía.
    public var framesBeforeAnchor: Int
    /// Tras un cambio de ancla (seek o parada): la toma acaba ahí, como la de audio.
    public var framesAfterCut: Int
    /// Rechazados por el destino (PTS que no avanza, codificador ocupado…).
    public var framesRejected: Int
    public var timing: FrameTiming?
    /// Deriva del reloj del audio frente al de host (del ajuste del `HostTimeMap`).
    public var audioClockPPM: Double?
    /// Llegada − marca: mínimo, mediana y máximo, en segundos.
    public var arrivalLag: (min: Double, median: Double, max: Double)?
    public var firstSongTime: Double?
    public var lastSongTime: Double?

    /// Deriva relativa entre el reloj de fotogramas de la cámara y el del audio, en ppm.
    public var cameraMinusAudioPPM: Double? {
        guard let c = timing?.cameraClockPPM, let a = audioClockPPM else { return nil }
        return c - a
    }

    public static func == (a: VideoSyncReport, b: VideoSyncReport) -> Bool {
        a.framesReceived == b.framesReceived && a.framesWritten == b.framesWritten && a.framesBeforeAnchor == b.framesBeforeAnchor
            && a.framesAfterCut == b.framesAfterCut && a.framesRejected == b.framesRejected && a.timing == b.timing
            && a.audioClockPPM == b.audioClockPPM && a.arrivalLag?.min == b.arrivalLag?.min
            && a.arrivalLag?.median == b.arrivalLag?.median && a.arrivalLag?.max == b.arrivalLag?.max
            && a.firstSongTime == b.firstSongTime && a.lastSongTime == b.lastSongTime
    }
}

/// Une cámara, reloj del audio y escritor en una toma (mini-spec Fase 6, «Cámara y sincronía»): cada fotograma se
/// sitúa en el tema con el `HostTimeMap` del momento y va al destino con PTS = tiempo del tema (sin desfase).
///
/// Quien graba (la app, `tf-video`) alimenta el mapa cada poco con `updateMap`: las marcas nuevas de
/// `AudioSession.outputHostClock(after:)` y el `playbackAnchor` de la sesión (en cuanto exista). Los fotogramas que
/// llegan sin ancla se descartan: conviene poner el ancla en cuanto el reproductor la publique (unos ms tras `play`).
/// Si el ancla cambia a mitad (seek o parada), la toma acaba en ese punto, como la de audio en `AudioSession`.
/// `handle` es seguro desde la cola de la cámara.
public final class VideoTakeRecorder: @unchecked Sendable {
    public let sink: any VideoFrameSink
    public let nominalFPS: Double
    private let lock = NSLock()
    private var mapValue: HostTimeMap
    private var records: [FrameRecord] = []
    private var beforeAnchor = 0
    private var afterCut = 0
    private var rejected = 0

    public init(sink: any VideoFrameSink, sampleRate: Double, nominalFPS: Double) {
        self.sink = sink
        self.nominalFPS = nominalFPS
        mapValue = HostTimeMap(sampleRate: sampleRate)
    }

    public var map: HostTimeMap { lock.withLock { mapValue } }

    public func updateMap(_ body: (inout HostTimeMap) -> Void) { lock.withLock { body(&mapValue) } }

    /// Manejador de fotogramas de la cámara.
    public func handle(_ frame: CameraFrame) {
        let (song, cut) = lock.withLock { () -> (Double?, Bool) in
            guard let y = mapValue.outputSample(atHostSeconds: frame.hostSeconds),
                  let i = mapValue.anchorIndex(atOutputSample: y) else { return (nil, false) }
            return (mapValue.anchors[i].songTime(atOutputSample: y), i > 0)
        }
        var ok = false
        if let song, !cut { ok = sink.append(frame, songTime: song) }
        lock.withLock {
            if song == nil { beforeAnchor += 1 } else if cut { afterCut += 1 } else if !ok { rejected += 1 }
            records.append(FrameRecord(sequence: frame.sequence, hostSeconds: frame.hostSeconds,
                                       arrivalHostSeconds: frame.arrivalHostSeconds, songTime: cut ? nil : song, written: ok))
        }
    }

    public var frames: [FrameRecord] { lock.withLock { records } }

    public func report() -> VideoSyncReport {
        let (r, m, b, c, j) = lock.withLock { (records, mapValue, beforeAnchor, afterCut, rejected) }
        let lags = r.map { $0.arrivalHostSeconds - $0.hostSeconds }.sorted()
        let written = r.filter(\.written)
        return VideoSyncReport(
            framesReceived: r.count, framesWritten: written.count, framesBeforeAnchor: b, framesAfterCut: c, framesRejected: j,
            timing: FrameTiming.analyze(hostTimes: r.map(\.hostSeconds), nominalFPS: nominalFPS),
            audioClockPPM: m.audioClockPPM,
            arrivalLag: lags.isEmpty ? nil : (lags.first!, lags[lags.count / 2], lags.last!),
            firstSongTime: written.first?.songTime, lastSongTime: written.last?.songTime)
    }
}

/// Destino que solo apunta (tests y `tf-video sync`).
public final class FrameLogSink: VideoFrameSink, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [(sequence: Int, songTime: Double)] = []

    public init() {}

    public func append(_ frame: CameraFrame, songTime: Double) -> Bool {
        lock.withLock {
            guard songTime >= 0 else { return false }
            if let last = log.last, songTime <= last.songTime { return false }
            log.append((frame.sequence, songTime))
            return true
        }
    }

    public var entries: [(sequence: Int, songTime: Double)] { lock.withLock { log } }
}
