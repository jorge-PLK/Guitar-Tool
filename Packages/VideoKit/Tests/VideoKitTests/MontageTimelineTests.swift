#if canImport(CoreGraphics)
import CoreGraphics
#endif
import XCTest
@testable import VideoKit

/// `MontageLayout`, `MontageTimeline` y `MontageAudioEnvelope` (mini-spec Fase 7, «Pruebas»).
final class MontageTimelineTests: XCTestCase {
    static let frame = CGSize(width: 320, height: 180)
    static let solos = [MontageSpan(start: 4, end: 5), MontageSpan(start: 7.5, end: 8.5)]

    /// Rítmica A entera, rítmica B parcial y solista C con dos solos (como la puerta).
    static func timeline(_ layout: MontageLayoutKind, canvas: MontageCanvas = .landscape, firstImageC: Double = 2) -> MontageTimeline {
        let parts = [
            MontageTimeline.Part(id: "A", name: "A", isSolo: false, presence: [MontageSpan(start: 2, end: 10)], firstImage: 2, frameSize: frame),
            MontageTimeline.Part(id: "B", name: "B", isSolo: false, presence: [MontageSpan(start: 2, end: 6)], firstImage: 2, frameSize: frame),
            MontageTimeline.Part(id: "C", name: "C", isSolo: true, presence: solos, firstImage: firstImageC, frameSize: frame)
        ]
        return MontageTimeline(canvas: canvas.size, layout: layout, span: MontageSpan(start: 2, end: 10), barDuration: 1, fadeIn: true,
                               fadeOut: true, parts: parts, hasCaption: true)
    }

    // MARK: Layout

    func testLayoutsInsideCanvasWithoutOverlap() {
        var checked = 0
        for canvas in [MontageCanvas.landscape, .portrait] {
            let size = canvas.size
            for kind in [MontageLayoutKind.side, .grid, .stack] {
                for n in 1...6 {
                    let r = MontageLayout.rects(kind, count: n, canvas: size)
                    XCTAssertEqual(r.count, n)
                    for (i, a) in r.enumerated() {
                        XCTAssertGreaterThanOrEqual(a.minX, MontageStyle.margin - 1e-9)
                        XCTAssertGreaterThanOrEqual(a.minY, MontageStyle.margin - 1e-9)
                        XCTAssertLessThanOrEqual(a.maxX, size.width - MontageStyle.margin + 1e-9)
                        XCTAssertLessThanOrEqual(a.maxY, size.height - MontageStyle.margin + 1e-9)
                        XCTAssertEqual(a.size.width, r[0].size.width, accuracy: 1e-9)
                        XCTAssertEqual(a.size.height, r[0].size.height, accuracy: 1e-9)
                        for b in r[(i + 1)...] {
                            let x = a.intersection(b)
                            XCTAssertTrue(x.isNull || x.width * x.height < 1e-6, "\(kind) n=\(n) solapan \(a) \(b)")
                        }
                    }
                    checked += 1
                }
            }
        }
        let c = MontageCanvas.landscape.size
        let inner = CGRect(x: 48, y: 48, width: 1920 - 96, height: 1080 - 96)
        // Tabla de la spec: rejilla 1 completo, 3 dos arriba y uno centrado abajo, 4 en 2 × 2; 2 apilados con la celda
        // del 2 × 2 y centrados en horizontal (Jorge, 17/11/2026).
        XCTAssertEqual(MontageLayout.rects(.grid, count: 1, canvas: c), [inner])
        let g4 = MontageLayout.rects(.grid, count: 4, canvas: c)
        XCTAssertEqual(Set(g4.map(\.minX)).count, 2)
        XCTAssertEqual(Set(g4.map(\.minY)).count, 2)
        let g2 = MontageLayout.rects(.grid, count: 2, canvas: c)
        let cellW = (1824 - 24) / 2.0, cellH = (984 - 24) / 2.0
        for (k, r) in g2.enumerated() {
            XCTAssertEqual(r.width, cellW, accuracy: 1e-9, "rejilla 2: ancho de celda del 2 × 2")
            XCTAssertEqual(r.height, cellH, accuracy: 1e-9, "rejilla 2: alto de celda del 2 × 2")
            XCTAssertEqual(r.size, g4[0].size)
            XCTAssertEqual(r.midX, c.width / 2, accuracy: 1e-9, "rejilla 2: centrado en horizontal")
            XCTAssertEqual(r.minY, g4[2 * k].minY, accuracy: 1e-9, "rejilla 2: filas del 2 × 2")
        }
        XCTAssertEqual(g2[1].minY - g2[0].maxY, MontageStyle.gap, accuracy: 1e-9, "rejilla 2: uno encima del otro")
        XCTAssertEqual(g2[0].minX, (1920 - cellW) / 2, accuracy: 1e-9, "rejilla 2: fondo a los lados")
        let g3 = MontageLayout.rects(.grid, count: 3, canvas: c)
        XCTAssertEqual(g3[0].minY, g3[1].minY)
        XCTAssertGreaterThan(g3[2].minY, g3[0].maxY)
        XCTAssertEqual(g3[2].midX, c.width / 2, accuracy: 1e-9)
        XCTAssertEqual(g3[2], g2[1], "rejilla 2 → 3: el de abajo no se mueve")
        XCTAssertEqual(MontageLayout.rects(.singleLandscape, count: 1, canvas: c), [CGRect(origin: .zero, size: c)])
        // Lado a lado: una fila; apilado: una columna; plano único: lienzo entero.
        XCTAssertEqual(Set(MontageLayout.rects(.side, count: 4, canvas: c).map(\.minY)).count, 1)
        XCTAssertEqual(Set(MontageLayout.rects(.stack, count: 4, canvas: MontageCanvas.portrait.size).map(\.minX)).count, 1)
        XCTAssertEqual(MontageLayout.rects(.single, count: 2, canvas: c), [CGRect(origin: .zero, size: c), CGRect(origin: .zero, size: c)])
        print("F7 layouts: \(checked) combinaciones (3 layouts × 6 recuadros × 2 lienzos) dentro del lienzo y sin solapes; rejilla 3 abajo centrado en x = \(g3[2].midX)")
    }

