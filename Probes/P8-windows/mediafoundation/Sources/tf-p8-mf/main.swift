// Prueba d del paso 4 (Fase 7c): Media Foundation desde Swift a través de un shim C.
// Deja C:\ToneForge\p8-mf-<arch>.mp4 (H.264 + AAC, 2 s) para traerlo al Mac y mirarlo con ffmpeg.
import Foundation
import MFShim

#if arch(arm64)
let arch = "arm64"
#elseif arch(x86_64)
let arch = "x64"
#else
let arch = "?"
#endif

nonisolated(unsafe) var failures = 0
func hex(_ hr: Int32) -> String { String(format: "0x%08X", UInt32(bitPattern: hr)) }

print("tf-p8-mf arch=\(arch)")

// H.264 + AAC, 2 s (lo que haría MontageExporter/VideoTakeWriter en Windows).
do {
    let path = "C:\\ToneForge\\p8-mf-\(arch).mp4"
    try? FileManager.default.removeItem(atPath: path)
    var step: UnsafePointer<CChar>?
    let t0 = Date()
    let hr = tfmf_write(path, 2, 0, 1, &step)
    let ms = Date().timeIntervalSince(t0) * 1e3
    let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
    let ok = hr == 0 && size > 10_000
    print("\(ok ? "OK" : "FALLO") H.264+AAC MP4: hr \(hex(hr)) en «\(String(cString: step!))», \(size) bytes, \(String(format: "%.0f", ms)) ms")
    if !ok { failures += 1 }
}

// HEVC solo vídeo, 1 s: en Windows el codificador HEVC depende del hardware o de la extensión de la Store.
do {
    let path = "C:\\ToneForge\\p8-mf-hevc-\(arch).mp4"
    try? FileManager.default.removeItem(atPath: path)
    var step: UnsafePointer<CChar>?
    let hr = tfmf_write(path, 1, 1, 0, &step)
    let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
    print("AVISO HEVC: hr \(hex(hr)) en «\(String(cString: step!))», \(size) bytes")
}

print("fallos \(failures)")
exit(failures == 0 ? 0 : 1)
