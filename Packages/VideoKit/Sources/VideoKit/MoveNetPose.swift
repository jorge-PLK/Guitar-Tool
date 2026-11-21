import Foundation

// Pose del encuadre fuera del Mac (plan, «Corte del paso 7», parte 7.11; modelo de la parte 7.3): MoveNet SinglePose
// Thunder en ONNX. Pre y posprocesado puros y portables, probados en el Mac; el modelo va detrás de
// `PoseKeypointModel` (Windows: ONNX Runtime, `OnnxPoseModel`). Da lo mismo que `GuitarFramer.joints(in:)` con Vision:
// las 10 articulaciones de `PoseJoint` con confianza ≥ `GuitarFramer.minConfidence`, normalizadas a la imagen (ya
// girada) con origen arriba a la izquierda. Réplica de `Probes/P8-windows/ort-models/pose.py`, donde se midió frente a
// Vision (error medio 0,025; umbral aprobado 0,05).

/// El modelo de pose: entrada NHWC (1, lado, lado, 3) RGB 0…255 → 17 puntos COCO (y, x, confianza) en el cuadrado.
protocol PoseKeypointModel: Sendable {
    func keypoints(input: [Float]) throws -> [Float]
}

/// Contrato de MoveNet SinglePose Thunder (parte 7.3: Xenova/movenet-singlepose-thunder@38296077, Apache-2.0, envuelto
/// con un `Cast` para que la entrada sea float32).
enum MoveNetPose {
    /// Lado de la entrada (px).
    static let inputSide = 256
    static let inputName = "image"
    static let outputName = "output_0"
    static let keypointCount = 17
    /// Carpeta de desarrollo en `TF_MODELS_DIR` (`pose/model.onnx`) y clave del proveedor recordado.
    static let modelFolder = "pose"

    /// Índices COCO de las 8 articulaciones directas; `neck` y `root` son la media de hombros y de caderas.
    static let coco: [(PoseJoint, Int)] = [
        (.leftShoulder, 5), (.rightShoulder, 6), (.leftElbow, 7), (.rightElbow, 8),
        (.leftWrist, 9), (.rightWrist, 10), (.leftHip, 11), (.rightHip, 12)
    ]

    /// Dónde cae la imagen dentro del cuadrado (resize_with_pad: escala conservando el aspecto, centrada, ceros alrededor).
    struct Letterbox: Equatable, Sendable {
        var x: Int
        var y: Int
        var width: Int
        var height: Int
        var side: Int

        /// Como `pose.py`: `round` de Python (mitades al par) y división entera para el desplazamiento.
        init(width w: Int, height h: Int, side: Int = MoveNetPose.inputSide) {
            let sc = Double(side) / Double(max(1, max(w, h)))
            width = max(1, Int((Double(w) * sc).rounded(.toNearestOrEven)))
            height = max(1, Int((Double(h) * sc).rounded(.toNearestOrEven)))
            x = (side - width) / 2
            y = (side - height) / 2
            self.side = side
        }