    // MARK: Timeline

    /// Muestreo cada 1 ms: ningún salto en rectángulo, opacidad, escala ni desenfoque mayor que la pendiente máxima de
    /// la ease-in-out cúbica (3 por unidad de progreso, en u = 0,5) sobre 0,5 s, en los cuatro layouts.
    func testTransitionsAreContinuous() {
        let d = MontageStyle.transition, step = 0.001
        let slope = 3 / d * step
        var report: [String] = []
        for kind in MontageLayoutKind.allCases {
            let canvas = kind.defaultCanvas
            let tl = Self.timeline(kind, canvas: canvas)
            var prev: [String: MontageBoxState] = [:]
            var worstRect = 0.0, worstOpacity = 0.0, worstScale = 0.0, worstBlur = 0.0
            var t = 1.5
            while t <= 10.5 {
                let st = tl.state(at: t)
                var now: [String: MontageBoxState] = [:]
                for b in st.boxes {
                    now[b.partID] = b
                    if let p = prev[b.partID] {
                        let dr = [b.rect.minX - p.rect.minX, b.rect.minY - p.rect.minY, b.rect.maxX - p.rect.maxX, b.rect.maxY - p.rect.maxY].map { abs(Double($0)) }.max()!
                        worstRect = max(worstRect, dr)
                        worstOpacity = max(worstOpacity, abs(b.opacity - p.opacity))
                        worstScale = max(worstScale, abs(b.scale - p.scale))
                        worstBlur = max(worstBlur, abs(b.blur - p.blur))
                    } else {
                        // Aparece: casi transparente, al 92 % y desenfocado.
                        XCTAssertLessThan(b.opacity, 1e-6, "\(kind) \(b.partID) aparece en \(t)")
                    }
                }
                for (id, p) in prev where now[id] == nil {
                    XCTAssertLessThan(p.opacity, 1e-6, "\(kind) \(id) desaparece en \(t) con opacidad \(p.opacity)")
                }
                prev = now
                t += step
            }
            let maxDim = Double(max(canvas.width, canvas.height))
            XCTAssertLessThanOrEqual(worstRect, slope * maxDim + 1e-6, "\(kind) rectángulo")
            XCTAssertLessThanOrEqual(worstOpacity, slope + 1e-9, "\(kind) opacidad")
            XCTAssertLessThanOrEqual(worstScale, slope * (1 - MontageStyle.entryScale) + 1e-9, "\(kind) escala")
            XCTAssertLessThanOrEqual(worstBlur, slope * MontageStyle.maxBlur + 1e-9, "\(kind) desenfoque")
            report.append(String(format: "%@ rect %.2f px/ms (tope %.2f), opacidad %.4f/ms (tope %.4f)", kind.rawValue, worstRect, slope * maxDim, worstOpacity, slope))
        }
        print("F7 continuidad: \(report.joined(separator: "; "))")
    }

