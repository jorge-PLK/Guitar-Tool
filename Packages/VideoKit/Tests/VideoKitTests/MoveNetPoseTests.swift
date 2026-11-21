import CMiniz
import Foundation
import XCTest
@testable import VideoKit

/// Pose del encuadre con MoveNet (plan, «Corte del paso 7», parte 7.11): pre y posprocesado puros, iguales en el Mac
/// y en Windows. Las referencias de la entrada son de Pillow 11.3 (`Image.resize(BILINEAR)` + relleno, como
/// `Probes/P8-windows/ort-models/pose.py`) y se exigen bit a bit.
///
/// `testRealModelAgainstVision` (solo con `TF_MODEL_TESTS=1`, bajo el vigilante) usa los fotogramas de la parte 7.3:
/// `<TF_MODELS_DIR>/pose/` (en el Mac, por defecto `Probes/P8-windows/ort-models/out/pose`; en Windows,
/// `C:\tf-models\pose`) con `model.onnx`, `in_image.bin`, `mac.json` y `takeA/`, `takeC/` (PNG + `vision.json`).
///   TF_MODEL_TESTS=1 Tools/py/.venv/bin/python Probes/P4-modelos/common/guard.py --limit-gb 10 \
///     --log Temp/logs/guard-videokit-pose.log -- Tools/test.sh VideoKit MoveNetPoseTests
/// En el Mac `NativeONNX` no tiene ONNX Runtime: el modelo lo corre el ORT de Python (`Tools/py/.venv`) sobre los
/// tensores que prepara Swift; en Windows, `OnnxPoseModel`.
final class MoveNetPoseTests: XCTestCase {
    /// Umbral de Jorge (parte 7.3): error medio de pose frente a Vision, en coordenadas normalizadas.
    static let maxMeanErrorVsVision = 0.05

    /// Imagen sintética de `pilref`: RGB por fórmula.
    static func synthetic(width: Int, height: Int) -> [UInt8] {
        var a = [UInt8](repeating: 0, count: width * height * 3)
        for y in 0..<height {
            for x in 0..<width {
                let o = (y * width + x) * 3
                a[o] = UInt8((x * 37 + y * 11) % 256)
                a[o + 1] = UInt8((x * 5 + y * 53 + 17) % 256)
                a[o + 2] = UInt8((x * x + 3 * y * y) % 256)
            }
        }
        return a
    }

    static func letterbox(_ rgb: [UInt8], width: Int, height: Int, layout: MoveNetPose.PixelLayout = .rgb,
                          side: Int) -> (tensor: [Float], box: MoveNetPose.Letterbox) {
        rgb.withUnsafeBytes {
            MoveNetPose.input(pixels: $0.baseAddress!, width: width, height: height, bytesPerRow: width * layout.bytesPerPixel,
                              layout: layout, side: side)
        }
    }

    /// Geometría de resize_with_pad, con el `round` de Python (mitades al par).
    func testLetterboxGeometry() {
        typealias L = MoveNetPose.Letterbox
        XCTAssertEqual(L(width: 1920, height: 1080), L(x: 0, y: 56, width: 256, height: 144, side: 256))
        XCTAssertEqual(L(width: 1080, height: 1920), L(x: 56, y: 0, width: 144, height: 256, side: 256))
        XCTAssertEqual(L(width: 640, height: 480), L(x: 0, y: 32, width: 256, height: 192, side: 256))
        XCTAssertEqual(L(width: 1000, height: 333), L(x: 0, y: 85, width: 256, height: 85, side: 256))
        // 257 · 0,5 = 128,5 → 128 (al par), desplazamiento (256 − 128) / 2 = 64.
        XCTAssertEqual(L(width: 512, height: 257), L(x: 0, y: 64, width: 256, height: 128, side: 256))
        XCTAssertEqual(L(width: 23, height: 13, side: 8), L(x: 0, y: 1, width: 8, height: 5, side: 8))
        XCTAssertEqual(L(width: 9, height: 31, side: 8), L(x: 3, y: 0, width: 2, height: 8, side: 8))
    }