        init(x: Int, y: Int, width: Int, height: Int, side: Int) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
            self.side = side
        }
    }

    /// Cómo están los canales de un píxel en memoria.
    struct PixelLayout: Sendable {
        var bytesPerPixel: Int
        var red: Int
        var green: Int
        var blue: Int

        static let bgra = PixelLayout(bytesPerPixel: 4, red: 2, green: 1, blue: 0)
        static let rgba = PixelLayout(bytesPerPixel: 4, red: 0, green: 1, blue: 2)
        static let rgb = PixelLayout(bytesPerPixel: 3, red: 0, green: 1, blue: 2)
    }

    // MARK: - Entrada

    /// Tensor de entrada (lado × lado × 3, RGB 0…255 enteros) y dónde quedó la imagen. El redimensionado es el BILINEAR
    /// de Pillow bit a bit (el de la medida frente a Vision): filtro triangular ensanchado al reducir, coeficientes en
    /// punto fijo de 22 bits, pasada horizontal y luego vertical, cada una redondeada a 8 bits.
    static func input(pixels: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int, layout: PixelLayout,
                      side: Int = inputSide) -> (tensor: [Float], box: Letterbox) {
        let box = Letterbox(width: width, height: height, side: side)
        var tensor = [Float](repeating: 0, count: side * side * 3)
        guard width > 0, height > 0 else { return (tensor, box) }
        let src = pixels.assumingMemoryBound(to: UInt8.self)
        let h = PillowBilinear(inSize: width, outSize: box.width)
        let v = PillowBilinear(inSize: height, outSize: box.height)
        // Pasada horizontal: filas de la imagen → `box.width` columnas RGB de 8 bits.
        let tw = box.width
        var temp = [UInt8](repeating: 0, count: height * tw * 3)
        temp.withUnsafeMutableBufferPointer { t in
            h.k.withUnsafeBufferPointer { k in
                let ch = (layout.red, layout.green, layout.blue)
                for y in 0..<height {
                    let row = src + y * bytesPerRow
                    for xx in 0..<tw {
                        let xmin = h.bounds[2 * xx], n = h.bounds[2 * xx + 1]
                        var s0 = PillowBilinear.half, s1 = PillowBilinear.half, s2 = PillowBilinear.half
                        for i in 0..<n {
                            let p = row + (xmin + i) * layout.bytesPerPixel
                            let w = Int(k[xx * h.ksize + i])
                            s0 += Int(p[ch.0]) * w
                            s1 += Int(p[ch.1]) * w
                            s2 += Int(p[ch.2]) * w
                        }
                        let o = (y * tw + xx) * 3
                        t[o] = PillowBilinear.clip8(s0)
                        t[o + 1] = PillowBilinear.clip8(s1)
                        t[o + 2] = PillowBilinear.clip8(s2)
                    }
                }
            }
        }
        // Pasada vertical, directa al cuadrado con el desplazamiento del relleno.
        temp.withUnsafeBufferPointer { t in
            v.k.withUnsafeBufferPointer { k in
                tensor.withUnsafeMutableBufferPointer { out in
                    for yy in 0..<box.height {
                        let ymin = v.bounds[2 * yy], n = v.bounds[2 * yy + 1]
                        for xx in 0..<tw {
                            var s0 = PillowBilinear.half, s1 = PillowBilinear.half, s2 = PillowBilinear.half
                            for i in 0..<n {
                                let o = ((ymin + i) * tw + xx) * 3
                                let w = Int(k[yy * v.ksize + i])
                                s0 += Int(t[o]) * w
                                s1 += Int(t[o + 1]) * w
                                s2 += Int(t[o + 2]) * w
                            }
                            let d = ((box.y + yy) * side + box.x + xx) * 3
                            out[d] = Float(PillowBilinear.clip8(s0))
                            out[d + 1] = Float(PillowBilinear.clip8(s1))
                            out[d + 2] = Float(PillowBilinear.clip8(s2))
                        }
                    }
                }
            }
        }
        return (tensor, box)
    }

    // MARK: - Salida

    /// 17 × (y, x, confianza) en el cuadrado → articulaciones normalizadas a la imagen, origen arriba a la izquierda.
    /// `neck` y `root`: media de los dos puntos y la menor de sus confianzas. Solo las de confianza ≥ `minConfidence`.
    static func joints(keypoints kp: [Float], box: Letterbox,
                       minConfidence: Float = GuitarFramer.minConfidence) -> [PoseJoint: PosePoint] {
        guard kp.count >= keypointCount * 3, box.width > 0, box.height > 0 else { return [:] }
        let s = Double(box.side)
        var all: [PoseJoint: (p: PosePoint, c: Float)] = [:]
        for (joint, i) in coco {
            let y = Double(kp[3 * i]), x = Double(kp[3 * i + 1])
            all[joint] = (PosePoint(x: (x * s - Double(box.x)) / Double(box.width),
                                    y: (y * s - Double(box.y)) / Double(box.height)), kp[3 * i + 2])
        }
        for (joint, a, b) in [(PoseJoint.neck, PoseJoint.leftShoulder, PoseJoint.rightShoulder),
                              (PoseJoint.root, PoseJoint.leftHip, PoseJoint.rightHip)] {
            guard let pa = all[a], let pb = all[b] else { continue }
            all[joint] = (PosePoint(x: (pa.p.x + pb.p.x) / 2, y: (pa.p.y + pb.p.y) / 2), min(pa.c, pb.c))
        }
        return all.filter { $0.value.c >= minConfidence }.mapValues(\.p)
    }
}