    func testAnticipationEntranceExitAndRedistribution() {
        let tl = Self.timeline(.side)
        let c = 2, d = MontageStyle.transition
        // La entrada empieza 0,5 s antes del solo (4,0 → 3,5) y dura 0,5 s: a mitad en 3,75.
        XCTAssertEqual(MontageStyle.anticipation, 0.5)
        XCTAssertEqual(tl.visibility(part: c, at: 3.5), 0)
        XCTAssertGreaterThan(tl.visibility(part: c, at: 3.501), 0)
        XCTAssertEqual(tl.visibility(part: c, at: 3.75), 0.5, accuracy: 1e-12)
        let atNote = tl.visibility(part: c, at: 4.0)
        let s = tl.state(at: 4.0).boxes.first { $0.partID == "C" }!
        // Completa en el inicio de cada presencia (primera nota de los dos solos), en los cuatro layouts.
        for kind in MontageLayoutKind.allCases {
            let k = Self.timeline(kind, canvas: kind == .stack || kind == .single ? .portrait : .landscape)
            for solo in Self.solos {
                let b = k.state(at: solo.start).boxes.first { $0.partID == "C" }
                XCTAssertEqual(b?.opacity, 1, "\(kind) opacidad en \(solo.start)")
                XCTAssertEqual(b?.scale, 1, "\(kind) escala en \(solo.start)")
                XCTAssertEqual(b?.blur, 0, "\(kind) desenfoque en \(solo.start)")
            }
        }
        // Salida al acabar la presencia (5,0): mitad a 5,25, fuera a 5,5.
        XCTAssertEqual(tl.visibility(part: c, at: 5.0), 1)
        XCTAssertEqual(tl.visibility(part: c, at: 5.25), 0.5, accuracy: 1e-12)
        XCTAssertEqual(tl.visibility(part: c, at: 5.5), 0)
        // Redistribución terminada: 3 columnas a 4,6 s, 2 a 5,6 s, 1 a 6,6 s (B acabó a las 6,0).
        let canvas = MontageCanvas.landscape.size
        XCTAssertEqual(tl.state(at: 4.6).boxes.map(\.rect), MontageLayout.rects(.side, count: 3, canvas: canvas))
        XCTAssertEqual(tl.state(at: 5.6).boxes.map(\.rect), MontageLayout.rects(.side, count: 2, canvas: canvas))
        XCTAssertEqual(tl.state(at: 6.6).boxes.map(\.partID), ["A"])
        XCTAssertEqual(tl.state(at: 6.6).boxes[0].rect, MontageLayout.rects(.side, count: 1, canvas: canvas)[0])
        // Recorte con la proporción del recuadro (sin detección: centrado).
        for b in tl.state(at: 4.1).boxes {
            let aspect = b.crop.width * 320 / (b.crop.height * 180)
            XCTAssertEqual(aspect, Double(b.rect.width / b.rect.height), accuracy: 1e-9)
            XCTAssertEqual(b.crop.midX, 0.5, accuracy: 1e-9)
        }

        // Sin imagen tan pronto: la entrada empieza en el primer fotograma (3,9).
        let late = Self.timeline(.side, firstImageC: 3.9)
        XCTAssertEqual(late.visibility(part: c, at: 3.89), 0)
        XCTAssertEqual(late.visibility(part: c, at: 4.0), MontageTimeline.ease(0.1 / d), accuracy: 1e-12)
        XCTAssertEqual(late.visibility(part: c, at: 4.4), 1)
        // El segundo solo sí tiene imagen 0,5 s antes.
        XCTAssertEqual(late.visibility(part: c, at: 7.0), 0)
        XCTAssertEqual(late.visibility(part: c, at: 7.5), 1)

        // Plano único: fundido cruzado A ↔ C con la misma curva (suma 1) y los dos a pantalla completa.
        let single = Self.timeline(.single, canvas: .portrait)
        var worst = 0.0
        for k in 0...500 {
            let t = 3.5 + Double(k) * 0.001
            worst = max(worst, abs(single.visibility(part: 0, at: t) + single.visibility(part: c, at: t) - 1))
            worst = max(worst, abs(single.visibility(part: 0, at: t + 1.5) + single.visibility(part: c, at: t + 1.5) - 1))
        }
        XCTAssertLessThan(worst, 1e-12)
        let full = CGRect(origin: .zero, size: MontageCanvas.portrait.size)
        XCTAssertEqual(single.state(at: 3.75).boxes.map(\.rect), [full, full])
        XCTAssertEqual(single.state(at: 4.0).boxes.map(\.partID), ["C"], "en la primera nota solo la solista")
        XCTAssertEqual(single.state(at: 6.0).boxes.map(\.partID), ["A"])
        XCTAssertEqual(single.visibility(part: 1, at: 3), 0, "la otra rítmica no sale en el plano único")
        print(String(format: "F7 anticipación: solista a %.3f de opacidad y %.1f %% de escala en la primera nota; con primer fotograma a 3,9 s: %.3f; fundido cruzado |vA + vC − 1| máx %.1e",
                     atNote, s.scale * 100, late.visibility(part: c, at: 4.0), worst))
    }

