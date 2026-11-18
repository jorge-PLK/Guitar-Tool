import CoreGraphics
import XCTest
@testable import VideoKit

/// Plano único (decisiones de Jorge del 17/11/2026): una guitarra solo se ve donde tiene toma con imagen. Un corte a
/// una parte sin toma en ese instante cae en el automático; el automático nunca elige una parte sin toma; si nadie
/// tiene toma, la última parte sigue con fundido a negro. `MontagePlan.singleCutCandidates` dice qué partes puede
/// mandar un corte (el selector del carril «Plano»).
final class MontageSingleCoverageTests: XCTestCase {
    static let frame = CGSize(width: 1920, height: 1080)
    static let step = 0.001
    /// Lo que dura la salida tras quedarse sin imagen: la transición (la ease-in-out llega a 0 justo en 0,5 s).
    static let fall = MontageStyle.transition

    static func timeline(_ parts: [MontageTimeline.Part], span: MontageSpan, rhythm: String? = nil, cuts: [MontageCut] = []) -> MontageTimeline {
        MontageTimeline(canvas: MontageCanvas.portrait.size, layout: .single, span: span, barDuration: 1, fadeIn: false, fadeOut: false,
                        parts: parts, singleRhythmPartID: rhythm, singleCuts: cuts)
    }

    static func part(_ id: String, solo: Bool = false, presence: [MontageSpan], images: [MontageSpan]) -> MontageTimeline.Part {
        MontageTimeline.Part(id: id, name: id, isSolo: solo, presence: presence, firstImage: images.first?.start, frameSize: frame, images: images)
    }

    static func opacity(_ tl: MontageTimeline, _ id: String, _ t: Double) -> Double {
        tl.state(at: t).boxes.first { $0.partID == id }?.opacity ?? 0
    }

    /// Mayor retraso (s) entre el final de la imagen de una parte y un instante en que aún se ve, recorriendo
    /// `span` cada milisegundo. Con la regla bien aplicada, como mucho la salida (`fall`).
    static func worstVisibleWithoutImage(_ tl: MontageTimeline, images: [String: [MontageSpan]], span: MontageSpan) -> Double {
        var worst = 0.0, t = span.start
        while t < span.end {
            for b in tl.state(at: t).boxes where b.opacity > 0 && b.brightness > 0 {
                let list = images[b.partID] ?? []
                guard !list.contains(where: { $0.contains(t) }) else { continue }
                let lastEnd = list.map(\.end).filter { $0 <= t }.max() ?? -.infinity
                worst = max(worst, t - lastEnd)
            }
            t += step
        }
        return worst
    }

    /// Rítmica A con imagen en 0–10; B (no solista) con toma en 2–6. Cortes: 1 → B (aún sin toma), 3,5 → automático,
    /// 4 → B (su toma acaba a mitad del tramo), 8 → B (sin toma).
    func testCutToPartWithoutTakeFallsBackToAutomatic() {
        let a = Self.part("A", presence: [MontageSpan(start: 0, end: 10)], images: [MontageSpan(start: 0, end: 10)])
        let b = Self.part("B", presence: [MontageSpan(start: 2, end: 6)], images: [MontageSpan(start: 2, end: 6)])
        let span = MontageSpan(start: 0, end: 10)
        let cuts = [MontageCut(time: 1, partID: "B"), MontageCut(time: 3.5, partID: nil), MontageCut(time: 4, partID: "B"),
                    MontageCut(time: 8, partID: "B")]
        let tl = Self.timeline([a, b], span: span, rhythm: "A", cuts: cuts)
        // Corte a 1 s: B no tiene toma hasta 2 s → A entero hasta 2; B entra en su primera imagen (completo a 2,5).
        XCTAssertEqual(Self.opacity(tl, "A", 1.9), 1, accuracy: 1e-12)
        XCTAssertEqual(Self.opacity(tl, "B", 1.999), 0, accuracy: 1e-12)
        XCTAssertEqual(Self.opacity(tl, "B", 2.25), 0.5, accuracy: 1e-12)
        XCTAssertEqual(Self.opacity(tl, "B", 2.5), 1, accuracy: 1e-12)
        // Corte a 4 s → B: su toma acaba a 6 s, dentro del tramo (que llega a 7,5) → fundido cruzado a A en 6–6,5.
        XCTAssertEqual(Self.opacity(tl, "B", 5.999), 1, accuracy: 1e-12)
        XCTAssertEqual(Self.opacity(tl, "B", 6.25), 0.5, accuracy: 1e-12)
        XCTAssertEqual(Self.opacity(tl, "A", 6.25), 0.5, accuracy: 1e-12)
        XCTAssertEqual(Self.opacity(tl, "A", 6.5), 1, accuracy: 1e-12)
        // Sin fundido a negro: B sale en cuanto acaba su imagen (lo cubre A).
        XCTAssertEqual(tl.imageBrightness(part: 1, at: 6.25), 1, accuracy: 1e-12)
        // Corte a 8 s → B, que no tiene toma: automático (A) hasta el final, B nunca.
        var t = 6.5
        while t < 10 { XCTAssertEqual(Self.opacity(tl, "B", t), 0, "B sin toma en \(t)"); t += Self.step }
        let worst = Self.worstVisibleWithoutImage(tl, images: ["A": a.images!, "B": b.images!], span: span)
        print(String(format: "F7 cobertura (cortes): una parte sin toma se ve como mucho %.3f s tras su última imagen (tope %.3f s, la salida)",
                     worst, Self.fall))
        XCTAssertLessThanOrEqual(worst, Self.fall + 1e-9)
    }

