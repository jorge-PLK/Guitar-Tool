import CoreMedia
import XCTest
@testable import VideoKit

/// `HostTimeMap` (mini-spec Fase 6, «Pruebas»): ida y vuelta exactas a 44,1 y 48 kHz, con cambio de ancla (seek) y
/// con deriva; y la escala de host común con CoreMedia.
final class HostTimeMapTests: XCTestCase {
    /// Marcas de un reloj de `fs` con `ppm` de deriva frente al host, un ciclo de 512 cada vez durante `seconds`.
    static func clock(fs: Double, ppm: Double, host0: Double, sample0: Double, seconds: Double) -> HostTimeMap {
        var m = HostTimeMap(sampleRate: fs)
        let rate = fs * (1 + ppm * 1e-6)
        var y = sample0
        while y < sample0 + seconds * fs {
            m.addClockPoint(outputSample: y, hostSeconds: host0 + (y - sample0) / rate)
            y += 512
        }
        return m
    }

    /// Ida y vuelta host → tema → host y tema → host → tema, en 300 s de pasada, con dos anclas (seek hacia delante
    /// y hacia atrás). Tolerancias: 1 ns en host y 1e-6 muestras en el tema; la muestra entera no cambia nunca.
    func testRoundTripsAreExactAtBothRatesAndAcrossSeeks() {
        for fs in [44_100.0, 48_000.0] {
            for ppm in [0.0, 50.0, -37.5] {
                var m = Self.clock(fs: fs, ppm: ppm, host0: 86_400.123456, sample0: 123_456_789, seconds: 300)
                // Pasada 1 desde 12,34 s del tema; seek a los 100 s de pasada al 200,5 s; seek hacia atrás a los 200 s al 30 s.
                let a1 = HostTimeMap.Anchor(songTime: 12.34, outputSample: 123_456_789 + 4_321.5, sampleRate: fs)
                let a2 = HostTimeMap.Anchor(songTime: 200.5, outputSample: 123_456_789 + 100 * fs + 77, sampleRate: fs)
                let a3 = HostTimeMap.Anchor(songTime: 30, outputSample: 123_456_789 + 200 * fs + 13.25, sampleRate: fs)
                m.setAnchor(a1)
                m.setAnchor(a2)
                m.setAnchor(a3)
                XCTAssertEqual(m.anchors.count, 3)
                var worstHost = 0.0, worstSong = 0.0, sampleChanges = 0, checked = 0
                for i in stride(from: 1.0, to: 299, by: 0.37) {
                    let h = m.hostSeconds(atOutputSample: 123_456_789 + i * fs)!
                    guard let (t, k) = m.songPosition(atHostSeconds: h) else { XCTFail("sin tiempo del tema"); continue }
                    XCTAssertEqual(k, i < 100 ? 0 : i < 200 ? 1 : 2)
                    // Host → (tema, pasada) → host y vuelta al tema.
                    let h2 = m.hostSeconds(atSongTime: t, anchorIndex: k)!
                    let t2 = m.songTime(atHostSeconds: h2)!
                    worstHost = max(worstHost, abs(h2 - h))
                    worstSong = max(worstSong, abs(t2 - t) * fs)
                    if (t * fs).rounded(.down) != (t2 * fs).rounded(.down) { sampleChanges += 1 }
                    // Sin pasada: la más reciente que llega a ese tiempo (la última llega a todo lo ≥ 30 s).
                    let latest = m.hostSeconds(atSongTime: t)!
                    if t < 30 { XCTAssertEqual(latest, h, accuracy: 1e-9) } else { XCTAssertGreaterThanOrEqual(latest, h - 1e-9) }
                    checked += 1
                }
                print(String(format: "F6 HostTimeMap %.0f Hz, %.1f ppm: %d puntos, máx |host| %.2e s, máx |tema| %.2e muestras, %d muestras cambiadas",
                             fs, ppm, checked, worstHost, worstSong, sampleChanges))
                XCTAssertLessThanOrEqual(worstHost, 1e-9)
                XCTAssertLessThanOrEqual(worstSong, 1e-6)
                XCTAssertEqual(sampleChanges, 0)
                XCTAssertEqual(m.audioClockPPM ?? .nan, ppm, accuracy: 1e-5)
                // Antes de la primera ancla no hay tiempo del tema.
                XCTAssertNil(m.songTime(atHostSeconds: m.hostSeconds(atOutputSample: 123_456_789)!))
                // Seek: cada tramo usa su ancla.
                let hB = m.hostSeconds(atOutputSample: 123_456_789 + 150 * fs)!
                XCTAssertEqual(m.songTime(atHostSeconds: hB)!, 200.5 + (50 * fs - 77) / fs, accuracy: 1e-9)
            }
        }
    }

