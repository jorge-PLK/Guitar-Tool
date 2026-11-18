import Accelerate
import AVFoundation
import Foundation

/// Medida de sonoridad de un fichero o de una señal (mini-spec Fase 7, «Exportación» y «Pruebas»).
public struct LoudnessReport: Sendable, Equatable {
    /// Sonoridad integrada (LUFS, ITU-R BS.1770-4). `nil` si ningún bloque pasa la puerta (silencio o menos de 400 ms).
    public var integratedLUFS: Double?
    /// Pico real en dBTP (sobremuestreo ×4). `-infinity` si la señal es silencio.
    public var truePeakDB: Double
    /// Duración medida en segundos.
    public var duration: Double

    public init(integratedLUFS: Double?, truePeakDB: Double, duration: Double) {
        self.integratedLUFS = integratedLUFS
        self.truePeakDB = truePeakDB
        self.duration = duration
    }
}

/// Medidor de sonoridad integrada (ITU-R BS.1770-4) y pico real, por bloques: se le van dando trozos de la
/// señal con `process(_:)` (mono o estéreo, cualquier frecuencia; sin cargar el fichero entero) y se lee el
/// resultado con `report`.
///
/// - Ponderación K con los coeficientes de `LoudnessMatch.kWeightingCoefficients`.
/// - Bloques de 400 ms con solape del 75 % (salto de 100 ms), puerta absoluta de −70 LUFS y relativa de −10 LU.
///   El último bloque incompleto no cuenta (igual que `ebur128`).
/// - Todos los canales pesan 1,0 (BS.1770: L, R y C); un mono pesa como el canal central, así que suena
///   3 dB por debajo del mismo audio duplicado en estéreo, igual que `ebur128` de ffmpeg.
/// - Pico real: interpolación ×4 con FIR de 48 coeficientes por fase (seno cardinal con ventana de Hann; más largo que los 12 de la norma para no subestimar el pico del ruido de banda ancha).
public struct LoudnessMeter: Sendable {
    // BS.1770-4.
    static let blockSeconds = 0.4
    static let hopSeconds = 0.1
    static let absoluteGateLUFS = -70.0
    static let relativeGateLU = -10.0
    static let hopsPerBlock = 4
    // Pico real: sobremuestreo y largo del FIR (coeficientes por fase).
    static let oversampling = 4
    static let firTaps = 48

    static let firCenter = firTaps / 2 - 1

    /// Coeficientes de las fases 1…3 del interpolador: `phases[p-1][j]` multiplica a `x[n - firCenter + j]` para la
    /// muestra intermedia en `n + p/4`. Normalizados a ganancia 1 en continua.
    static let phases: [[Double]] = (1..<oversampling).map { p in
        let frac = Double(p) / Double(oversampling)
        let half = Double(firTaps / 2)
        var h = (0..<firTaps).map { j -> Double in
            let t = Double(j - firCenter) - frac            // distancia a la muestra intermedia
            let sinc = t == 0 ? 1 : sin(Double.pi * t) / (Double.pi * t)
            let window = abs(t) < half ? 0.5 * (1 + cos(Double.pi * t / half)) : 0
            return sinc * window
        }
        let sum = h.reduce(0, +)
        h = h.map { $0 / sum }
        return h
    }

    public let sampleRate: Double
    public let channelCount: Int

    private let hopFrames: Int
    private let coefficients: [[Double]]
    /// Estado de los dos biquads (DF2 transpuesta) por canal: `[z1a, z2a, z1b, z2b]`.
    private var filterState: [[Double]]
    private var hopEnergy = 0.0
    private var hopFilled = 0
    private var recentHops: [Double] = []
    /// Energía media ponderada de cada bloque de 400 ms (sin convertir a LUFS).
    private var blockEnergies: [Double] = []
    private var history: [[Double]]
    private var peakLinear = 0.0
    private var frames = 0

    public init(sampleRate: Double, channels: Int) {
        self.sampleRate = sampleRate
        self.channelCount = max(1, channels)
        hopFrames = max(1, Int((Self.hopSeconds * sampleRate).rounded()))
        coefficients = LoudnessMatch.kWeightingCoefficients(sampleRate: sampleRate)
        filterState = Array(repeating: [0, 0, 0, 0], count: max(1, channels))
        history = Array(repeating: Array(repeating: 0.0, count: Self.firTaps - 1), count: max(1, channels))
    }