    func testGlobalFadesCaptionAndAudioEnvelope() {
        let tl = Self.timeline(.side)
        XCTAssertEqual(tl.globalFade(at: 2), 0)
        XCTAssertEqual(tl.globalFade(at: 2.5), 0.5, accuracy: 1e-12)
        XCTAssertEqual(tl.globalFade(at: 3), 1)
        XCTAssertEqual(tl.globalFade(at: 9.25), 0.75, accuracy: 1e-12)
        XCTAssertEqual(tl.globalFade(at: 10), 0)
        XCTAssertEqual(tl.captionOpacity(at: 2), 0)
        XCTAssertEqual(tl.captionOpacity(at: 2.25), 0.5, accuracy: 1e-12)
        XCTAssertEqual(tl.captionOpacity(at: 4), 1)
        XCTAssertEqual(tl.captionOpacity(at: 6.75), 0.5, accuracy: 1e-12)
        XCTAssertEqual(tl.captionOpacity(at: 7.01), 0)

        // Audio: la toma entra con 80 ms dentro de su presencia; la guitarra original, con el fundido inverso.
        let url = URL(fileURLWithPath: "/dev/null")
        let take = MontageAudioTrack(url: url, songStart: 2, volume: 1, gate: .during(Self.solos))
        let orig = MontageAudioTrack(url: url, songStart: 2, volume: 1, gate: .except(Self.solos))
        let f = MontageStyle.audioFade
        for (t, want) in [(4.0, 0.0), (4.0 + f / 2, 0.5), (4.0 + f, 1.0), (4.5, 1.0), (5.0 - f / 2, 0.5), (5.0, 0.0), (6.0, 0.0)] {
            XCTAssertEqual(MontageAudioEnvelope.gain(take, at: t, timeline: tl), want, accuracy: 1e-12, "toma en \(t)")
            XCTAssertEqual(MontageAudioEnvelope.gain(orig, at: t, timeline: tl), 1 - want, accuracy: 1e-12, "original en \(t)")
        }
        let bp = MontageAudioEnvelope.breakpoints(take, timeline: tl, segment: 0)
        for x in [2.0, 3.0, 4.0, 4.0 + f, 5.0 - f, 5.0, 7.5, 9.0, 10.0] {
            XCTAssertTrue(bp.contains { abs($0 - x) < 1e-12 }, "vértice \(x)")
        }
        // El fundido global también va en el audio.
        let stem = MontageAudioTrack(url: url, songStart: 0, volume: 0.8, gate: .always)
        XCTAssertEqual(MontageAudioEnvelope.gain(stem, at: 2.5, timeline: tl), 0.4, accuracy: 1e-12)
    }