    /// Con una sola marca se usa la frecuencia nominal; sin marcas o sin ancla no hay conversión; un ancla nueva
    /// anterior a las que había las sustituye.
    func testDegenerateCasesAndAnchorReplacement() {
        var m = HostTimeMap(sampleRate: 48_000)
        XCTAssertNil(m.hostSeconds(atOutputSample: 0))
        m.addClockPoint(outputSample: 1_000, hostSeconds: 50)
        XCTAssertEqual(m.hostSeconds(atOutputSample: 49_000)!, 51, accuracy: 1e-12)
        XCTAssertNil(m.audioClockPPM)
        XCTAssertNil(m.songTime(atHostSeconds: 51))
        m.setAnchor(.init(songTime: 10, outputSample: 5_000, sampleRate: 48_000))
        m.setAnchor(.init(songTime: 20, outputSample: 9_000, sampleRate: 48_000))
        m.setAnchor(.init(songTime: 30, outputSample: 7_000, sampleRate: 48_000))
        XCTAssertEqual(m.anchors.map(\.songTime), [10, 30])
    }

    /// Las marcas de host de cámara (CMTime del reloj de host) y de audio (ticks de mach) se pasan a la misma escala.
    func testHostClockMatchesCoreMediaHostClock() {
        let now = mach_absolute_time()
        let cm = CMClockMakeHostTimeFromSystemUnits(now)
        // CoreMedia guarda ns y la vuelta a ticks redondea: un tick (≈ 42 ns en Apple Silicon) como mucho.
        XCTAssertEqual(HostClock.seconds(hostTime: cm), HostClock.seconds(ticks: now), accuracy: HostClock.seconds(ticks: 1) + 1e-12)
        XCTAssertEqual(CMTimeGetSeconds(cm), HostClock.seconds(ticks: now), accuracy: 1e-6)
        let s = HostClock.nowSeconds
        XCTAssertEqual(HostClock.seconds(hostTime: HostClock.hostTime(seconds: s)), s, accuracy: 1e-7)
        XCTAssertEqual(CMTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock())), HostClock.nowSeconds, accuracy: 0.01)
    }

    /// Análisis de marcas de la cámara: fotogramas perdidos, fps y jitter.
    func testFrameTimingFindsDropsRateAndJitter() {
        let cam = SimulatedCameraCapture(config: .init(delaySeconds: 0.04, jitterSeconds: 0.002, dropEvery: 10), originHostSeconds: 100)
        var stamps: [Double] = []
        _ = try? cam.start(CameraRequest(width: 640, height: 360, fps: 30)) { _ in }
        for k in 0..<900 where !cam.isDropped(k) { stamps.append(cam.stampHostSeconds(ofFrame: k)) }
        let t = FrameTiming.analyze(hostTimes: stamps, nominalFPS: 30)!
        print(String(format: "F6 marcas simuladas: %d perdidos, %.4f fps, jitter máx %.3f ms", t.droppedFromGaps, t.measuredFPS, t.jitterMax * 1000))
        // 90 perdidos (uno de cada 10); el último (899) no deja hueco porque no hay fotograma detrás.
        XCTAssertEqual(t.droppedFromGaps, 89)
        XCTAssertEqual(t.measuredFPS, 30, accuracy: 0.01)
        XCTAssertLessThanOrEqual(t.jitterMax, 0.0025)
        XCTAssertGreaterThan(t.jitterMax, 0.0015)
    }

    /// Formato más cercano: resolución primero, luego fps.
    func testClosestFormat() {
        let c = CameraDevice.simulated
        let a = c.closestFormat(to: CameraRequest(width: 1920, height: 1080, fps: 120))!
        XCTAssertEqual([a.format.width, a.format.height], [1920, 1080])
        XCTAssertEqual(a.fps, 60)
        let b = c.closestFormat(to: CameraRequest(width: 3840, height: 2160, fps: 30))!
        XCTAssertEqual(b.format.width, 1920)
        let d = c.closestFormat(to: CameraRequest(width: 700, height: 400, fps: 25))!
        XCTAssertEqual(d.format.width, 640)
        XCTAssertEqual(d.fps, 30)
    }
}
