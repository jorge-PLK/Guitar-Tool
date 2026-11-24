import Foundation
import NativePlatform

// Lógica de bombeo de `WASAPIAudioIO` sin tipos de Windows (plan, «Corte del paso 7», parte 7.10): lo que hace con cada
// búfer del shim `CWASAPI` (marcas → línea común, desentrelazado, reparto en trozos, contadores). Portátil para que los
// tests la prueben en el Mac con un dispositivo simulado (`WASAPIStreamCoreTests`); en Windows la llama el puente C.

/// Marcas de un búfer de salida, copia de `wasapi_render_info` (CWASAPI.h).
struct WASAPIRenderMarks: Sendable, Equatable {
    /// Fotogramas escritos antes de este búfer, contando el silencio previo al arranque: su `sampleTime`.
    var framesWritten: UInt64
    /// `IAudioClock::GetPosition` en unidades de `clockFrequency`, y su QPC en 100 ns (0 = falló).
    var clockPosition: UInt64
    var clockQPC100ns: UInt64
    var clockFrequency: UInt64
    /// `GetCurrentPadding` antes de escribir (compartido; 0 en exclusivo).
    var paddingFrames: UInt32
}

/// Marcas de un paquete de captura, copia de `wasapi_capture_info` (CWASAPI.h).
struct WASAPICaptureMarks: Sendable, Equatable {
    /// Posición en fotogramas del flujo (la que va a `DuplexClockSync`; con AUTOCONVERTPCM no es `u64DevicePosition`).
    var streamPosition: UInt64
    /// `u64QPCPosition` en 100 ns (0 = sin marca).
    var qpc100ns: UInt64
    /// `AUDCLNT_BUFFERFLAGS_*`.
    var flags: UInt32

    /// Mismos valores que `WASAPI_CAPTURE_*` y `AUDCLNT_BUFFERFLAGS_*`.
    static let discontinuity: UInt32 = 0x1
    static let timestampError: UInt32 = 0x4
}

/// Un flujo dúplex: el estado que el hilo de audio del shim toca en cada llamada. Un solo escritor (ese hilo); los
/// manejadores se ponen con el flujo parado (`prepare`) y se quitan después de `wasapi_stop` (`clear`).
final class WASAPIStreamCore: @unchecked Sendable {
    /// Trozo máximo que se pasa a un manejador (como `CoreAudioIO.maxFrames`); un búfer mayor se reparte en trozos
    /// consecutivos.
    static let defaultChunkFrames = 8_192

    let sampleRate: Double
    let inputChannels: Int
    let outputChannels: Int
    let chunkFrames: Int
    let minimumPoints: Int
    /// Modo compartido: `paddingFrames == 0` al despertar = el motor vació el búfer (cuenta como sobrecarga).
    let shared: Bool
    let counters: IOCounters
    let hostLog: HostTimeLog

    private(set) var sync: DuplexClockSync
    /// Fotogramas de captura descartados porque el offset aún no estaba fijado (arranque, o discontinuidad antes de fijarlo).
    var droppedCaptureFrames: Int { counters.droppedCaptureFrames.load(ordering: .relaxed) }
    /// Discontinuidades de captura después del primer paquete (con el offset fijado, se conserva: `DuplexClockSync`).
    var captureResets: Int { counters.captureResets.load(ordering: .relaxed) }
    /// El primer paquete tras una discontinuidad ya contó su salto en `inGaps`.
    private var jumpCounted = false

    private var render: AudioIORenderHandler?
    private var capture: AudioIOCaptureHandler?
    private let inData: [UnsafeMutablePointer<Float>]
    private let outData: [UnsafeMutablePointer<Float>]
    private let inPointers: UnsafeMutableBufferPointer<UnsafeMutablePointer<Float>>
    private let outPointers: UnsafeMutableBufferPointer<UnsafeMutablePointer<Float>>
    private var expectedOut: UInt64?
    private var expectedIn: Int64?
    private var seenCapture = false
    /// Última marca de salida (muestras de la línea y tics de `HostClock`) para `HostTimeLog`.
    private var lastOutSample = Double.nan
    private var lastOutTicks: UInt64 = 0
    private var lastRenderSampleTime: Int64?

