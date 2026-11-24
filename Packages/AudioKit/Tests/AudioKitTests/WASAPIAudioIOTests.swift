import Foundation
import XCTest
@testable import AudioKit
#if os(Windows)
import Synchronization

/// `WASAPIAudioIO` contra el dispositivo real de Windows (en la VM, la tarjeta HDA virtual). Solo abre, arranca y para:
/// la salida es SILENCIO (el manejador no escribe) y lo capturado no se guarda ni se analiza, solo se cuentan
/// fotogramas y saltos (brief del paso 7, «VM»). Sin topes de reloj: x64 va emulado.
final class WASAPIAudioIOTests: XCTestCase {
    /// Lo que cuentan los manejadores (hilo de audio, sin reservar).
    final class Counts: Sendable {
        let renderBlocks = Atomic<Int>(0)
        let captureFrames = Atomic<Int>(0)
        let captureJumps = Atomic<Int>(0)
        let nextCapture = Atomic<Int64>(-1)
        let renderHost = Atomic<Int>(0)
    }

    static func defaults() throws -> (render: WASAPIDeviceInfo, capture: WASAPIDeviceInfo?) {
        let list = try WASAPIAudioIO.devices()
        guard let r = list.first(where: { $0.flow == .render && $0.isDefault }) else {
            throw XCTSkip("[windows] sin endpoint de salida")
        }
        return (r, list.first { $0.flow == .capture && $0.isDefault })
    }

    static func run(_ io: WASAPIAudioIO, seconds: Double, _ c: Counts) throws {
        try io.start(render: { b in
            c.renderBlocks.add(1, ordering: .relaxed)            // silencio: el búfer llega a cero y no se toca
            if b.hostSeconds > 0 { c.renderHost.add(1, ordering: .relaxed) }
        }, capture: { b in
            let expected = c.nextCapture.load(ordering: .relaxed)
            if expected >= 0, expected != b.sampleTime { c.captureJumps.add(1, ordering: .relaxed) }
            c.nextCapture.store(b.sampleTime + Int64(b.frameCount), ordering: .relaxed)
            c.captureFrames.add(b.frameCount, ordering: .relaxed)
        })
        Thread.sleep(forTimeInterval: seconds)
        io.stop()
    }

    func testListsEndpointsWithMinimumPeriods() throws {
        let list = try WASAPIAudioIO.devices()
        guard !list.isEmpty else { throw XCTSkip("[windows] sin dispositivos de audio") }
        for d in list {
            print("WASAPI \(d.flow.rawValue)\(d.isDefault ? " *" : "") \(d.name) · \(d.mix.label) · compartido "
                  + "\(d.sharedPath.label) mín \(d.minimumSharedPeriodFrames) · exclusivo mín \(d.minimumExclusivePeriodFrames) · \(d.id)"
                  + " · driver \(d.driver.service)/\(d.driver.provider) \(d.driver.version) \(d.driver.infPath) · "
                  + "adaptador \(d.driver.adapterInstance) · hr 0x\(String(UInt32(bitPattern: d.driver.hresult), radix: 16))")
            XCTAssertFalse(d.id.isEmpty)
            XCTAssertGreaterThan(d.mix.sampleRate, 0)
            XCTAssertGreaterThan(d.minimumSharedPeriodFrames, 0)
        }
    }

    func testUnknownEndpointIsNotConnected() throws {
        _ = try Self.defaults()
        let setup = AudioSetup(inputDeviceUID: "{no-existe}", outputDeviceUID: "", sampleRate: 48_000)
        XCTAssertThrowsError(try WASAPIAudioIO(setup: setup)) { error in
            XCTAssertEqual(error as? AudioIOError, .notConnected("{no-existe}"))
        }
    }

    /// Entrada estricta en compartido (decisión por defecto de la parte 7.10b): a otra frecuencia que la salida, no abre.
    /// En la VM la entrada va a 44,1 kHz y la salida a 48 kHz, así que aquí corre.
    func testSharedInputAtOtherRateIsRejected() throws {
        let (render, capture) = try Self.defaults()
        guard let capture else { throw XCTSkip("[windows] sin endpoint de entrada") }
        guard abs(capture.mix.sampleRate - render.mix.sampleRate) >= 0.5 else {
            throw XCTSkip("[windows] entrada y salida a la misma frecuencia: no hay desajuste que rechazar")
        }
        let setup = AudioSetup(inputDeviceUID: capture.id, outputDeviceUID: render.id, sampleRate: render.mix.sampleRate)
        XCTAssertThrowsError(try WASAPIAudioIO(setup: setup)) { error in
            XCTAssertEqual(error as? AudioIOError,
                           .sampleRateMismatch(device: capture.mix.sampleRate, requested: render.mix.sampleRate))
        }
    }