    /// Entrada igual a Pillow bit a bit: reducción (23×13, 9×31) y ampliación (5×3), con el relleno a cero.
    func testInputMatchesPillowExactly() {
        let cases: [(w: Int, h: Int, ref: [Int])] = [
            (23, 13, Self.pillow23x13), (5, 3, Self.pillow5x3), (9, 31, Self.pillow9x31)
        ]
        for c in cases {
            let (t, _) = Self.letterbox(Self.synthetic(width: c.w, height: c.h), width: c.w, height: c.h, side: 8)
            XCTAssertEqual(t.count, c.ref.count)
            let worst = zip(t, c.ref).map { abs(Double($0) - Double($1)) }.max() ?? .nan
            print(String(format: "7.11 entrada %dx%d → 8: máx |Swift − Pillow| %.0f niveles", c.w, c.h, worst))
            XCTAssertEqual(worst, 0, "\(c.w)x\(c.h)")
        }
    }

    /// BGRA (Windows) y RGB dan el mismo tensor; imagen lisa → contenido de su color y relleno a 0.
    func testChannelOrderAndPadding() {
        let w = 40, h = 30
        let rgb = Self.synthetic(width: w, height: h)
        var bgra = [UInt8](repeating: 255, count: w * h * 4)
        for i in 0..<(w * h) { bgra[4 * i] = rgb[3 * i + 2]; bgra[4 * i + 1] = rgb[3 * i + 1]; bgra[4 * i + 2] = rgb[3 * i] }
        let a = Self.letterbox(rgb, width: w, height: h, side: 16)
        let b = Self.letterbox(bgra, width: w, height: h, layout: .bgra, side: 16)
        XCTAssertEqual(a.tensor, b.tensor)

        let flat = [UInt8](repeating: 0, count: w * h * 3).enumerated().map { [UInt8(200), 100, 7][$0.offset % 3] }
        let (t, box) = Self.letterbox(flat, width: w, height: h, side: 16)
        XCTAssertEqual(box, MoveNetPose.Letterbox(x: 0, y: 2, width: 16, height: 12, side: 16))
        for y in 0..<16 {
            for x in 0..<16 {
                let inside = y >= 2 && y < 14
                let px = Array(t[((y * 16 + x) * 3)..<((y * 16 + x) * 3 + 3)])
                XCTAssertEqual(px, inside ? [200, 100, 7] : [0, 0, 0], "(\(x), \(y))")
            }
        }
    }

    /// 17 × (y, x, confianza) → coordenadas de la imagen; `neck`/`root` como media con la menor confianza; umbral 0,3.
    func testDecodeKeypoints() throws {
        let box = MoveNetPose.Letterbox(width: 1920, height: 1080)   // x 0, y 56, 256 × 144
        var kp = [Float](repeating: 0, count: 17 * 3)
        func set(_ i: Int, x: Double, y: Double, c: Float) {
            // Punto de la imagen (x, y normalizados) → cuadrado de 256.
            kp[3 * i] = Float((y * 144 + 56) / 256)
            kp[3 * i + 1] = Float(x)
            kp[3 * i + 2] = c
        }
        set(5, x: 0.40, y: 0.30, c: 0.9)    // hombro izq.
        set(6, x: 0.60, y: 0.32, c: 0.5)    // hombro der.
        set(9, x: 0.35, y: 0.70, c: 0.31)   // muñeca izq.
        set(10, x: 0.65, y: 0.72, c: 0.29)  // muñeca der.: fuera
        set(11, x: 0.45, y: 0.80, c: 0.8)   // cadera izq.
        set(12, x: 0.55, y: 0.80, c: 0.2)   // cadera der.: fuera, y `root` también
        set(0, x: 0.5, y: 0.1, c: 0.99)     // nariz: no es del encuadre
        let j = MoveNetPose.joints(keypoints: kp, box: box)
        XCTAssertEqual(Set(j.keys), [.leftShoulder, .rightShoulder, .neck, .leftWrist, .leftHip])
        let eps = 1e-6
        XCTAssertEqual(try XCTUnwrap(j[.leftShoulder]).x, 0.40, accuracy: eps)
        XCTAssertEqual(try XCTUnwrap(j[.leftShoulder]).y, 0.30, accuracy: eps)
        XCTAssertEqual(try XCTUnwrap(j[.neck]).x, 0.50, accuracy: eps)
        XCTAssertEqual(try XCTUnwrap(j[.neck]).y, 0.31, accuracy: eps)
        XCTAssertEqual(try XCTUnwrap(j[.leftWrist]).y, 0.70, accuracy: eps)
        XCTAssertTrue(MoveNetPose.joints(keypoints: [0, 0, 1], box: box).isEmpty)
    }

