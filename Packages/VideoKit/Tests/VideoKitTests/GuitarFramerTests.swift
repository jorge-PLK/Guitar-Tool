#if canImport(CoreGraphics)
import CoreGraphics
#endif
import XCTest
@testable import VideoKit

/// Parte pura de `GuitarFramer` con poses sintéticas (mini-spec Fase 7, «Pruebas»).
final class GuitarFramerTests: XCTestCase {
    /// Pose cuyas articulaciones ocupan el rectángulo de centro (cx, cy) y tamaño w × h.
    static func pose(cx: Double, cy: Double, w: Double, h: Double) -> [PoseJoint: PosePoint] {
        [
            .leftShoulder: PosePoint(x: cx - w * 0.3, y: cy - h / 2), .rightShoulder: PosePoint(x: cx + w * 0.3, y: cy - h / 2),
            .leftElbow: PosePoint(x: cx - w * 0.4, y: cy - h * 0.1), .rightElbow: PosePoint(x: cx + w * 0.45, y: cy),
            .leftWrist: PosePoint(x: cx - w / 2, y: cy + h * 0.1), .rightWrist: PosePoint(x: cx + w / 2, y: cy + h * 0.2),
            .leftHip: PosePoint(x: cx - w * 0.2, y: cy + h / 2), .rightHip: PosePoint(x: cx + w * 0.2, y: cy + h / 2)
        ]
    }