    /// Rítmica elegida A con audio en 0–10 pero vídeo solo hasta 5 s; B (no solista) con toma en 0–10; solista C con
    /// solo en 7–8 y vídeo solo hasta 6 s. El automático pasa a B a los 5 s y no muestra a C en su solo.
    func testAutomaticNeverPicksPartWithoutTake() {
        let a = Self.part("A", presence: [MontageSpan(start: 0, end: 10)], images: [MontageSpan(start: 0, end: 5)])
        let b = Self.part("B", presence: [MontageSpan(start: 0, end: 10)], images: [MontageSpan(start: 0, end: 10)])
        let c = Self.part("C", solo: true, presence: [MontageSpan(start: 3, end: 4), MontageSpan(start: 7, end: 8)],
                          images: [MontageSpan(start: 0, end: 6)])
        let span = MontageSpan(start: 0, end: 10)
        let tl = Self.timeline([a, b, c], span: span, rhythm: "A")
        let expect: [(Double, String)] = [(1, "A"), (3.5, "C"), (4.6, "A"), (5.6, "B"), (7.5, "B"), (9.9, "B")]
        for (t, id) in expect {
            let st = tl.state(at: t)
            XCTAssertEqual(st.boxes.filter { $0.opacity > 1 - 1e-9 }.map(\.partID), [id], "t = \(t): \(st.boxes.map { "\($0.partID) \($0.opacity)" })")
        }
        // Cambio a B en vez de fundir a negro: A sale en 5–5,5 sin oscurecerse.
        XCTAssertEqual(Self.opacity(tl, "A", 5.25), 0.5, accuracy: 1e-12)
        XCTAssertEqual(Self.opacity(tl, "B", 5.25), 0.5, accuracy: 1e-12)
        XCTAssertEqual(tl.imageBrightness(part: 0, at: 5.4), 1, accuracy: 1e-12)
        // Las opacidades suman 1 tras la entrada inicial (0–0,5 s): nunca vacío ni dos enteros.
        var worstSum = 0.0, t = Self.fall
        while t < 10 { worstSum = max(worstSum, abs(tl.state(at: t).boxes.reduce(0) { $0 + $1.opacity } - 1)); t += Self.step }
        XCTAssertLessThan(worstSum, 1e-9, "suma de opacidades")
        let worst = Self.worstVisibleWithoutImage(tl, images: ["A": a.images!, "B": b.images!, "C": c.images!], span: span)
        print(String(format: "F7 cobertura (automático): sin toma se ve como mucho %.3f s (tope %.3f s); |Σ opacidad − 1| máx %.1e",
                     worst, Self.fall, worstSum))
        XCTAssertLessThanOrEqual(worst, Self.fall + 1e-9)
    }

    /// Nadie con toma tras los 5 s: A sigue entero y su imagen funde a negro en 5–5,5 (lineal) y queda en negro.
    func testNobodyCoversKeepsLastPartFadingToBlack() {
        let a = Self.part("A", presence: [MontageSpan(start: 0, end: 10)], images: [MontageSpan(start: 0, end: 5)])
        let tl = Self.timeline([a], span: MontageSpan(start: 0, end: 10))
        for t in [4.999, 5.25, 5.5, 7, 9.999] { XCTAssertEqual(Self.opacity(tl, "A", t), 1, accuracy: 1e-12, "A en pantalla en \(t)") }
        XCTAssertEqual(tl.imageBrightness(part: 0, at: 4.999), 1, accuracy: 1e-12)
        XCTAssertEqual(tl.imageBrightness(part: 0, at: 5.25), 0.5, accuracy: 1e-12)
        XCTAssertEqual(tl.imageBrightness(part: 0, at: 5.5), 0, accuracy: 1e-12)
        XCTAssertEqual(tl.state(at: 9.999).boxes.first?.brightness ?? -1, 0, accuracy: 1e-12)
        // Mismo fundido en un layout de varios recuadros.
        let side = MontageTimeline(canvas: MontageCanvas.landscape.size, layout: .side, span: MontageSpan(start: 0, end: 10), barDuration: 1,
                                   fadeIn: false, fadeOut: false, parts: [a])
        XCTAssertEqual(side.state(at: 5.25).boxes.first?.brightness ?? -1, 0.5, accuracy: 1e-12)
        XCTAssertEqual(side.state(at: 8).boxes.first?.brightness ?? -1, 0, accuracy: 1e-12)
        // Toma que acaba con su recuadro (resto de redondeo < `endFadeTolerance`): sin fundido a negro, solo la salida.
        let flush = Self.part("F", presence: [MontageSpan(start: 0, end: 5.0073)], images: [MontageSpan(start: 0, end: 5)])
        let tf = Self.timeline([flush], span: MontageSpan(start: 0, end: 5.0073))
        XCTAssertEqual(tf.imageBrightness(part: 0, at: 5.3), 1, accuracy: 1e-12)
    }