    /// Detector con un modelo falso: recibe 256 × 256 × 3 y sus puntos llegan decodificados.
    func testDetectorWithFakeModel() throws {
        struct Fake: PoseKeypointModel {
            func keypoints(input: [Float]) throws -> [Float] {
                guard input.count == 256 * 256 * 3 else { throw GuitarFramerError.read("forma") }
                var kp = [Float](repeating: 0.9, count: 51)
                for i in 0..<17 { kp[3 * i] = 0.5; kp[3 * i + 1] = 0.25 }
                return kp
            }
        }
        let w = 64, h = 32
        let bgra = [UInt8](repeating: 128, count: w * h * 4)
        let j = try bgra.withUnsafeBytes {
            try MoveNetPoseDetector(model: Fake()).joints(pixels: $0.baseAddress!, width: w, height: h, bytesPerRow: w * 4)
        }
        XCTAssertEqual(j.count, PoseJoint.allCases.count)
        XCTAssertEqual(try XCTUnwrap(j[.root]).x, 0.25, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(j[.root]).y, 0.5, accuracy: 1e-6)
    }

    /// Decisión de Jorge (21/11, parte 7.11b): si la inferencia falla en un fotograma, ese fotograma queda sin pose y
    /// el análisis sigue, como Vision en el Mac (`try?`). 8 fotogramas, el modelo falla en el 3.º: 8 muestras, 7 con
    /// pose, la caja fija sale y el fotograma fallido tiene 0 articulaciones; `joints` (sin tragar) sí lanza.
    func testInferenceFailureLeavesFrameWithoutPose() throws {
        struct FailsOnce: PoseKeypointModel {
            let failing: Float
            func keypoints(input: [Float]) throws -> [Float] {
                // El fotograma se reconoce por su gris (el valor del primer píxel de la imagen, centro del cuadrado).
                let s = MoveNetPose.inputSide
                if input[(s / 2 * s + s / 2) * 3] == failing { throw GuitarFramerError.read("inferencia") }
                var kp = [Float](repeating: 0.9, count: 51)
                for i in 0..<17 { kp[3 * i] = 0.3 + Float(i) * 0.02; kp[3 * i + 1] = 0.3 + Float(i % 5) * 0.08 }
                return kp
            }
        }
        let w = 64, h = 64, failingGray: UInt8 = 102
        let detector = MoveNetPoseDetector(model: FailsOnce(failing: Float(failingGray)))
        var samples: [PoseSample] = []
        for k in 0..<8 {
            let gray = UInt8(100 + k)
            let bgra = [UInt8](repeating: gray, count: w * h * 4)
            let joints = bgra.withUnsafeBytes {
                detector.frameJoints(pixels: $0.baseAddress!, width: w, height: h, bytesPerRow: w * 4)
            }
            if gray == failingGray {
                XCTAssertThrowsError(try bgra.withUnsafeBytes {
                    try detector.joints(pixels: $0.baseAddress!, width: w, height: h, bytesPerRow: w * 4)
                })
            }
            samples.append(PoseSample(time: 1 + Double(k) * GuitarFramer.defaultInterval, joints: joints))
        }
        let a = GuitarFramer.analyze(samples: samples, frameWidth: w, frameHeight: h, fingerprint: "fallo")
        print("7.11b fallo de inferencia: \(a.samples) muestras, \(a.detected) con pose, articulaciones por muestra \(samples.map(\.joints.count))")
        XCTAssertEqual(a.samples, 8)
        XCTAssertEqual(a.detected, 7)
        XCTAssertEqual(samples[2].joints.count, 0)
        XCTAssertEqual(samples.filter { $0.joints.count == PoseJoint.allCases.count }.count, 7)
        XCTAssertNotNil(a.fixed)
    }

