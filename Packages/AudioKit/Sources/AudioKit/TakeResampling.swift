#if canImport(AVFoundation)
import AVFoundation
#else
import NativeAudioFile
#endif
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation

/// Tomas a otra frecuencia que la del proyecto: las grabadas antes de reconvertirlo (`Library.migrate`
/// reconvierte tema y stems, no las tomas). Decisión de Jorge (17/11/2026): no se reescriben en disco; se
/// remuestrean **al cargar**, con el mismo conversor que el tema y los stems (`AudioImporter`: AVAudioConverter,
/// calidad máxima, algoritmo Mastering, en el Mac; r8brain en Windows).
///
/// La muestra 0 del fichero convertido es el mismo instante que la del original, y `songStart` va en
/// segundos: la toma cae donde caía. El único redondeo nuevo es el de `songStart` a muestras de destino
/// (≤ media muestra, ≈ 11 µs a 44,1 kHz), el mismo que ya hace quien coloca una toma (`StudyPlayer`, montaje).
public enum TakeResampling {
    /// Frecuencia del fichero.
    public static func sampleRate(of url: URL) throws -> Double {
        try AudioSamples.sampleRate(of: url)
    }

    /// `url` si ya está a `sampleRate` (mismo camino que siempre, sin copia); si no, una copia remuestreada en
    /// una caché temporal (clave: ruta, tamaño, fecha y frecuencia), con los mismos canales, que se reutiliza.
    public static func readable(_ url: URL, at sampleRate: Double) throws -> URL {
        let rate = try self.sampleRate(of: url)
        if abs(rate - sampleRate) < 0.5 { return url }
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("ToneForge-resampled-takes", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let attrs = try fm.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let date = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let key = "\(url.standardizedFileURL.path)|\(size)|\(date)|\(sampleRate)"
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        let cached = dir.appendingPathComponent("\(hash.prefix(32)).wav")
        if fm.fileExists(atPath: cached.path) { return cached }
        let channels = try convert(url, to: sampleRate, scratch: dir)
        let tmp = dir.appendingPathComponent(".\(UUID().uuidString).wav")
        try TakeFile.write(channels, sampleRate: sampleRate, to: tmp)
        if fm.fileExists(atPath: cached.path) { try? fm.removeItem(at: tmp); return cached }
        try fm.moveItem(at: tmp, to: cached)
        return cached
    }

    /// Canales de la toma a `sampleRate`. Si ya está a esa frecuencia, `TakeFile.read` tal cual.
    public static func read(_ url: URL, at sampleRate: Double) throws -> [[Float]] {
        let rate = try self.sampleRate(of: url)
        if abs(rate - sampleRate) < 0.5 { return try TakeFile.read(url) }
        let dir = FileManager.default.temporaryDirectory
        return try convert(url, to: sampleRate, scratch: dir)
    }

    /// El conversor entrega estéreo (mono duplicado): una toma mono vuelve a mono.
    private static func convert(_ url: URL, to sampleRate: Double, scratch: URL) throws -> [[Float]] {
        #if canImport(AVFoundation)
        let channels = Int(try AVAudioFile(forReading: url).processingFormat.channelCount)
        #else
        let channels = try AudioFileReader(url: url).channelCount
        #endif
        let tmp = scratch.appendingPathComponent(".\(UUID().uuidString).conv.wav")
        defer { try? FileManager.default.removeItem(at: tmp) }
        _ = try AudioImporter.convert(url, to: tmp, sampleRate: sampleRate, progress: { _ in })
        let out = try TakeFile.read(tmp)
        return Array(out.prefix(max(1, channels)))
    }
}