    /// Color del carril «Plano»: lo que de verdad se ve. A con toma 0–10, B con toma 2–6; cortes 4 → B (su toma acaba
    /// a 6, dentro del tramo) y 8 → B (sin toma): A, B desde 3,5 (empieza su entrada) hasta 6, A hasta el final. Una
    /// toma con imagen solo en 0–5 (punch) y audio hasta 10: la parte sigue, en negro, de 5 a 10.
    func testSingleShotsPaintWhatIsSeen() {
        let url = URL(fileURLWithPath: "/dev/null")
        func part(_ id: String, _ take: MontageSpan) -> MontagePart {
            MontagePart(id: id, name: id, isSolo: false, presence: [take], video: MontagePartVideo(url: url, videoOffset: 0, take: take))
        }
        let span = MontageSpan(start: 0, end: 10)
        let plan = MontagePlan(canvas: .portrait, fps: 30, layout: .single, span: span, barDuration: 2, fadeIn: false, fadeOut: false,
                               parts: [part("A", span), part("B", MontageSpan(start: 2, end: 6))], singleRhythmPartID: "A",
                               singleCuts: [MontageCut(time: 4, partID: "B"), MontageCut(time: 8, partID: "B")])
        XCTAssertEqual(plan.singleShots(), [
            MontageShot(span: MontageSpan(start: 0, end: 3.5), partID: "A"),
            MontageShot(span: MontageSpan(start: 3.5, end: 6), partID: "B"),
            MontageShot(span: MontageSpan(start: 6, end: 10), partID: "A")
        ])
        let punchOnly = MontagePart(id: "C", name: "C", isSolo: false, presence: [span],
                                    video: MontagePartVideo(url: nil, videoOffset: 0,
                                                            punches: [PreviewPunch(start: 0, end: 5, videoURL: url, videoOffset: 0)], take: span))
        let dark = MontagePlan(canvas: .portrait, fps: 30, layout: .single, span: span, barDuration: 2, fadeIn: false, fadeOut: false,
                               parts: [punchOnly])
        XCTAssertEqual(dark.singleShots(), [
            MontageShot(span: MontageSpan(start: 0, end: 5), partID: "C"),
            MontageShot(span: MontageSpan(start: 5, end: 10), partID: "C", black: true)
        ])
    }

    /// Selector del carril «Plano»: A con vídeo en toda su toma (0–10), B sin vídeo base y un punch con vídeo en 3–4
    /// (otro sin vídeo en 5–6), C sin vídeo, D con toma en 6–9.
    func testSingleCutCandidates() {
        let url = URL(fileURLWithPath: "/dev/null")
        let take = MontageSpan(start: 0, end: 10)
        let parts = [
            MontagePart(id: "A", name: "A", isSolo: false, presence: [take], video: MontagePartVideo(url: url, videoOffset: 0, take: take)),
            MontagePart(id: "B", name: "B", isSolo: false, presence: [take],
                        video: MontagePartVideo(url: nil, videoOffset: 0, punches: [
                            PreviewPunch(start: 3, end: 4, videoURL: url, videoOffset: 0),
                            PreviewPunch(start: 5, end: 6, videoURL: nil, videoOffset: 0)
                        ], take: take)),
            MontagePart(id: "C", name: "C", isSolo: false, presence: [take], video: nil),
            MontagePart(id: "D", name: "D", isSolo: true, presence: [], video: MontagePartVideo(url: url, videoOffset: 0,
                                                                                                take: MontageSpan(start: 6, end: 9)))
        ]
        let plan = MontagePlan(canvas: .portrait, fps: 30, layout: .single, span: take, barDuration: 2, fadeIn: false, fadeOut: false, parts: parts)
        XCTAssertEqual(plan.singleCutCandidates(at: 3.5), ["A", "B"])
        XCTAssertEqual(plan.singleCutCandidates(at: 5.5), ["A"])
        XCTAssertEqual(plan.singleCutCandidates(at: 6), ["A", "D"])
        XCTAssertEqual(plan.singleCutCandidates(at: 9), ["A"], "el final de la toma ya no la cubre")
        XCTAssertEqual(plan.singleCutCandidates(at: 10), [])
        XCTAssertEqual(parts[1].video?.coverage, [MontageSpan(start: 3, end: 4)])
    }
}