    /// Generador determinista en [−1, 1].
    struct Noise {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53) * 2 - 1
        }
    }

    func testBoxFromJoints() throws {
        let b = try XCTUnwrap(GuitarFramer.box(joints: Self.pose(cx: 0.5, cy: 0.6, w: 0.2, h: 0.3)))
        let m = GuitarFramer.boxMargin
        XCTAssertEqual(b.midX, 0.5, accuracy: 1e-12)
        XCTAssertEqual(b.midY, 0.6, accuracy: 1e-12)
        XCTAssertEqual(b.width, 0.2 * (1 + 2 * m), accuracy: 1e-12)
        XCTAssertEqual(b.height, 0.3 * (1 + 2 * m), accuracy: 1e-12)
        // Pocas articulaciones o sin brazos: sin caja.
        XCTAssertNil(GuitarFramer.box(joints: [.leftWrist: PosePoint(x: 0.1, y: 0.1), .rightWrist: PosePoint(x: 0.2, y: 0.2)]))
        XCTAssertNil(GuitarFramer.box(joints: [.leftHip: PosePoint(x: 0.1, y: 0.5), .rightHip: PosePoint(x: 0.3, y: 0.5), .neck: PosePoint(x: 0.2, y: 0.1)]))
        // Junto al borde: recortada al fotograma.
        let edge = try XCTUnwrap(GuitarFramer.box(joints: Self.pose(cx: 0.08, cy: 0.9, w: 0.16, h: 0.2)))
        XCTAssertGreaterThanOrEqual(edge.x, 0)
        XCTAssertLessThanOrEqual(edge.y + edge.height, 1 + 1e-12)
    }

    /// Recorte dentro del fotograma, con la proporción pedida y conteniendo la caja cuando cabe.
    func testCropInsideFrameWithRequestedAspect() {
        var noise = Noise(state: 7)
        var worstAspect = 0.0
        var count = 0
        for frame in [CGSize(width: 1920, height: 1080), CGSize(width: 1080, height: 1920), CGSize(width: 320, height: 180)] {
            for _ in 0..<300 {
                let w = 0.05 + 0.6 * abs(noise.next()), h = 0.05 + 0.6 * abs(noise.next())
                let box = FramingBox(x: (1 - w) * abs(noise.next()), y: (1 - h) * abs(noise.next()), width: w, height: h)
                let aspect = [0.5625, 0.915, 1, 1.7778, 0.45, 3][count % 6]
                let c = GuitarFramer.crop(box: box, frameSize: frame, aspect: aspect)
                XCTAssertGreaterThanOrEqual(c.x, -1e-12)
                XCTAssertGreaterThanOrEqual(c.y, -1e-12)
                XCTAssertLessThanOrEqual(c.x + c.width, 1 + 1e-12)
                XCTAssertLessThanOrEqual(c.y + c.height, 1 + 1e-12)
                let got = c.width * frame.width / (c.height * frame.height)
                worstAspect = max(worstAspect, abs(got / aspect - 1))
                // Si la caja ampliada cabe en el fotograma, la contiene.
                let needW = max(w * frame.width, h * frame.height * aspect), needH = needW / aspect
                if needW <= frame.width && needH <= frame.height {
                    XCTAssertLessThanOrEqual(c.x, box.x + 1e-9)
                    XCTAssertLessThanOrEqual(box.x + box.width, c.x + c.width + 1e-9)
                    XCTAssertLessThanOrEqual(c.y, box.y + 1e-9)
                    XCTAssertLessThanOrEqual(box.y + box.height, c.y + c.height + 1e-9)
                }
                count += 1
            }
        }
        XCTAssertLessThan(worstAspect, 1e-9)
        // Sin detección: el fotograma entero centrado (lo más grande de esa proporción).
        let none = GuitarFramer.crop(box: nil, frameSize: CGSize(width: 1920, height: 1080), aspect: 1)
        XCTAssertEqual(none.height, 1, accuracy: 1e-12)
        XCTAssertEqual(none.midX, 0.5, accuracy: 1e-12)
        print(String(format: "F7 recorte: %d casos dentro del fotograma, error relativo de proporción máx %.1e", count, worstAspect))
    }

    /// Trayectoria: temblor de ±0,02, una detección suelta a +0,3 y un hueco de 2 s sin pose.
    func testTrackSmoothingAndGaps() throws {
        var noise = Noise(state: 42)
        let truth: (Double) -> Double = { 0.4 + 0.1 * sin(2 * .pi * $0 / 10) }
        var samples: [PoseSample] = []
        var raw: [(Double, Double)] = []
        var t = 0.0
        while t <= 20 + 1e-9 {
            if t > 8 - 1e-9 && t < 10 - 1e-9 {
                samples.append(PoseSample(time: t, joints: [:]))
            } else {
                var cx = truth(t) + 0.02 * noise.next()
                if abs(t - 5) < 1e-9 { cx += 0.3 }
                raw.append((t, cx))
                samples.append(PoseSample(time: t, joints: Self.pose(cx: cx, cy: 0.55 + 0.01 * noise.next(), w: 0.3, h: 0.35)))
            }
            t += GuitarFramer.defaultInterval
        }
        let a = GuitarFramer.analyze(samples: samples, frameWidth: 1920, frameHeight: 1080, fingerprint: "x")
        XCTAssertEqual(a.samples, samples.count)
        XCTAssertEqual(a.detected, samples.count - 8)
        XCTAssertEqual(a.track.count, samples.count)
        // Fija: mediana (cerca del centro medio de la toma y del tamaño real).
        let fixed = try XCTUnwrap(a.fixed)
        XCTAssertEqual(fixed.width, 0.3 * (1 + 2 * GuitarFramer.boxMargin), accuracy: 0.03)
        XCTAssertEqual(fixed.midY, 0.55, accuracy: 0.01)

        let xs = a.track.map { $0.box.midX }
        func rms(_ v: [Double]) -> Double { (v.map { $0 * $0 }.reduce(0, +) / Double(v.count)).squareRoot() }
        func secondDiff(_ v: [Double]) -> [Double] {
            (1..<(v.count - 1)).map { (i: Int) -> Double in
                let d: Double = v[i + 1] - 2 * v[i]
                return d + v[i - 1]
            }
        }
        let rawJitter = rms(secondDiff(raw.map(\.1))), smoothJitter = rms(secondDiff(xs))
        let rawErrors: [Double] = raw.map { p in p.1 - truth(p.0) }
        let smoothErrors: [Double] = a.track.map { k in k.box.midX - truth(k.time) }
        let rawErr = rms(rawErrors), smoothErr = rms(smoothErrors)
        let maxStep = zip(xs, xs.dropFirst()).map { abs($1 - $0) }.max()!
        let outlier = abs(a.trackBox(at: 5)!.midX - truth(5))
        let gap = stride(from: 8.25, through: 9.75, by: 0.25).map { abs(a.trackBox(at: $0)!.midX - truth($0)) }.max()!
        XCTAssertLessThan(smoothJitter, rawJitter / 10, "temblor")
        XCTAssertLessThan(smoothErr, rawErr, "error frente a la verdad")
        XCTAssertLessThan(maxStep, 0.02, "sin saltos (la verdad avanza hasta 0,016 por muestra)")
        XCTAssertLessThan(outlier, 0.03, "detección suelta quitada")
        XCTAssertLessThan(gap, 0.03, "hueco interpolado")
        // Evaluación entre muestras: interpolación lineal.
        let mid = try XCTUnwrap(a.trackBox(at: 12.125))
        XCTAssertEqual(mid.midX, (a.trackBox(at: 12)!.midX + a.trackBox(at: 12.25)!.midX) / 2, accuracy: 1e-12)
        print(String(format: "F7 encuadre: temblor (2.ª diferencia RMS) %.4f → %.4f; error RMS %.4f → %.4f; paso máx %.4f; detección suelta %.4f; hueco máx %.4f",
                     rawJitter, smoothJitter, rawErr, smoothErr, maxStep, outlier, gap))

        // Caché y ajuste manual.
        XCTAssertEqual(try JSONDecoder().decode(FramingAnalysis.self, from: JSONEncoder().encode(a)), a)
        let manual = FramingBox(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        XCTAssertEqual(MontageFraming(mode: .fixed, analysis: a).box(at: 3), a.fixed)
        XCTAssertEqual(MontageFraming(mode: .fixed, analysis: a, manualBox: manual).box(at: 3), manual)
        let auto = a.trackBox(at: 3)!
        let zoomed = try XCTUnwrap(MontageFraming(mode: .follow, analysis: a, followZoom: 2, followOffsetX: 0.05, followOffsetY: -0.02).box(at: 3))
        XCTAssertEqual(zoomed.width, auto.width / 2, accuracy: 1e-12)
        XCTAssertEqual(zoomed.midX, auto.midX + 0.05, accuracy: 1e-12)
        XCTAssertEqual(zoomed.midY, auto.midY - 0.02, accuracy: 1e-12)
        XCTAssertNil(MontageFraming(mode: .follow).box(at: 3), "sin análisis: fotograma entero")

        // Sin ninguna detección.
        let empty = GuitarFramer.analyze(samples: [PoseSample(time: 0, joints: [:])], frameWidth: 10, frameHeight: 10, fingerprint: "")
        XCTAssertNil(empty.fixed)
        XCTAssertTrue(empty.track.isEmpty)
    }
}