    /// «Cortar huecos sin tomas»: segmentos, correspondencia de tiempos y fundidos por segmento.
    func testSegmentsTimeMapAndSegmentFades() {
        let a = [MontageSpan(start: 2, end: 5.5)], b = [MontageSpan(start: 7, end: 9.5)], c = [MontageSpan(start: 9, end: 12)]
        // Sin cortar: un segmento, el tramo de siempre.
        XCTAssertEqual(MontagePlan.segments(presences: [a, b, c], cutGaps: false), [MontageSpan(start: 2, end: 12)])
        // Cortando: cada tramo empieza 0,5 s antes si hay imagen (A no tiene antes de 2; B sí); B y C se juntan.
        XCTAssertEqual(MontagePlan.segments(presences: [a, b, c], imageStarts: [2, 2, 2], cutGaps: true),
                       [MontageSpan(start: 2, end: 5.5), MontageSpan(start: 6.5, end: 12)])
        // Sin datos de imagen: la anticipación entera, sin bajar de 0.
        XCTAssertEqual(MontagePlan.segments(presences: [[MontageSpan(start: 0.2, end: 1)], b], cutGaps: true),
                       [MontageSpan(start: 0, end: 1), MontageSpan(start: 6.5, end: 9.5)])
        XCTAssertEqual(MontagePlan.segments(presences: [[], []], cutGaps: true), [])

        let map = MontageTimeMap(segments: [MontageSpan(start: 2, end: 5.5), MontageSpan(start: 6.5, end: 9.5)])
        XCTAssertEqual(map.duration, 6.5)
        XCTAssertEqual(map.songTime(videoTime: 0), 2)
        XCTAssertEqual(map.songTime(videoTime: 3.4), 5.4, accuracy: 1e-12)
        XCTAssertEqual(map.songTime(videoTime: 3.5), 6.5)
        XCTAssertEqual(map.songTime(videoTime: 6.5), 9.5)
        XCTAssertEqual(map.videoTime(songTime: 4), 2)
        XCTAssertEqual(map.videoTime(songTime: 6), 3.5, "en el hueco: inicio del segmento siguiente")
        XCTAssertEqual(map.videoTime(songTime: 7), 4)
        XCTAssertEqual(map.videoTime(songTime: 1), 0)
        XCTAssertEqual(map.videoTime(songTime: 20), 6.5)
        for v in stride(from: 0.0, to: 6.5, by: 0.1) { XCTAssertEqual(map.videoTime(songTime: map.songTime(videoTime: v)), v, accuracy: 1e-9) }

        // Fundidos por segmento: el primero entra (no empieza en 0); en el corte, salida y entrada; el último no
        // sale si acaba con el tema. Un segmento de menos de dos compases los acorta a la mitad.
        let parts = [MontageTimeline.Part(id: "A", name: "A", isSolo: false, presence: [MontageSpan(start: 2, end: 9.5)], firstImage: 2, frameSize: Self.frame)]
        let tl = MontageTimeline(canvas: MontageCanvas.landscape.size, layout: .side, span: MontageSpan(start: 2, end: 9.5),
                                 segments: map.segments, barDuration: 1, fadeIn: true, fadeOut: false, parts: parts, hasCaption: true)
        XCTAssertEqual(tl.globalFade(at: 2.5), 0.5, accuracy: 1e-12)
        XCTAssertEqual(tl.globalFade(at: 4), 1)
        XCTAssertEqual(tl.globalFade(at: 5), 0.5, accuracy: 1e-12)
        XCTAssertEqual(tl.globalFade(at: 6), 0, "hueco")
        XCTAssertEqual(tl.globalFade(at: 7), 0.5, accuracy: 1e-12)
        XCTAssertEqual(tl.globalFade(at: 9.4), 1, "el último acaba con el tema")
        // El rótulo cuenta tiempo de vídeo: 5 s de vídeo = 4,5 s del tema en el segundo segmento (6,5 + 1,5 = 8,0).
        XCTAssertEqual(tl.captionOpacity(at: 7.75), 0.5, accuracy: 1e-12)
        let short = MontageTimeline(canvas: MontageCanvas.landscape.size, layout: .side, span: MontageSpan(start: 2, end: 9.5),
                                    segments: [MontageSpan(start: 2, end: 3.2), MontageSpan(start: 6.5, end: 9.5)], barDuration: 1,
                                    fadeIn: true, fadeOut: true, parts: parts)
        XCTAssertEqual(short.fadeDuration(segment: 0), 0.6, accuracy: 1e-12)
        XCTAssertEqual(short.globalFade(at: 2.3), 0.5, accuracy: 1e-12)
        XCTAssertEqual(short.globalFade(at: 2.6), 1, accuracy: 1e-12)
        XCTAssertEqual(short.globalFade(at: 2.9), 0.5, accuracy: 1e-12)
        // Audio con los mismos fundidos por segmento.
        let stem = MontageAudioTrack(url: URL(fileURLWithPath: "/dev/null"), songStart: 0, volume: 1, gate: .always)
        XCTAssertEqual(MontageAudioEnvelope.gain(stem, at: 7, timeline: tl), 0.5, accuracy: 1e-12)
        XCTAssertTrue(MontageAudioEnvelope.breakpoints(stem, timeline: tl, segment: 1).contains(7.5))
    }

