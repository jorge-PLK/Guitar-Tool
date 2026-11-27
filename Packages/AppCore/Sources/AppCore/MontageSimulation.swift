import AudioKit
import Foundation
import VideoKit

// Versión simulada de las costuras de Montaje (W2-M1): para los tests y para desarrollar la página sin compositor, sin
// lector de tomas y sin pose. La mezcla del audio no se simula: `MontageMixer` es portátil y los tests lo usan de verdad.

/// Cuenta lo que han hecho los servicios simulados (los tests lo leen).
final class SimulatedMontageCounters: @unchecked Sendable {
    private let lock = NSLock()
    private var _composers = 0, _analyses = 0, _exports = 0, _takeFrames = 0
    private var _exportStarted = false
    var composers: Int { lock.withLock { _composers } }
    var analyses: Int { lock.withLock { _analyses } }
    var exports: Int { lock.withLock { _exports } }
    var takeFrames: Int { lock.withLock { _takeFrames } }
    /// La exportación ya empezó a codificar (el test cancela a partir de aquí).
    var exportStarted: Bool { lock.withLock { _exportStarted } }
    func composer() { lock.withLock { _composers += 1 } }
    func analysis() { lock.withLock { _analyses += 1 } }
    func export() { lock.withLock { _exports += 1 } }
    func takeFrame() { lock.withLock { _takeFrames += 1 } }
    func started() { lock.withLock { _exportStarted = true } }
}

/// Compositor que tarda `frameMillis` por fotograma y devuelve uno liso pequeño; anota los instantes pedidos.
final class SimulatedMontageComposer: MontageComposing, @unchecked Sendable {
    let duration: Double
    /// Inicio del primer tramo en tiempo del tema (tiempo de vídeo 0).
    let origin: Double
    let frameMillis: Double
    private let size: (width: Int, height: Int)
    private let lock = NSLock()
    private var _requested: [Double] = []
    var requested: [Double] { lock.withLock { _requested } }

    init(duration: Double, origin: Double, frameMillis: Double, size: (width: Int, height: Int) = (32, 18)) {
        self.duration = duration
        self.origin = origin
        self.frameMillis = frameMillis
        self.size = size
    }

    func songTime(videoTime: Double) -> Double { origin + videoTime }
    func videoTime(songTime: Double) -> Double { max(0, songTime - origin) }

    func frame(atVideoTime t: Double) throws -> MontageFramePixels {
        lock.withLock { _requested.append(t) }
        if frameMillis > 0 { Thread.sleep(forTimeInterval: frameMillis / 1000) }
        let shade = UInt8(truncatingIfNeeded: Int(t * 10))
        guard let p = MontageFrameImage.solid(width: size.width, height: size.height, b: shade, g: 0x40, r: 0x80) else {
            throw MontageError.composition("sin búfer")
        }
        return p
    }
}

extension MontageServices {
    /// Servicios simulados: compositor con `frameMillis` por fotograma, análisis con progreso, fotograma liso de toma y
    /// exportación de `exportSteps` pasos de `exportStepMillis` que respeta la cancelación. La mezcla es la real.
    static func simulated(frameMillis: Double = 0, analysisMillis: Double = 0, exportSteps: Int = 10, exportStepMillis: Double = 10,
                          counters: SimulatedMontageCounters = SimulatedMontageCounters(),
                          composerBox: SimulatedComposerBox? = nil) -> MontageServices {
        MontageServices(
            makeComposer: { plan, maxDimension in
                counters.composer()
                let duration = plan.segments.reduce(0) { $0 + ($1.end - $1.start) }
                let size = MontageBuilder.renderSize(canvas: plan.canvas, maxDimension: min(maxDimension, 64))
                let c = SimulatedMontageComposer(duration: duration, origin: plan.segments.first?.start ?? 0, frameMillis: frameMillis,
                                                 size: (Int(size.width), Int(size.height)))
                composerBox?.set(c)
                return c
            },
            takeFrame: { _, _, _ in
                counters.takeFrame()
                return MontageFrameImage.solid(width: 64, height: 36, b: 0x30, g: 0x90, r: 0xC0)
            },
            analyze: { video, progress in
                counters.analysis()
                for i in 1...4 {
                    try Task.checkCancellation()
                    if analysisMillis > 0 { try await Task.sleep(for: .milliseconds(analysisMillis)) }
                    progress(Double(i) / 4)
                }
                return FramingAnalysis(fingerprint: GuitarFramer.fingerprint(video: video), frameWidth: 1920, frameHeight: 1080,
                                       samples: 40, detected: 38, fixed: FramingBox(x: 0.3, y: 0.2, width: 0.4, height: 0.5),
                                       track: (0..<4).map { FramingKey(time: Double($0) * 4, box: FramingBox(x: 0.25 + 0.03 * Double($0), y: 0.2, width: 0.4, height: 0.5)) })
            },
            mix: { job, progress in try await MontageMixer.mix(job, progress: progress) },
            export: { _, _, settings, url, progress in
                counters.export()
                counters.started()
                for i in 1...exportSteps {
                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(exportStepMillis))
                    progress(Double(i) / Double(exportSteps))
                }
                try Data("simulado".utf8).write(to: url)
                return MontageExportOutcome(codec: settings.codec.rawValue)
            })
    }
}

/// Guarda el último compositor simulado creado (los tests miran los instantes pedidos).
final class SimulatedComposerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _composer: SimulatedMontageComposer?
    var composer: SimulatedMontageComposer? { lock.withLock { _composer } }
    func set(_ c: SimulatedMontageComposer) { lock.withLock { _composer = c } }
}
