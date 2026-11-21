#if os(Windows)
import Foundation
import XCTest
@testable import VideoKit

/// Media Foundation en Windows (plan, «Fase 7c», paso 7, parte 7.2): búfer de píxeles, codificadores, cámaras sin
/// dispositivo y contrato de las marcas QPC.
final class MediaFoundationWindowsTests: XCTestCase {
    /// Forma del búfer y color: BGRA → NV12 → BGRA (shim) con error ≤ 2 niveles en colores planos; blanco Y = 235 y
    /// negro Y = 16 (rango limitado); `pixel` de NV12 coincide con la conversión del shim.
    func testFramePixelBufferLayoutAndColorRoundTrip() {
        let b = FramePixelBuffer(pixelFormat: .bgra, width: 33, height: 17)
        XCTAssertEqual(b.bytesPerRow, 192)
        XCTAssertEqual(b.byteCount, 192 * 17)
        XCTAssertEqual(Int(bitPattern: b.baseAddress) % FramePixelBuffer.alignment, 0)
        let n = FramePixelBuffer(pixelFormat: .nv12, width: 33, height: 17)
        XCTAssertEqual(n.bytesPerRow, 64)
        XCTAssertEqual(n.planeHeight(1), 9)
        XCTAssertEqual(n.byteCount, 64 * (17 + 9))
        XCTAssertEqual(n.planeBaseAddress(1) - n.baseAddress, 64 * 17)
        var worst = 0
        for c: (UInt8, UInt8, UInt8) in [(255, 255, 255), (0, 0, 0), (0, 0, 234), (40, 200, 40), (200, 60, 10), (128, 128, 128)] {
            b.fill(b: c.0, g: c.1, r: c.2)
            let yuv = b.converted(to: .nv12)
            let back = yuv.converted(to: .bgra)
            for (x, y) in [(0, 0), (32, 16), (17, 9)] {
                let p = back.pixel(x: x, y: y), q = yuv.pixel(x: x, y: y)
                worst = max(worst, abs(Int(p.b) - Int(c.0)), abs(Int(p.g) - Int(c.1)), abs(Int(p.r) - Int(c.2)))
                XCTAssertLessThanOrEqual(max(abs(Int(p.b) - Int(q.b)), abs(Int(p.g) - Int(q.g)), abs(Int(p.r) - Int(q.r))), 1)
            }
            if c == (255, 255, 255) { XCTAssertEqual(yuv.baseAddress.load(as: UInt8.self), 235) }
            if c == (0, 0, 0) { XCTAssertEqual(yuv.baseAddress.load(as: UInt8.self), 16) }
        }
        let filled = FramePixelBuffer(pixelFormat: .nv12, width: 8, height: 8)
        filled.fill(b: 0, g: 0, r: 234)
        let red = filled.pixel(x: 3, y: 5)
        print("7.2 FramePixelBuffer: máx error BGRA→NV12→BGRA \(worst) niveles; rojo 234 en NV12 → \(red)")
        XCTAssertLessThanOrEqual(worst, 2)
        XCTAssertLessThanOrEqual(abs(Int(red.r) - 234), 2)
    }

    /// Hay H.264 (el codificador de software de Windows) y HEVC se detecta por enumeración, no se supone.
    func testEncodersListedAndHEVCDetected() {
        let all = MediaFoundationEncoders.all()
        for e in all { print("7.2 codificador: \(e.codec.rawValue) \(e.isHardware ? "hardware" : "software") «\(e.name)»") }
        XCTAssertFalse(MediaFoundationEncoders.available(.h264).isEmpty)
        XCTAssertEqual(MediaFoundationEncoders.hasHEVC, !MediaFoundationEncoders.available(.hevc).isEmpty)
        XCTAssertTrue(all.allSatisfy { !$0.name.isEmpty })
    }

    /// Sin cámara (la VM): enumeración sin error, una cámara inexistente da `notFound`, el aviso de cambios se registra y
    /// se quita. Con cámara (un PC), cada una tiene identificador y formatos.
    func testCamerasEnumerateWithoutDevice() async throws {
        let provider = MediaFoundationCameraProvider()
        let cams = provider.cameras()
        print("7.2 cámaras: \(cams.count) \(cams.map { "\($0.name): \($0.formats.count) formatos" }); permiso \(await MediaFoundationCameraProvider.ensureAccess())")
        XCTAssertEqual(provider.defaultCamera()?.id, cams.first?.id)
        for c in cams {
            XCTAssertFalse(c.id.isEmpty)
            XCTAssertTrue(c.formats.allSatisfy { $0.index >= 0 && $0.width > 0 && $0.height > 0 })
        }
        provider.setChangeHandler { }
        provider.setChangeHandler(nil)
        XCTAssertThrowsError(try MediaFoundationCameraCapture(cameraID: "no-existe")) { e in
            XCTAssertEqual(e as? CameraError, .notFound("no-existe"))
        }
    }

    /// Contrato de las marcas: `MFGetSystemTime` (QPC en 100 ns, la escala de `MFSampleExtension_DeviceTimestamp`)
    /// pasado a ticks de QPC y a segundos de `HostClock` cae entre dos lecturas de `HostClock` (error < 0,1 ms).
    func testSystemTimeConvertsToHostClock() {
        var worst = 0.0
        for _ in 0..<100 {
            let a = HostClock.nowSeconds
            let s = MF.systemTime()
            let b = HostClock.nowSeconds
            let h = MediaFoundationCameraCapture.hostSeconds(qpcHundredNanoseconds: s)
            worst = max(worst, max(a - h, h - b, 0))
        }
        print(String(format: "7.2 QPC: frecuencia %llu Hz, máx desvío de MFGetSystemTime → HostClock fuera de [antes, después] %.3f µs",
                     MediaFoundationCameraCapture.frequency, worst * 1e6))
        XCTAssertLessThan(worst, 1e-4)
    }
}
#endif