    /// El lector de PNG de los tests frente al escritor de `RenderSupport` (RGB, filtro 0). Los filtros 1–4 los
    /// cubren los fotogramas reales de `testRealModelAgainstVision` (entrada igual a Pillow bit a bit).
    func testPNGReader() throws {
        let rgba: [UInt8] = (0..<(5 * 3 * 4)).map { UInt8(($0 * 29) % 256) }
        let img = try XCTUnwrap(TestPNG.decode(RenderSupport.png(rgba: rgba, width: 5, height: 3)))
        XCTAssertEqual(img.width, 5)
        XCTAssertEqual(img.height, 3)
        XCTAssertEqual(img.channels, 3)
        XCTAssertEqual(img.pixels, rgba.enumerated().filter { $0.offset % 4 != 3 }.map(\.element))
    }

    // MARK: - Modelo real (TF_MODEL_TESTS=1)

    static let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    static func poseDirectory() -> URL {
        let env = ProcessInfo.processInfo.environment
        #if os(Windows)
        let root = env["TF_MODELS_DIR"] ?? "C:\\tf-models"
        #else
        let root = env["TF_MODELS_DIR"] ?? repo.appendingPathComponent("Probes/P8-windows/ort-models/out").path
        #endif
        return URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent(MoveNetPose.modelFolder, isDirectory: true)
    }

    struct VisionFile: Decodable {
        struct Frame: Decodable {
            var png: String
            var t: Double
            var joints: [String: [Double]]
        }
        var frames: [Frame]
    }

    /// Los 16 fotogramas de la parte 7.3: entrada de Swift → MoveNet → decodificación de Swift, frente a Vision.
    func testRealModelAgainstVision() throws {
        guard ProcessInfo.processInfo.environment["TF_MODEL_TESTS"] == "1" else {
            throw XCTSkip("tests del modelo real desactivados (TF_MODEL_TESTS != 1)")
        }
        let dir = Self.poseDirectory()
        let model = dir.appendingPathComponent("model.onnx")
        guard FileManager.default.fileExists(atPath: model.path) else { throw XCTSkip("no está el modelo en \(model.path)") }

        var inputs: [[Float]] = []
        var boxes: [MoveNetPose.Letterbox] = []
        var vision: [[PoseJoint: PosePoint]] = []
        var names: [String] = []
        for take in ["takeA", "takeC"] {
            let folder = dir.appendingPathComponent(take, isDirectory: true)
            let file = try JSONDecoder().decode(VisionFile.self, from: Data(contentsOf: folder.appendingPathComponent("vision.json")))
            for f in file.frames {
                let img = try XCTUnwrap(TestPNG.decode(Data(contentsOf: folder.appendingPathComponent(f.png))), f.png)
                let layout: MoveNetPose.PixelLayout = img.channels == 4 ? .rgba : .rgb
                let (t, box) = img.pixels.withUnsafeBytes {
                    MoveNetPose.input(pixels: $0.baseAddress!, width: img.width, height: img.height,
                                      bytesPerRow: img.width * img.channels, layout: layout)
                }
                inputs.append(t)
                boxes.append(box)
                var v: [PoseJoint: PosePoint] = [:]
                for (k, p) in f.joints { if let j = PoseJoint(rawValue: k), p.count >= 2 { v[j] = PosePoint(x: p[0], y: p[1]) } }
                vision.append(v)
                names.append("\(take) t=\(Int(f.t))")
            }
        }
        XCTAssertEqual(inputs.count, 16)

        // Entrada del primer fotograma frente a la de pose.py (Pillow), guardada por la parte 7.3.
        let pyInput = try Self.floats(dir.appendingPathComponent("in_image.bin"))
        let inWorst = zip(inputs[0], pyInput).map { abs($0 - $1) }.max() ?? .nan
        let inDiff = zip(inputs[0], pyInput).filter { $0 != $1 }.count
        print(String(format: "7.11 entrada real takeA t=15: máx |Swift − Pillow| %.0f niveles, %d de %d valores distintos",
                     inWorst, inDiff, pyInput.count))
        XCTAssertEqual(pyInput.count, inputs[0].count)
        XCTAssertEqual(inWorst, 0)

        let t0 = Date()
        let outputs = try Self.runModel(model, inputs)
        let ms = Date().timeIntervalSince(t0) * 1000 / Double(inputs.count)

        var errs: [Double] = []
        var onlyVision = 0, onlyMoveNet = 0
        for (i, out) in outputs.enumerated() {
            let mn = MoveNetPose.joints(keypoints: out, box: boxes[i])
            var line: [String] = []
            for k in PoseJoint.allCases {
                switch (vision[i][k], mn[k]) {
                case let (v?, m?):
                    let e = hypot(m.x - v.x, m.y - v.y)
                    errs.append(e)
                    line.append(String(format: "%@ %.3f", k.rawValue, e))
                case (.some, nil): onlyVision += 1
                case (nil, .some): onlyMoveNet += 1
                case (nil, nil): break
                }
            }
            print("7.11 \(names[i]): \(line.joined(separator: ", "))")
        }
        let sorted = errs.sorted()
        let mean = errs.reduce(0, +) / Double(max(1, errs.count))
        let median = sorted.isEmpty ? .nan : sorted[sorted.count / 2]
        print(String(format: "7.11 pose MoveNet (Swift) frente a Vision: %d pares, error medio %.4f (umbral %.2f), mediana %.4f, máx %.4f; solo Vision %d, solo MoveNet %d; %.1f ms/fotograma con el modelo",
                     errs.count, mean, Self.maxMeanErrorVsVision, median, sorted.last ?? .nan, onlyVision, onlyMoveNet, ms))
        XCTAssertGreaterThanOrEqual(errs.count, 40)
        XCTAssertLessThanOrEqual(mean, Self.maxMeanErrorVsVision)
    }

