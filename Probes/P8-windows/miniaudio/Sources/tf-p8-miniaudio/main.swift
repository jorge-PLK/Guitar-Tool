// Prueba c del paso 4 (Fase 7c): miniaudio en Windows ARM64/x64.
// En la VM puede no haber dispositivos: eso no es fallo; sí lo es que no compile, no enlace o no inicialice.
import Foundation
import MiniAudioShim

#if arch(arm64)
let arch = "arm64"
#elseif arch(x86_64)
let arch = "x86_64"
#else
let arch = "?"
#endif

nonisolated(unsafe) var failures = 0
func report(_ ok: Bool, _ name: String, _ detail: String) {
    print("\(ok ? "OK" : "FALLO") \(name): \(detail)")
    fflush(stdout)
    if !ok { failures += 1 }
}

/// Marcas de QPC de cada periodo, preasignadas (el hilo de audio no reserva memoria).
final class PeriodLog {
    var stamps = [Int64](repeating: 0, count: 4096)
    var frames = [UInt32](repeating: 0, count: 4096)
    var count = 0
}
let onPeriod: tfma_period_cb = { user, frames, qpc in
    let log = Unmanaged<PeriodLog>.fromOpaque(user!).takeUnretainedValue()
    if log.count < log.stamps.count {
        log.stamps[log.count] = qpc
        log.frames[log.count] = frames
    }
    log.count += 1
}
func intervalsMs(_ log: PeriodLog) -> [Double] {
    let n = min(log.count, log.stamps.count)
    let f = Double(tfma_qpc_frequency())
    return n < 2 ? [] : (1..<n).map { Double(log.stamps[$0] - log.stamps[$0 - 1]) / f * 1e3 }
}

print("tf-p8-miniaudio arch=\(arch)")

// 1) Contexto WASAPI y dispositivos.
let nDevices = tfma_wasapi_report()
report(nDevices >= 0, "contexto WASAPI", nDevices >= 0 ? "\(nDevices) dispositivos" : "error \(nDevices)")

// 2) Hilo de audio de miniaudio llamando a Swift (backend nulo, 48 kHz, periodo 480 = 10 ms, 2 s).
do {
    let log = PeriodLog()
    let p = Unmanaged.passRetained(log).toOpaque()
    let r = tfma_null_playback(48_000, 480, 2_000, onPeriod, p)
    Unmanaged<PeriodLog>.fromOpaque(p).release()
    let d = intervalsMs(log).dropFirst(2)   // los dos primeros incluyen el arranque
    let mean = d.isEmpty ? .nan : d.reduce(0, +) / Double(d.count)
    let worst = d.map { abs($0 - mean) }.max() ?? .nan
    let framesSeen = Set(log.frames.prefix(min(log.count, 4096)))
    report(r == 0 && (180...220).contains(log.count) && abs(mean - 10) < 1, "backend nulo → callback Swift",
           String(format: "r=%d, %d periodos en 2 s (esperado ~200), intervalo medio %.3f ms, peor desviación %.2f ms, tamaños %@",
                  r, log.count, mean, worst, framesSeen.sorted().map(String.init).joined(separator: ",")))
}

// 3) Dúplex WASAPI por defecto (128 muestras); sin dispositivos falla y se anota, no es fallo.
do {
    let log = PeriodLog()
    let p = Unmanaged.passRetained(log).toOpaque()
    let r = tfma_wasapi_duplex(128, 1_000, onPeriod, p)
    Unmanaged<PeriodLog>.fromOpaque(p).release()
    let d = intervalsMs(log).dropFirst(2)
    let mean = d.isEmpty ? Double.nan : d.reduce(0, +) / Double(d.count)
    print(String(format: "AVISO dúplex WASAPI: r=%d, %d periodos en 1 s, intervalo medio %.3f ms", r, log.count, mean))
}

// 4) Decodificadores frente a AVAudioFile (referencias medidas en el Mac con AudioImporter/AVAudioFile).
struct Ref { let file: String; let frames: UInt64; let sr: UInt32; let ch: UInt32; let rms: Double; let first: Int64 }
let fixtures = "C:\\tf\\Packages\\AudioKit\\Tests\\AudioKitTests\\Fixtures\\"
let refs = [
    Ref(file: "sine1k_mono_48k_24bit.wav", frames: 72_000, sr: 48_000, ch: 1, rms: 0.088368, first: 1),
    Ref(file: "sine1k_stereo_44k.mp3", frames: 66_150, sr: 44_100, ch: 2, rms: 0.059359, first: 1),
    Ref(file: "sine1k_stereo_96k.flac", frames: 144_000, sr: 96_000, ch: 2, rms: 0.062486, first: 2),
    Ref(file: "Artista Prueba - Tema Prueba.wav", frames: 8_820, sr: 44_100, ch: 1, rms: 0.088369, first: 1),
]
/// RMS relativo admitido frente a AVAudioFile (las referencias van con 6 decimales).
let rmsTolerance = 1e-3
for ref in refs {
    var frames: UInt64 = 0, sr: UInt32 = 0, ch: UInt32 = 0, rms = 0.0, peak = 0.0, first: Int64 = 0
    let r = tfma_decode(fixtures + ref.file, &frames, &sr, &ch, &rms, &peak, &first)
    let dRms = abs(rms - ref.rms) / ref.rms
    let ok = r == 0 && frames == ref.frames && sr == ref.sr && ch == ref.ch && dRms <= rmsTolerance && first == ref.first
    report(ok, "decodificar \(ref.file)",
           String(format: "r=%d, frames %llu (AVAudioFile %llu, Δ %lld), %u Hz, %u ch, RMS Δrel %.1e, primera muestra > 0,01 en %lld (AVAudioFile %lld)",
                  r, frames, ref.frames, Int64(frames) - Int64(ref.frames), sr, ch, dRms, first, ref.first))
}

// 5) Ruta no ASCII ida y vuelta (nombres de temas con tildes): escribir WAV y volverlo a leer.
do {
    let path = "C:\\ToneForge\\p8 canción ñ €.wav"
    let w = tfma_write_wav(path, 48_000, 24_000)
    var frames: UInt64 = 0, sr: UInt32 = 0, ch: UInt32 = 0, rms = 0.0, peak = 0.0, first: Int64 = 0
    let r = tfma_decode(path, &frames, &sr, &ch, &rms, &peak, &first)
    let expected = 0.125 / 2.0.squareRoot()
    report(w == 0 && r == 0 && frames == 24_000 && abs(rms - expected) < 1e-4 && FileManager.default.fileExists(atPath: path),
           "WAV ruta no ASCII", String(format: "escribir %d, leer %d, frames %llu, RMS %.6f (esperado %.6f), existe para Foundation %@",
                                       w, r, frames, rms, expected, FileManager.default.fileExists(atPath: path) ? "sí" : "no"))
}

print("fallos \(failures)")
exit(failures == 0 ? 0 : 1)