    /// Con `allowInputResampling` (solo tests) abre también si la entrada va a otra frecuencia (AUTOCONVERTPCM): así el
    /// dúplex se prueba en la VM, donde entrada y salida no coinciden.
    func testSharedDuplexOpensRunsTwiceAndStops() throws {
        let (render, capture) = try Self.defaults()
        guard let capture else { throw XCTSkip("[windows] sin endpoint de entrada") }
        let setup = AudioSetup(inputDeviceUID: capture.id, outputDeviceUID: render.id, sampleRate: render.mix.sampleRate)
        let io = try WASAPIAudioIO(setup: setup, options: .init(allowInputResampling: true))
        let i = io.streamInfo
        print("WASAPI compartido: salida \(i.renderPath.label) periodo \(i.renderPeriodFrames) búfer \(i.renderBufferFrames); "
              + "entrada \(i.capturePath.label) periodo \(i.capturePeriodFrames) búfer \(i.captureBufferFrames) "
              + "(endpoint a \(i.captureDeviceRate) Hz); latencia declarada \(io.declaredLatencySamples) muestras")
        XCTAssertEqual(io.outputDeviceUID, render.id)
        XCTAssertEqual(io.inputDeviceUID, capture.id)
        XCTAssertEqual(io.format.sampleRate, render.mix.sampleRate)
        XCTAssertGreaterThan(io.format.inputChannels, 0)
        XCTAssertGreaterThan(io.format.outputChannels, 0)
        for pass in 1...2 {   // se puede volver a arrancar el mismo flujo
            let c = Counts()
            try Self.run(io, seconds: 3, c)
            XCTAssertFalse(io.isRunning)
            let st = io.status
            print("WASAPI pasada \(pass): búferes \(st.renderBuffers) · paquetes \(st.capturePackets) · MMCSS \(st.mmcss) · "
                  + "descartados \(st.droppedCaptureFrames) · offset \(st.captureOffset.map { "\($0)" } ?? "sin fijar") · "
                  + "deriva \(st.driftPPM.map { String(format: "%.1f", $0) } ?? "-") ppm · saltos \(c.captureJumps.load(ordering: .relaxed))")
            XCTAssertEqual(st.stopReason, 0, "el flujo no debe pararse solo")
            XCTAssertGreaterThan(c.renderBlocks.load(ordering: .relaxed), 0)
            XCTAssertGreaterThan(c.renderHost.load(ordering: .relaxed), 0, "hostSeconds de salida desde IAudioClock")
            XCTAssertGreaterThan(st.capturePackets, 0)
            // 3 s de paquetes de ~10 ms bastan para los 100 puntos del offset; luego la captura llega a los manejadores.
            XCTAssertNotNil(st.captureOffset)
            XCTAssertGreaterThan(c.captureFrames.load(ordering: .relaxed), 0)
        }
    }

    func testExclusiveDuplexOpensAndStops() throws {
        let (render, capture) = try Self.defaults()
        guard let capture else { throw XCTSkip("[windows] sin endpoint de entrada") }
        // El modo exclusivo no remuestrea: con entrada y salida por defecto a frecuencias distintas (p. ej. un micro
        // de 16 kHz) el dúplex exclusivo no puede abrirse a la frecuencia de salida y no hay nada que probar.
        guard abs(capture.mix.sampleRate - render.mix.sampleRate) < 0.5 else {
            throw XCTSkip("[windows] entrada a \(capture.mix.sampleRate) Hz y salida a \(render.mix.sampleRate) Hz: sin dúplex exclusivo posible")
        }
        let setup = AudioSetup(inputDeviceUID: capture.id, outputDeviceUID: render.id, sampleRate: render.mix.sampleRate)
        let io = try WASAPIAudioIO(setup: setup, options: .init(mode: .exclusive, periodFrames: 0))
        let i = io.streamInfo
        print("WASAPI exclusivo: salida \(i.renderFormat?.label ?? "-") periodo \(i.renderPeriodFrames); "
              + "entrada \(i.captureFormat?.label ?? "-") periodo \(i.capturePeriodFrames); "
              + "latencia declarada \(io.declaredLatencySamples) muestras")
        XCTAssertEqual(i.mode, .exclusive)
        XCTAssertEqual(i.renderPath, .exclusive)
        let c = Counts()
        try Self.run(io, seconds: 1.5, c)
        XCTAssertEqual(io.status.stopReason, 0)
        XCTAssertGreaterThan(c.renderBlocks.load(ordering: .relaxed), 0)
    }

    func testOutputOnlyOpensAtMixRate() throws {
        let (render, _) = try Self.defaults()
        let io = try WASAPIAudioIO(outputUID: "")
        XCTAssertEqual(io.outputDeviceUID, render.id, "vacío = render por defecto")
        XCTAssertEqual(io.inputDeviceUID, "")
        XCTAssertEqual(io.format.inputChannels, 0)
        XCTAssertEqual(io.format.sampleRate, render.mix.sampleRate)
        let c = Counts()
        try Self.run(io, seconds: 1, c)
        XCTAssertGreaterThan(c.renderBlocks.load(ordering: .relaxed), 0)
        XCTAssertEqual(c.captureFrames.load(ordering: .relaxed), 0)
    }
}
#endif