    static func floats(_ url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    /// Salidas (17 × 3) del modelo para cada entrada.
    static func runModel(_ model: URL, _ inputs: [[Float]]) throws -> [[Float]] {
        #if os(Windows)
        let onnx = try OnnxPoseModel(modelURL: model)
        return try inputs.map { try onnx.keypoints(input: $0) }
        #else
        // Sin ONNX Runtime en el Mac: el ORT de Python, con las entradas de Swift en un fichero.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("movenet-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let inURL = tmp.appendingPathComponent("in.bin"), outURL = tmp.appendingPathComponent("out.bin")
        let flat = inputs.flatMap { $0 }
        try flat.withUnsafeBytes { Data($0) }.write(to: inURL)
        let script = """
        import sys, numpy as np, onnxruntime as ort
        m, i, o, n = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
        s = ort.InferenceSession(m, providers=["CPUExecutionProvider"])
        x = np.fromfile(i, np.float32).reshape(n, 1, 256, 256, 3)
        np.concatenate([s.run(["output_0"], {"image": x[k]})[0].reshape(-1) for k in range(n)]).astype(np.float32).tofile(o)
        """
        let p = Process()
        p.executableURL = repo.appendingPathComponent("Tools/py/.venv/bin/python")
        p.arguments = ["-I", "-c", script, model.path, inURL.path, outURL.path, "\(inputs.count)"]
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw GuitarFramerError.read("python ORT salió con \(p.terminationStatus)") }
        let out = try floats(outURL)
        let n = MoveNetPose.keypointCount * 3
        guard out.count == n * inputs.count else { throw GuitarFramerError.read("salida de \(out.count) valores") }
        return (0..<inputs.count).map { Array(out[($0 * n)..<(($0 + 1) * n)]) }
        #endif
    }

    // MARK: - Referencias de Pillow 11.3 (scratchpad pilref.py: letterbox a 8 px de `synthetic`)

