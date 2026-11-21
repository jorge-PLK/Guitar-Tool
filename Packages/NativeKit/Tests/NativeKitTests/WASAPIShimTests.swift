#if os(Windows)
import CWASAPI
import Foundation
import XCTest

/// Shim WASAPI (parte 7.7): enumera, abre dúplex compartido, renderiza silencio y para/reabre sin colgarse. Las marcas
/// se comprueban en orden, no en valor (en la VM la tarjeta es virtual: sin latencia que valga).
final class WASAPIShimTests: XCTestCase {
    /// Contadores del hilo de audio (memoria fija; el callback no reserva ni toma cerrojos).
    struct Counters {
        var renderBuffers = 0, captureFrames = 0, renderOrderErrors = 0, captureGaps = 0
        var lastWritten: UInt64 = 0, nextCapture: UInt64 = .max, lastClockQPC: UInt64 = 0, clockQPCBackwards = 0
        var events = 0
    }

    func testEnumerateDoesNotFail() {
        let n = wasapi_enumerate(nil, 0)
        XCTAssertGreaterThanOrEqual(n, 0, "HRESULT \(String(UInt32(bitPattern: n), radix: 16))")
    }

    func testSharedDuplexStartsStopsAndRestarts() throws {
        var devices = [wasapi_device_info](repeating: wasapi_device_info(), count: 32)
        let n = Int(wasapi_enumerate(&devices, 32))
        let flows = devices.prefix(min(n, 32)).filter { $0.is_default != 0 }.map(\.flow)
        guard flows.contains(Int32(WASAPI_FLOW_RENDER)), flows.contains(Int32(WASAPI_FLOW_CAPTURE)) else {
            throw XCTSkip("[windows] el equipo no tiene salida y entrada de audio por defecto")
        }
        let counters = UnsafeMutablePointer<Counters>.allocate(capacity: 1)
        defer { counters.deallocate() }
        for attempt in 0..<2 {   // abrir, arrancar, parar, rearrancar y cerrar; dos veces
            counters.initialize(to: Counters())
            var p = wasapi_open_params()
            p.mode = Int32(WASAPI_MODE_SHARED)
            p.use_render = 1
            p.use_capture = 1
            p.ctx = UnsafeMutableRawPointer(counters)
            p.render = { ctx, _, frames, _, info in
                let c = ctx!.assumingMemoryBound(to: Counters.self)
                let i = info!.pointee
                if c.pointee.renderBuffers > 0, i.frames_written <= c.pointee.lastWritten { c.pointee.renderOrderErrors += 1 }
                if i.clock_qpc_100ns != 0 {
                    if i.clock_qpc_100ns < c.pointee.lastClockQPC { c.pointee.clockQPCBackwards += 1 }
                    c.pointee.lastClockQPC = i.clock_qpc_100ns
                }
                c.pointee.lastWritten = i.frames_written
                c.pointee.renderBuffers += 1
                _ = frames
            }
            p.capture = { ctx, _, frames, _, info in
                let c = ctx!.assumingMemoryBound(to: Counters.self)
                let i = info!.pointee
                if c.pointee.nextCapture != .max, i.stream_position != c.pointee.nextCapture,
                   i.flags & UInt32(WASAPI_CAPTURE_DISCONTINUITY) == 0 { c.pointee.captureGaps += 1 }
                c.pointee.nextCapture = i.stream_position + UInt64(frames)
                c.pointee.captureFrames += Int(frames)
            }
            p.event = { ctx, _, _, _, _ in ctx!.assumingMemoryBound(to: Counters.self).pointee.events += 1 }
            var stream: OpaquePointer?
            var info = wasapi_stream_info()
            var step: UnsafePointer<CChar>?
            let hr = wasapi_open(&p, &stream, &info, &step)
            XCTAssertEqual(hr, 0, "intento \(attempt): \(step.map { String(cString: $0) } ?? "?")")
            guard hr == 0, let stream else { return }
            defer { wasapi_close(stream) }
            for run in 0..<2 {
                counters.pointee.nextCapture = .max
                counters.pointee.renderBuffers = 0
                XCTAssertEqual(wasapi_start(stream), 0)
                Thread.sleep(forTimeInterval: 0.4)
                wasapi_stop(stream)
                var st = wasapi_stream_status()
                wasapi_get_status(stream, &st)
                XCTAssertEqual(st.stop_reason, 0, "intento \(attempt).\(run): parada pedida")
                XCTAssertEqual(st.running, 0)
                XCTAssertGreaterThan(counters.pointee.renderBuffers, 10, "0,4 s dan más de 10 búferes")
                XCTAssertGreaterThan(counters.pointee.captureFrames, 0)
            }
            XCTAssertEqual(counters.pointee.renderOrderErrors, 0)
            XCTAssertEqual(counters.pointee.clockQPCBackwards, 0)
            XCTAssertEqual(counters.pointee.captureGaps, 0)
            XCTAssertGreaterThan(info.render_buffer_frames, 0)
            XCTAssertGreaterThan(info.render_period_frames, 0)
        }
    }

    func testOpenRejectsMissingCallbacks() {
        var p = wasapi_open_params()
        p.use_render = 1
        var stream: OpaquePointer?
        XCTAssertLessThan(wasapi_open(&p, &stream, nil, nil), 0)
        XCTAssertNil(stream)
        wasapi_close(nil)
    }
}
#endif