/// Coeficientes del BILINEAR de Pillow (`precompute_coeffs` + `normalize_coeffs_8bpc` de `Resample.c`).
struct PillowBilinear {
    /// `PRECISION_BITS` de Pillow: 32 − 8 − 2.
    static let precisionBits = 22
    static let half = 1 << (precisionBits - 1)

    let ksize: Int
    /// Por salida: primer píxel de entrada y cuántos.
    let bounds: [Int]
    /// Por salida: `ksize` pesos en punto fijo (los que sobran, 0).
    let k: [Int32]

    init(inSize: Int, outSize: Int) {
        let scale = Double(inSize) / Double(outSize)
        let filterscale = max(1, scale)
        let support = 1.0 * filterscale
        ksize = Int(support.rounded(.up)) * 2 + 1
        var bounds = [Int](repeating: 0, count: 2 * outSize)
        var k = [Int32](repeating: 0, count: outSize * ksize)
        var w = [Double](repeating: 0, count: ksize)
        for xx in 0..<outSize {
            let center = (Double(xx) + 0.5) * scale
            let ss = 1 / filterscale
            // (int) de C: trunca hacia cero.
            let xmin = max(0, Int(center - support + 0.5))
            let xmax = min(inSize, Int(center + support + 0.5)) - xmin
            var ww = 0.0
            for x in 0..<ksize { w[x] = 0 }
            for x in 0..<max(0, xmax) {
                let t = abs((Double(x + xmin) - center + 0.5) * ss)
                w[x] = t < 1 ? 1 - t : 0
                ww += w[x]
            }
            for x in 0..<ksize {
                let f = ww != 0 ? w[x] / ww : w[x]
                let scaled = f * Double(1 << Self.precisionBits)
                k[xx * ksize + x] = Int32(f < 0 ? -0.5 + scaled : 0.5 + scaled)
            }
            bounds[2 * xx] = xmin
            bounds[2 * xx + 1] = max(0, xmax)
        }
        self.bounds = bounds
        self.k = k
    }

    /// `clip8` de Pillow: desplaza y satura a 0…255.
    @inline(__always)
    static func clip8(_ s: Int) -> UInt8 {
        let v = s >> precisionBits
        return v < 0 ? 0 : (v > 255 ? 255 : UInt8(v))
    }
}

/// Pose de un fotograma con MoveNet: entrada, modelo y decodificación.
struct MoveNetPoseDetector: Sendable {
    let model: any PoseKeypointModel

    func joints(pixels: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int,
                layout: MoveNetPose.PixelLayout = .bgra) throws -> [PoseJoint: PosePoint] {
        let (tensor, box) = MoveNetPose.input(pixels: pixels, width: width, height: height, bytesPerRow: bytesPerRow, layout: layout)
        return MoveNetPose.joints(keypoints: try model.keypoints(input: tensor), box: box)
    }

    /// Pose de un fotograma del encuadre con el contrato del Mac (`GuitarFramer+Vision`: `try?` por fotograma): si la
    /// inferencia falla, ese fotograma queda sin pose y el análisis sigue (decisión de Jorge, 21/11, parte 7.11b). Que
    /// el modelo no cargue sigue siendo error, antes del primer fotograma (`GuitarFramer.poseDetector`).
    func frameJoints(pixels: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int,
                     layout: MoveNetPose.PixelLayout = .bgra) -> [PoseJoint: PosePoint] {
        (try? joints(pixels: pixels, width: width, height: height, bytesPerRow: bytesPerRow, layout: layout)) ?? [:]
    }
}
