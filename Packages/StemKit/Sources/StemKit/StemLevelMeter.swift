import Foundation
import NativeAudioFile

/// Nivel de un stem en dBFS (sobre todos los canales).
public struct StemLevel: Sendable, Equatable {
    public var rmsDB: Double
    public var peakDB: Double
    public init(rmsDB: Double, peakDB: Double) {
        self.rmsDB = rmsDB
        self.peakDB = peakDB
    }
}

/// Medida de nivel por bloques y regla de «stem vacío» (mini-spec Fase 2, «Stems vacíos»).
public enum StemLevelMeter {
    /// Mini-spec Fase 2, «Stems vacíos»: vacío si RMS < −60 dBFS …
    public static let emptyRMSThresholdDB = -60.0
    /// … y pico < −30 dBFS.
    public static let emptyPeakThresholdDB = -30.0
    /// Suelo para el silencio digital exacto.
    public static let floorDB = -200.0
    static let blockFrames = 1 << 16

    /// Lee el fichero por bloques (sin cargarlo entero) y devuelve RMS y pico en dBFS de todos los canales.
    public static func measure(url: URL) throws -> StemLevel {
        let file = try AudioFileReader(url: url)
        let channels = file.channelCount
        let data = (0..<channels).map { _ in UnsafeMutablePointer<Float>.allocate(capacity: blockFrames) }
        defer { data.forEach { $0.deallocate() } }
        var sumSquares = 0.0
        var peak: Float = 0
        var count = 0
        while file.framePosition < file.frameCount {
            let n = try file.read(into: data, maxFrames: blockFrames)
            if n == 0 { break }
            for c in 0..<channels {
                let p = data[c]
                var blockSum: Float = 0
                var blockPeak: Float = 0
                for i in 0..<n {
                    let v = p[i]
                    blockSum += v * v
                    blockPeak = max(blockPeak, abs(v))
                }
                sumSquares += Double(blockSum)
                peak = max(peak, blockPeak)
            }
            count += n * channels
        }
        guard count > 0 else { return StemLevel(rmsDB: floorDB, peakDB: floorDB) }
        return StemLevel(rmsDB: db(sqrt(sumSquares / Double(count))), peakDB: db(Double(peak)))
    }

    /// Regla de la spec: RMS < −60 dBFS y pico < −30 dBFS.
    public static func isEmpty(_ level: StemLevel) -> Bool {
        level.rmsDB < emptyRMSThresholdDB && level.peakDB < emptyPeakThresholdDB
    }

    public static func isEmpty(url: URL) throws -> Bool { isEmpty(try measure(url: url)) }

    private static func db(_ linear: Double) -> Double { linear > 0 ? max(floorDB, 20 * log10(linear)) : floorDB }
}