    /// Procesa un trozo; `channels` tiene un array por canal, todos del mismo largo.
    public mutating func process(_ channels: [[Float]]) {
        guard let count = channels.first?.count, count > 0 else { return }
        let nch = min(channels.count, channelCount)
        var offset = 0
        while offset < count {
            let n = min(hopFrames - hopFilled, count - offset)
            for c in 0..<nch {
                var z = filterState[c]
                let s1 = coefficients[0], s2 = coefficients[1]
                var energy = 0.0
                channels[c].withUnsafeBufferPointer { x in
                    for i in offset..<(offset + n) {
                        var v = Double(x[i])
                        // Etapa 1 (estante alto) y 2 (paso alto).
                        var y = s1[0] * v + z[0]
                        z[0] = s1[1] * v - s1[3] * y + z[1]
                        z[1] = s1[2] * v - s1[4] * y
                        v = y
                        y = s2[0] * v + z[2]
                        z[2] = s2[1] * v - s2[3] * y + z[3]
                        z[3] = s2[2] * v - s2[4] * y
                        energy += y * y
                    }
                }
                filterState[c] = z
                hopEnergy += energy
                trackPeak(channel: c, samples: channels[c], range: offset..<(offset + n))
            }
            hopFilled += n
            offset += n
            if hopFilled == hopFrames { closeHop() }
        }
        frames += count
    }

    private mutating func closeHop() {
        recentHops.append(hopEnergy)
        if recentHops.count > Self.hopsPerBlock { recentHops.removeFirst() }
        if recentHops.count == Self.hopsPerBlock {
            blockEnergies.append(recentHops.reduce(0, +) / Double(Self.hopsPerBlock * hopFrames))
        }
        hopEnergy = 0
        hopFilled = 0
    }

    private mutating func trackPeak(channel c: Int, samples: [Float], range: Range<Int>) {
        let taps = Self.firTaps
        var ext = history[c]
        ext.reserveCapacity(ext.count + range.count)
        var peak = peakLinear
        for i in range {
            let v = Double(samples[i])
            peak = max(peak, abs(v))
            ext.append(v)
        }
        // Ventana de `firTaps` muestras que acaba en m, centrada en n = m - firTaps/2 (j = 0 ↔ n - firCenter):
        // las fases dan las muestras entre n y n + 1.
        ext.withUnsafeBufferPointer { e in
            for w in 0..<range.count {
                for phase in Self.phases {
                    var acc = 0.0
                    phase.withUnsafeBufferPointer { vDSP_dotprD($0.baseAddress!, 1, e.baseAddress! + w, 1, &acc, vDSP_Length(taps)) }
                    peak = max(peak, abs(acc))
                }
            }
        }
        history[c] = Array(ext.suffix(taps - 1))
        peakLinear = peak
    }

    /// Resultado hasta ahora. Para el pico real, rellena con ceros la cola del interpolador (no altera el estado).
    public var report: LoudnessReport {
        var copy = self
        let zeros = [Float](repeating: 0, count: Self.firTaps / 2)
        for c in 0..<channelCount { copy.trackPeak(channel: c, samples: zeros, range: 0..<zeros.count) }
        return LoudnessReport(integratedLUFS: copy.gatedLoudness(),
                              truePeakDB: copy.peakLinear > 0 ? 20 * log10(copy.peakLinear) : -.infinity,
                              duration: Double(frames) / sampleRate)
    }

    private func gatedLoudness() -> Double? {
        func lufs(_ e: Double) -> Double { -0.691 + 10 * log10(max(e, 1e-30)) }
        let absolute = blockEnergies.filter { lufs($0) > Self.absoluteGateLUFS }
        guard !absolute.isEmpty else { return nil }
        let gate = lufs(absolute.reduce(0, +) / Double(absolute.count)) + Self.relativeGateLU
        let relative = absolute.filter { lufs($0) > gate }
        guard !relative.isEmpty else { return nil }
        return lufs(relative.reduce(0, +) / Double(relative.count))
    }

    // MARK: Atajos

    /// Mide canales ya en memoria (señales cortas).
    public static func measure(_ channels: [[Float]], sampleRate: Double) -> LoudnessReport {
        var meter = LoudnessMeter(sampleRate: sampleRate, channels: channels.count)
        meter.process(channels)
        return meter.report
    }

    /// Mide un fichero por bloques de 64 Ki muestras. `progress` va de 0 a 1; si `isCancelled` devuelve
    /// verdadero se lanza `CancellationError`.
    public static func measure(url: URL, progress: (Double) -> Void = { _ in },
                               isCancelled: () -> Bool = { false }) throws -> LoudnessReport {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat
        let nch = Int(format.channelCount)
        var meter = LoudnessMeter(sampleRate: format.sampleRate, channels: nch)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 65_536)!
        let total = max(1, Int(file.length))
        while file.framePosition < file.length {
            if isCancelled() { throw CancellationError() }
            buf.frameLength = 0
            try file.read(into: buf, frameCount: 65_536)
            let n = Int(buf.frameLength)
            if n == 0 { break }
            let chunk = (0..<nch).map { Array(UnsafeBufferPointer(start: buf.floatChannelData![$0], count: n)) }
            meter.process(chunk)
            progress(min(1, Double(file.framePosition) / Double(total)))
        }
        return meter.report
    }
}
