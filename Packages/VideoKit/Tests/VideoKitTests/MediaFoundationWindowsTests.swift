#if os(Windows)
import Foundation
import WinSDK
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

    /// Diagnóstico W-2 (con cámara conectada): tiempos de enumerar, resolver por id, permiso y abrir; ids estables.
    func testCameraOpenTimingAndIdsDiagnostic() async throws {
        func ms(_ b: () -> Void) -> Double { let t = Date(); b(); return Date().timeIntervalSince(t) * 1000 }
        let provider = MediaFoundationCameraProvider()
        var cams: [CameraDevice] = []
        let tList = ms { cams = provider.cameras() }
        let tList2 = ms { cams = provider.cameras() }
        print("W2 lista: \(cams.count) cámaras, \(tList) ms (2ª \(tList2) ms)")
        guard let cam = cams.first else { return }
        print("W2 id=\(cam.id) nombre=\(cam.name) formatos=\(cam.formats.count)")
        var found: CameraDevice?
        let tById = ms { found = provider.camera(id: cam.id) }
        _ = tById
        print("W2 camera(id:) \(found != nil) en \(tById) ms")
        XCTAssertNotNil(found)
        // Regresión W-2: tras la primera descripción (abre el dispositivo, ~0,5 s) enumerar, resolver por id y comprobar
        // presencia no vuelven a abrirlo; Grabar lo hace en cada instantánea y sondeo, en el actor principal.
        XCTAssertLessThan(tList2, 150, "cameras() repetido reabre la cámara")
        XCTAssertLessThan(tById, 150, "camera(id:) reabre la cámara")
        var present = false
        let tHas = ms { present = provider.hasCamera(id: cam.id) }
        print("W2 hasCamera \(present) en \(tHas) ms")
        XCTAssertTrue(present)
        XCTAssertLessThan(tHas, 150)
        XCTAssertFalse(provider.hasCamera(id: "no-existe"))
        XCTAssertNil(provider.camera(id: "no-existe"))
        let t0 = Date()
        let access = await MediaFoundationCameraProvider.ensureAccess()
        print("W2 ensureAccess \(access) en \(Date().timeIntervalSince(t0) * 1000) ms")
        let t1 = Date()
        let cap = try MediaFoundationCameraCapture(cameraID: cam.id)
        let t2 = Date()
        let n = NSLock(); nonisolated(unsafe) var frames = 0
        let f = try cap.start(CameraRequest(width: 1280, height: 720, fps: 30)) { _ in n.withLock { frames += 1 } }
        let t3 = Date()
        try await Task.sleep(nanoseconds: 500_000_000)
        let before = n.withLock { frames }
        var during: [CameraDevice] = []
        let tDuring = ms { during = provider.cameras() }
        print("W2 con captura abierta: \(during.count) cámaras, formatos \(during.first?.formats.count ?? -1), \(tDuring) ms; fotogramas durante la enumeración: \(n.withLock { frames } - before)")
        var second: MediaFoundationCameraCapture?
        do { second = try MediaFoundationCameraCapture(cameraID: cam.id); print("W2 segunda captura init ok") } catch { print("W2 segunda captura init: \(error)") }
        _ = second
        try await Task.sleep(nanoseconds: 500_000_000)
        cap.stop()
        print("W2 init capture \(t2.timeIntervalSince(t1) * 1000) ms, start \(t3.timeIntervalSince(t2) * 1000) ms, \(f.width)x\(f.height)@\(f.fps), fotogramas en 1 s: \(n.withLock { frames })")
    }

    /// Diagnóstico W-2: abrir la captura mientras otro hilo enumera sin parar (Ajustes, snapshots y sondeo de Grabar).
    func testCaptureStartWhileEnumeratingDiagnostic() throws {
        final class Flag: @unchecked Sendable { private let l = NSLock(); private var v = true; var on: Bool { get { l.withLock { v } } set { l.withLock { v = newValue } } } }
        let provider = MediaFoundationCameraProvider()
        guard let cam = provider.cameras().first else { return }
        let flag = Flag()
        let enumerator = Thread { while flag.on { _ = provider.cameras().first?.formats.count } }
        enumerator.start()
        var report: [String] = []
        for i in 0..<6 {
            let t0 = Date()
            do {
                let found = provider.camera(id: cam.id)
                let cap = try MediaFoundationCameraCapture(cameraID: cam.id)
                let f = try cap.start(CameraRequest(width: 1280, height: 720, fps: 30)) { _ in }
                report.append("#\(i) ok \(f.width)x\(f.height) formatos(camera(id:))=\(found?.formats.count ?? -1) \(Int(Date().timeIntervalSince(t0) * 1000)) ms")
                Thread.sleep(forTimeInterval: 0.3); cap.stop()
            } catch { report.append("#\(i) FALLO \(error) \(Int(Date().timeIntervalSince(t0) * 1000)) ms") }
        }
        flag.on = false
        print("W2 concurrente: " + report.joined(separator: " | "))
    }

    /// Diagnóstico W-2: dos capturas a la vez de la misma cámara (vista previa de Ajustes + Grabar).
    func testTwoCapturesSameCameraDiagnostic() throws {
        let provider = MediaFoundationCameraProvider()
        guard let cam = provider.cameras().first else { return }
        let a = try MediaFoundationCameraCapture(cameraID: cam.id)
        _ = try a.start(CameraRequest(width: 1280, height: 720, fps: 30)) { _ in }
        defer { a.stop() }
        let t0 = Date()
        do {
            let b = try MediaFoundationCameraCapture(cameraID: cam.id)
            defer { b.stop() }
            let f = try b.start(CameraRequest(width: 1280, height: 720, fps: 30)) { _ in }
            print("W2 segunda captura simultánea: ok \(f.width)x\(f.height) \(Int(Date().timeIntervalSince(t0) * 1000)) ms")
        } catch { print("W2 segunda captura simultánea: FALLO \(error) \(Int(Date().timeIntervalSince(t0) * 1000)) ms") }
    }

    /// Diagnóstico W-2: enumerar y abrir desde un hilo con COM de apartamento (STA, como el hilo de interfaz de Flutter).
    func testCameraFromSTAThreadDiagnostic() throws {
        final class Box: @unchecked Sendable { var s = "" }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        let t = Thread {
            let hr = CoInitializeEx(nil, DWORD(COINIT_APARTMENTTHREADED.rawValue))
            let t0 = Date()
            let cams = MediaFoundationCameraProvider().cameras()
            let ms = Date().timeIntervalSince(t0) * 1000
            var open = "sin cámara"
            if let c = cams.first {
                do {
                    let cap = try MediaFoundationCameraCapture(cameraID: c.id)
                    let f = try cap.start(CameraRequest(width: 1280, height: 720, fps: 30)) { _ in }
                    Thread.sleep(forTimeInterval: 0.5); cap.stop()
                    open = "abrió \(f.width)x\(f.height)"
                } catch { open = "falló al abrir: \(error)" }
            }
            box.s = "W2 STA CoInitializeEx=0x\(String(UInt32(bitPattern: hr), radix: 16)) cámaras=\(cams.count) formatos=\(cams.first?.formats.count ?? -1) \(ms) ms; \(open)"
            done.signal()
        }
        t.start()
        done.wait()
        print(box.s)
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