    func testPlanRulesAndCodable() throws {
        let take = MontageSpan(start: 3, end: 9)
        XCTAssertEqual(MontagePlan.presence(take: take, isSolo: false, soloSections: Self.solos), [take])
        XCTAssertEqual(MontagePlan.presence(take: take, isSolo: true, soloSections: Self.solos),
                       [MontageSpan(start: 4, end: 5), MontageSpan(start: 7.5, end: 8.5)])
        XCTAssertEqual(MontagePlan.presence(take: take, isSolo: true, soloSections: []), [], "solista sin secciones de solo: vacía")
        XCTAssertEqual(MontagePlan.presence(take: MontageSpan(start: 4.5, end: 8), isSolo: true, soloSections: Self.solos),
                       [MontageSpan(start: 4.5, end: 5), MontageSpan(start: 7.5, end: 8)])
        XCTAssertEqual(MontagePlan.videoSpan(presences: [[MontageSpan(start: 3, end: 6)], [MontageSpan(start: 1, end: 2)], []]),
                       MontageSpan(start: 1, end: 6))
        XCTAssertEqual(MontagePlan.barDuration(bpm: nil, beatsPerBar: nil), 2)
        XCTAssertEqual(MontagePlan.barDuration(bpm: 90, beatsPerBar: 3), 2)
        let fades = MontagePlan.globalFades(span: MontageSpan(start: 0, end: 30), songDuration: 200)
        XCTAssertFalse(fades.fadeIn)
        XCTAssertTrue(fades.fadeOut)

        let plan = MontagePlan(canvas: .portrait, fps: 30, layout: .single, span: MontageSpan(start: 1, end: 6), barDuration: 2, fadeIn: true,
                               fadeOut: false, parts: [
                                   MontagePart(id: "p", name: "Rítmica", isSolo: false, presence: [MontageSpan(start: 1, end: 6)],
                                               video: MontagePartVideo(url: URL(fileURLWithPath: "/tmp/v.mov"), videoOffset: 0.033,
                                                                       punches: [PreviewPunch(start: 2, end: 3, videoURL: nil, videoOffset: 0)],
                                                                       take: MontageSpan(start: 1, end: 6)),
                                               framing: MontageFraming(mode: .follow, followZoom: 1.5))
                               ], singleRhythmPartID: "p",
                               audio: [MontageAudioTrack(url: URL(fileURLWithPath: "/tmp/a.wav"), songStart: 0, volume: 1, gate: .except([MontageSpan(start: 1, end: 6)]))],
                               caption: MontageCaption(title: "T", artist: "A"))
        let data = try JSONEncoder().encode(plan)
        XCTAssertEqual(try JSONDecoder().decode(MontagePlan.self, from: data), plan)
    }
}