    init(sampleRate: Double, inputChannels: Int, outputChannels: Int, shared: Bool,
         chunkFrames: Int = WASAPIStreamCore.defaultChunkFrames,
         minimumPoints: Int = DuplexClockSync.defaultMinimumPoints,
         counters: IOCounters = IOCounters(), hostLog: HostTimeLog = HostTimeLog()) {
        self.sampleRate = sampleRate
        self.inputChannels = inputChannels
        self.outputChannels = outputChannels
        self.shared = shared
        self.chunkFrames = max(1, chunkFrames)
        self.minimumPoints = minimumPoints
        self.counters = counters
        self.hostLog = hostLog
        sync = DuplexClockSync(sampleRate: sampleRate, minimumPoints: minimumPoints)
        let n = self.chunkFrames
        inData = (0..<inputChannels).map { _ in .allocate(capacity: n) }
        outData = (0..<outputChannels).map { _ in .allocate(capacity: n) }
        inPointers = .allocate(capacity: max(1, inputChannels))
        outPointers = .allocate(capacity: max(1, outputChannels))
        _ = inPointers.initialize(from: inData)
        _ = outPointers.initialize(from: outData)
    }

    deinit {
        inData.forEach { $0.deallocate() }
        outData.forEach { $0.deallocate() }
        inPointers.deallocate()
        outPointers.deallocate()
    }

    /// Con el flujo parado: manejadores nuevos y estado a cero (las posiciones del shim vuelven a 0 en cada arranque).
    func prepare(render: @escaping AudioIORenderHandler, capture: @escaping AudioIOCaptureHandler) {
        self.render = render
        self.capture = capture
        sync = DuplexClockSync(sampleRate: sampleRate, minimumPoints: minimumPoints)
        jumpCounted = false
        expectedOut = nil
        expectedIn = nil
        seenCapture = false
        lastOutSample = .nan
        lastOutTicks = 0
        lastRenderSampleTime = nil
        counters.reset()
        hostLog.reset()
    }

    /// Con el flujo ya parado: suelta los manejadores (y lo que capturen).
    func clear() {
        render = nil
        capture = nil
    }

    /// Tics de `HostClock` de una marca QPC en 100 ns (0 = sin marca).
    static func ticks(qpc100ns: UInt64) -> UInt64 {
        guard qpc100ns > 0 else { return 0 }
        return UInt64((Double(qpc100ns) * 100 / HostTimeLog.timebase).rounded())
    }

    // MARK: Hilo de audio

    /// Búfer de salida: `interleaved` llega a cero y tiene `frames × channels` muestras float32 entrelazadas.
    func render(interleaved: UnsafeMutablePointer<Float>, frames: Int, channels: Int, marks: WASAPIRenderMarks) {
        counters.callbacks.add(1, ordering: .relaxed)
        if marks.clockQPC100ns != 0 {
            sync.addRenderClock(position: marks.clockPosition, frequency: marks.clockFrequency,
                                hostSeconds: DuplexClockSync.seconds(qpc100ns: marks.clockQPC100ns))
            lastOutSample = Double(marks.clockPosition) * sampleRate / Double(max(1, marks.clockFrequency))
            lastOutTicks = Self.ticks(qpc100ns: marks.clockQPC100ns)
        }
        if shared, marks.paddingFrames == 0 { counters.overloads.add(1, ordering: .relaxed) }
        if let e = expectedOut, e != marks.framesWritten {
            counters.gaps.add(1, ordering: .relaxed)
            IOCounters.raise(counters.gapMax, Int(abs(Int64(bitPattern: marks.framesWritten &- e))))
        }
        expectedOut = marks.framesWritten &+ UInt64(frames)
        lastRenderSampleTime = Int64(marks.framesWritten)
        guard frames > 0, let render, !outData.isEmpty else { return }
        let used = min(channels, outputChannels)
        var done = 0
        while done < frames {
            let n = min(chunkFrames, frames - done)
            for p in outData { p.update(repeating: 0, count: n) }
            let line = sync.renderBuffer(framesWritten: Int64(marks.framesWritten) + Int64(done))
            render(AudioIOBuffer(sampleTime: line.sampleTime, frameCount: n, channels: UnsafeBufferPointer(outPointers),
                                 hostSeconds: line.hostSeconds))
            let base = interleaved + done * channels
            for c in 0..<used {
                let src = outData[c]
                for i in 0..<n { base[i * channels + c] = src[i] }
            }
            done += n
        }
    }

