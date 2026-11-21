import Foundation

/// Paso entre el layout de StemKit y el del ONNX de separación de Windows (parte 7.3: interfaz del ONNX publicado,
/// `Probes/P8-windows/ort-models/bs_chunk.py`).
///
/// - StemKit: `spec` `[1, 2·bins, T, 2]` con fila `2·f + canal` y (re, im) intercalado; el modelo devuelve una
///   máscara que `ChunkProcessor` multiplica por `spec`.
/// - ONNX: `spec_real`, `spec_imag` `(1, 2, bins, T)` en `[canal, frec, trama]` → `out_spec_real`, `out_spec_imag`
///   `(1, stems, 2, bins, T)`: el espectro de cada stem **ya enmascarado** (`sw_common.make_core`).
///
/// La máscara equivalente es `out / spec` (en Double, `out·conj(spec) / |spec|²`); donde `spec` es 0 exacto la
/// máscara vale 0 (el producto es 0 igual). Así el troceado, el solape y el DSP siguen sin cambios.
enum SeparationSpectrumLayout {
    /// Índice plano `[canal, frec, trama]` de un plano `(2, bins, T)`.
    @inline(__always)
    static func planeIndex(bin f: Int, channel c: Int, frame t: Int, bins: Int, frames: Int) -> Int {
        (c * bins + f) * frames + t
    }

    /// `spec` (layout de StemKit) → planos real e imaginario `(2, bins, T)`.
    static func split(spec: UnsafePointer<Float>, bins: Int, frames: Int,
                      real: UnsafeMutablePointer<Float>, imag: UnsafeMutablePointer<Float>) {
        for c in 0..<2 {
            for f in 0..<bins {
                let src = spec + (2 * f + c) * frames * 2
                let dst = planeIndex(bin: f, channel: c, frame: 0, bins: bins, frames: frames)
                for t in 0..<frames {
                    real[dst + t] = src[2 * t]
                    imag[dst + t] = src[2 * t + 1]
                }
            }
        }
    }

    /// Espectros enmascarados `(stems, 2, bins, T)` → máscara `[stems, 2·bins, T, 2]` tal que máscara·spec = out.
    static func mask(outReal: UnsafePointer<Float>, outImag: UnsafePointer<Float>, spec: UnsafePointer<Float>,
                     stems: Int, bins: Int, frames: Int, into mask: UnsafeMutablePointer<Float>) {
        let perStem = 2 * bins * frames
        for s in 0..<stems {
            for c in 0..<2 {
                for f in 0..<bins {
                    let row = 2 * f + c
                    let x = spec + row * frames * 2
                    let m = mask + (s * 2 * bins + row) * frames * 2
                    let o = s * perStem + planeIndex(bin: f, channel: c, frame: 0, bins: bins, frames: frames)
                    for t in 0..<frames {
                        let xr = Double(x[2 * t]), xi = Double(x[2 * t + 1])
                        let power = xr * xr + xi * xi
                        if power == 0 {
                            m[2 * t] = 0
                            m[2 * t + 1] = 0
                            continue
                        }
                        let yr = Double(outReal[o + t]), yi = Double(outImag[o + t])
                        m[2 * t] = Float((yr * xr + yi * xi) / power)
                        m[2 * t + 1] = Float((yi * xr - yr * xi) / power)
                    }
                }
            }
        }
    }
}
