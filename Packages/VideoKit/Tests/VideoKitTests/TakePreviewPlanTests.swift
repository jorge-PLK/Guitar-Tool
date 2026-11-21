import Foundation
import XCTest
@testable import VideoKit

/// `TakePreviewPlan` (puro): mismos casos en el Mac y en Windows (plan, «Fase 7c», paso 7, parte 7.9). Los números del
/// primero son los de `VideoFileTests.testPreviewUsesPunchInsideItsSpanAndBaseOutside` (vídeos de 9,9–13,3, 10,5–12,1 y
/// 11,2–12,5 s).
final class TakePreviewPlanTests: XCTestCase {
    func testPunchesOverBaseWithOwnOffsets() {
        let offset = 0.0333
        let plan = TakePreviewPlan.pieces(songStart: 10, duration: 3, base: 9.9...13.3, baseOffset: offset, punches: [
            .init(start: 10.8, end: 11.8, available: 10.5...12.1, offset: 0.02),
            .init(start: 11.5, end: 12.2, available: 11.2...12.5, offset: -0.01)
        ])
        XCTAssertEqual(plan.map(\.source), [.base, .punch(0), .punch(1), .base])
        let expect: [(Double, Double, Double)] = [(0, 0.8, 10 + offset), (0.8, 1.5, 10.8 + 0.02), (1.5, 2.2, 11.5 - 0.01), (2.2, 3.0, 12.2 + offset)]
        for (p, e) in zip(plan, expect) {
            XCTAssertEqual(p.start, e.0, accuracy: 1e-9)
            XCTAssertEqual(p.end, e.1, accuracy: 1e-9)
            XCTAssertEqual(p.sourceStart, e.2, accuracy: 1e-9)
        }
    }

    /// Recortes a lo que hay en el fichero, punch sin vídeo (hueco), punch fuera de la toma y sin base.
    func testClippingGapsAndMissingFiles() {
        // Base disponible solo desde 10,5 y hasta 12,0; punch 0 sin vídeo; punch 1 fuera de la toma.
        let a = TakePreviewPlan.pieces(songStart: 10, duration: 3, base: 10.5...12.0, baseOffset: 0, punches: [
            .init(start: 11, end: 11.5, available: nil, offset: 0),
            .init(start: 14, end: 15, available: 14...15, offset: 0)
        ])
        XCTAssertEqual(a.map(\.source), [.base, .base])
        XCTAssertEqual(a.map(\.start), [0.5, 1.5])
        XCTAssertEqual(a.map(\.end), [1.0, 2.0])
        XCTAssertEqual(a.map(\.sourceStart), [10.5, 11.5])
        // Sin base: solo el punch, desplazado por su desfase positivo (imagen tarde).
        let b = TakePreviewPlan.pieces(songStart: 0, duration: 2, base: nil, baseOffset: 0, punches: [
            .init(start: 0.5, end: 1.5, available: 0...2, offset: 0.25)
        ])
        XCTAssertEqual(b, [PreviewPiece(start: 0.5, end: 1.5, source: .punch(0), sourceStart: 0.75)])
        // Desfase que deja la base sin imagen al principio.
        let c = TakePreviewPlan.pieces(songStart: 0, duration: 1, base: 0...1, baseOffset: -0.2, punches: [])
        XCTAssertEqual(c, [PreviewPiece(start: 0.2, end: 1.0, source: .base, sourceStart: 0)])
    }
}