    /// Paquete de captura: `frames × channels` muestras float32 entrelazadas.
    func capture(interleaved: UnsafePointer<Float>, frames: Int, channels: Int, marks: WASAPICaptureMarks) {
        if marks.flags & WASAPICaptureMarks.discontinuity != 0, seenCapture {
            // El primer paquete suele traerla (arranque). Después se conserva el offset y el hueco es el real
            // (`DuplexClockSync.captureDiscontinuity`); antes se tiraba 1 s de audio hasta volver a fijarlo.
            sync.captureDiscontinuity()
            counters.captureResets.add(1, ordering: .relaxed)
            counters.inGaps.add(1, ordering: .relaxed)
            jumpCounted = true
        }
        seenCapture = true
        let markOK = marks.flags & WASAPICaptureMarks.timestampError == 0 && marks.qpc100ns != 0
        let hostMark = markOK ? DuplexClockSync.seconds(qpc100ns: marks.qpc100ns) : 0
        guard let sampleTime = sync.addCapturePacket(devicePosition: marks.streamPosition, hostSeconds: hostMark) else {
            counters.droppedCaptureFrames.add(frames, ordering: .relaxed)
            expectedIn = nil
            return
        }
        if let e = expectedIn, e != sampleTime {
            if !jumpCounted { counters.inGaps.add(1, ordering: .relaxed) }
            IOCounters.raise(counters.inGapMax, Int(abs(sampleTime - e)))
        }
        jumpCounted = false
        counters.captureRealigns.store(sync.realigns, ordering: .relaxed)
        expectedIn = sampleTime + Int64(frames)
        if let y = lastRenderSampleTime {
            let skew = Int(y - sampleTime)
            IOCounters.lower(counters.skewMin, skew)
            IOCounters.raise(counters.skewMax, skew)
        }
        hostLog.append(HostTimeLog.Raw(inSample: Double(sampleTime), outSample: lastOutSample,
                                       inHost: markOK ? Self.ticks(qpc100ns: marks.qpc100ns) : 0, outHost: lastOutTicks,
                                       inRate: 1, outRate: 1))
        guard frames > 0, let capture, !inData.isEmpty else { return }
        // Instante de la primera muestra sobre la recta (sin el temblor de la marca suelta); sin recta, la marca.
        var host = sync.captureHostSeconds(devicePosition: marks.streamPosition)
        if host == 0 { host = hostMark }
        let used = min(channels, inputChannels)
        var done = 0
        while done < frames {
            let n = min(chunkFrames, frames - done)
            let base = interleaved + done * channels
            for c in 0..<inputChannels {
                let dst = inData[c]
                if c < used {
                    for i in 0..<n { dst[i] = base[i * channels + c] }
                } else {
                    dst.update(repeating: 0, count: n)
                }
            }
            capture(AudioIOBuffer(sampleTime: sampleTime + Int64(done), frameCount: n,
                                  channels: UnsafeBufferPointer(inPointers),
                                  hostSeconds: host > 0 ? host + Double(done) / sampleRate : 0))
            done += n
        }
    }
}