    static let pillow23x13: [Int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 57, 80, 8, 154, 93, 22, 115, 108, 52, 110, 122, 99, 161, 136, 162, 82, 142, 131, 168, 147, 81, 101, 160, 183, 82, 162, 39, 169, 169, 53, 109, 126, 83, 135, 127, 130, 134, 141, 183, 95, 118, 119, 169, 85, 112, 80, 98, 169, 111, 107, 113, 170, 118, 127, 89, 117, 152, 160, 127, 170, 124, 140, 133, 120, 139, 100, 147, 148, 162, 76, 161, 110, 140, 170, 175, 145, 131, 136, 92, 113, 113, 170, 127, 97, 92, 138, 124, 148, 98, 148, 138, 93, 109, 96, 106, 135, 165, 108, 124, 111, 110, 128, 113, 118, 146, 163, 132, 136, 85, 146, 133, 169, 160, 114, 104, 175, 151, 121, 188, 124, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    static let pillow5x3: [Int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 17, 0, 16, 19, 0, 39, 22, 1, 62, 25, 3, 86, 29, 6, 109, 32, 9, 132, 35, 13, 148, 37, 16, 4, 38, 1, 20, 40, 1, 43, 43, 2, 66, 46, 4, 90, 50, 7, 113, 53, 10, 136, 56, 14, 152, 58, 17, 11, 70, 3, 27, 72, 3, 50, 75, 4, 73, 78, 6, 97, 82, 9, 120, 85, 12, 143, 88, 16, 159, 90, 19, 18, 102, 8, 34, 104, 8, 57, 107, 9, 80, 110, 11, 104, 114, 14, 127, 117, 17, 150, 120, 21, 166, 122, 24, 22, 123, 12, 38, 125, 12, 61, 128, 13, 84, 131, 15, 108, 135, 18, 131, 138, 21, 154, 141, 25, 170, 143, 28, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    static let pillow9x31: [Int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 100, 118, 22, 133, 121, 51, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 132, 132, 98, 116, 121, 122, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 147, 138, 146, 103, 112, 123, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 152, 127, 129, 118, 127, 120, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 126, 120, 112, 145, 132, 134, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 103, 116, 122, 149, 134, 146, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 105, 118, 142, 133, 132, 132, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 127, 150, 113, 122, 137, 0, 0, 0, 0, 0, 0, 0, 0, 0]
}

/// PNG de 8 bits sin entrelazar (RGB o RGBA), con miniz: para leer en los dos sistemas los fotogramas de la parte 7.3.
enum TestPNG {
    struct Image {
        var width: Int
        var height: Int
        var channels: Int
        var pixels: [UInt8]
    }

    static func decode(_ data: Data) -> Image? {
        let b = [UInt8](data)
        guard b.count > 8, b[0] == 0x89, b[1] == 0x50 else { return nil }
        func be32(_ o: Int) -> Int { Int(b[o]) << 24 | Int(b[o + 1]) << 16 | Int(b[o + 2]) << 8 | Int(b[o + 3]) }
        var o = 8, w = 0, h = 0, channels = 0
        var idat: [UInt8] = []
        while o + 8 <= b.count {
            let len = be32(o)
            let type = String(decoding: b[(o + 4)..<(o + 8)], as: UTF8.self)
            let body = o + 8
            guard body + len <= b.count else { return nil }
            switch type {
            case "IHDR":
                w = be32(body)
                h = be32(body + 4)
                guard b[body + 8] == 8, b[body + 12] == 0 else { return nil }   // 8 bits, sin entrelazar
                switch b[body + 9] { case 2: channels = 3; case 6: channels = 4; default: return nil }
            case "IDAT": idat.append(contentsOf: b[body..<(body + len)])
            case "IEND": break
            default: break
            }
            o = body + len + 4
        }
        guard w > 0, h > 0, channels > 0 else { return nil }
        var outLen = 0
        guard let p = idat.withUnsafeBytes({
            tinfl_decompress_mem_to_heap($0.baseAddress, $0.count, &outLen, Int32(TINFL_FLAG_PARSE_ZLIB_HEADER))
        }) else { return nil }
        defer { mz_free(p) }
        let raw = UnsafeBufferPointer(start: p.assumingMemoryBound(to: UInt8.self), count: outLen)
        let stride = w * channels
        guard outLen >= h * (stride + 1) else { return nil }
        var px = [UInt8](repeating: 0, count: h * stride)
        for y in 0..<h {
            let filter = raw[y * (stride + 1)]
            let src = y * (stride + 1) + 1, dst = y * stride
            for x in 0..<stride {
                let v = Int(raw[src + x])
                let a = x >= channels ? Int(px[dst + x - channels]) : 0
                let up = y > 0 ? Int(px[dst - stride + x]) : 0
                let ul = (y > 0 && x >= channels) ? Int(px[dst - stride + x - channels]) : 0
                let pred: Int
                switch filter {
                case 0: pred = 0
                case 1: pred = a
                case 2: pred = up
                case 3: pred = (a + up) / 2
                case 4:
                    let pa = abs(up - ul), pb = abs(a - ul), pc = abs(a + up - 2 * ul)
                    pred = (pa <= pb && pa <= pc) ? a : (pb <= pc ? up : ul)
                default: return nil
                }
                px[dst + x] = UInt8((v + pred) & 0xff)
            }
        }
        return Image(width: w, height: h, channels: channels, pixels: px)
    }
}
