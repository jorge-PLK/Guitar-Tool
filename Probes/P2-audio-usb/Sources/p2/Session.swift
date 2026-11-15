import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

/// Resultado de una sesión de audio dúplex.
struct SessionResult {
    var inputs: [[Float]]            // por canal de entrada, F muestras
    var sampleRate: Double
    var frames: Int
    var bufferFrames: UInt32
    var callbacks: Int
    var overloads: Int               // notificaciones kAudioDeviceProcessorOverload
    var gaps: [(atFrame: Int, missingFrames: Int)]   // saltos en mSampleTime entre callbacks
    var gapCount: Int
    var stamps: [(sampleTime: Double, hostSeconds: Double)]
    var allInputsExactZero: Bool
}

enum Permission {
    final class Box { var ok = false }

    static func ensureMic() throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return
        case .notDetermined:
            let box = Box(), sem = DispatchSemaphore(value: 0)
            AVCaptureDevice.requestAccess(for: .audio) { ok in box.ok = ok; sem.signal() }
            sem.wait()
            if !box.ok { throw Failure("Permiso de micrófono denegado al terminal. Ajustes del Sistema > Privacidad > Micrófono.") }
        default:
            throw Failure("Sin permiso de micrófono para el terminal. Ajustes del Sistema > Privacidad > Micrófono, y vuelve a lanzar.")
        }
    }
}

/// Estado compartido con el IOProc. Todo preasignado: nada de asignaciones en el hilo de tiempo real.
final class IOState {
    var pos = 0
    var callbacks = 0
    var hasPrev = false
    var expected = 0.0
    var gapCount = 0
    var finished = false
    let gapCap = 4000
    let gapAt: UnsafeMutablePointer<Int>
    let gapMissing: UnsafeMutablePointer<Int>
    var stampCount = 0
    let stampCap: Int
    let stamps: UnsafeMutablePointer<Double>   // pares (sampleTime, hostTime en ticks)
    let sem = DispatchSemaphore(value: 0)

    init(stampCap: Int) {
        self.stampCap = stampCap
        gapAt = .allocate(capacity: gapCap)
        gapMissing = .allocate(capacity: gapCap)
        stamps = .allocate(capacity: stampCap * 2)
    }
    deinit { gapAt.deallocate(); gapMissing.deallocate(); stamps.deallocate() }
}

final class Counter {
    private let lock = NSLock()
    private var n = 0
    func bump() { lock.lock(); n += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}

enum Session {
    /// Arranca un IOProc sobre el dispositivo: graba todas las entradas y, si hay `play`, lo envía (mono)
    /// a los canales de salida `outChannels` (0-based). Entrada y salida avanzan con el mismo contador de
    /// muestras, así que la correlación entre lo enviado y lo grabado mide la latencia real de ida y vuelta.
    static func run(dev: DeviceInfo, seconds: Double, play: [Float]? = nil, outChannels: [Int] = []) throws -> SessionResult {
        let fs = dev.nominalRate
        let F = Int((seconds * fs).rounded())
        let nIn = dev.inputChannels
        guard F > 0, fs > 0 else { throw Failure("Duración o frecuencia inválida.") }
        guard nIn > 0 || play != nil else { throw Failure("\(dev.name) no tiene entradas que grabar.") }
        if let bad = outChannels.first(where: { $0 < 0 || $0 >= dev.outputChannels }) {
            throw Failure("Canal de salida \(bad + 1) fuera de rango (el dispositivo tiene \(dev.outputChannels)).")
        }
        if !outChannels.isEmpty && play == nil { throw Failure("Hay canales de salida pero nada que reproducir.") }
        for s in dev.input.streams + dev.output.streams where !s.isFloat32 {
            throw Failure("El stream no es float32 en el HAL (\(String(describing: s.format))); no soportado en esta prueba.")
        }
        if nIn > 0 { try Permission.ensureMic() }

        let bytes = nIn * F * 4
        guard bytes < 6_000_000_000 else { throw Failure("La grabación necesitaría \(bytes / 1_000_000) MB en memoria; reduce la duración.") }
        let rec = UnsafeMutablePointer<Float>.allocate(capacity: max(1, nIn * F))
        rec.initialize(repeating: 0, count: max(1, nIn * F))
        let playLen = play?.count ?? 0
        let playPtr = UnsafeMutablePointer<Float>.allocate(capacity: max(1, playLen))
        if let p = play { playPtr.initialize(from: p, count: p.count) }
        defer { rec.deallocate(); playPtr.deallocate() }

        let state = IOState(stampCap: F / 16 + 1024)
        let inMap = dev.input.map
        let outSel = outChannels.map { dev.output.map[$0] }
        let st = state

        let block: AudioDeviceIOBlock = { _, inData, inTime, outData, outTime in
            let inList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
            let outList = UnsafeMutableAudioBufferListPointer(outData)
            for b in outList { if let d = b.mData { memset(d, 0, Int(b.mDataByteSize)) } }

            var frames = 0
            if nIn > 0, inList.count > 0 {
                frames = Int(inList[0].mDataByteSize) / (4 * max(1, Int(inList[0].mNumberChannels)))
            } else if outList.count > 0 {
                frames = Int(outList[0].mDataByteSize) / (4 * max(1, Int(outList[0].mNumberChannels)))
            }

            let ts = nIn > 0 ? inTime.pointee : outTime.pointee
            if ts.mFlags.contains(.sampleTimeValid) {
                if st.hasPrev {
                    let diff = ts.mSampleTime - st.expected
                    if abs(diff) > 0.5 {
                        if st.gapCount < st.gapCap {
                            st.gapAt[st.gapCount] = st.pos
                            st.gapMissing[st.gapCount] = Int(diff.rounded())
                        }
                        st.gapCount += 1
                    }
                }
                st.hasPrev = true
                st.expected = ts.mSampleTime + Double(frames)
                if st.stampCount < st.stampCap, ts.mFlags.contains(.hostTimeValid) {
                    st.stamps[st.stampCount * 2] = ts.mSampleTime
                    st.stamps[st.stampCount * 2 + 1] = Double(ts.mHostTime)
                    st.stampCount += 1
                }
            }

            let pos = st.pos
            let n = min(frames, F - pos)
            if n > 0 {
                for c in 0..<nIn {
                    let m = inMap[c]
                    guard m.buf < inList.count, let raw = inList[m.buf].mData else { continue }
                    let src = raw.assumingMemoryBound(to: Float.self)
                    let dst = rec + c * F + pos
                    for i in 0..<n { dst[i] = src[i * m.n + m.off] }
                }
            }
            for m in outSel {
                guard m.buf < outList.count, let raw = outList[m.buf].mData else { continue }
                let dst = raw.assumingMemoryBound(to: Float.self)
                let outFrames = Int(outList[m.buf].mDataByteSize) / (4 * max(1, m.n))
                for i in 0..<min(outFrames, frames) {
                    let idx = pos + i
                    if idx < playLen { dst[i * m.n + m.off] = playPtr[idx] }
                }
            }
            st.pos = pos + frames
            st.callbacks += 1
            if st.pos >= F && !st.finished {
                st.finished = true
                st.sem.signal()
            }
        }

        let counter = Counter()
        var overAddr = HAL.addr(kAudioDeviceProcessorOverload)
        let listener: AudioObjectPropertyListenerBlock = { _, _ in counter.bump() }
        let lq = DispatchQueue(label: "p2.overload")
        AudioObjectAddPropertyListenerBlock(dev.id, &overAddr, lq, listener)
        defer { AudioObjectRemovePropertyListenerBlock(dev.id, &overAddr, lq, listener) }

        var procID: AudioDeviceIOProcID?
        let q = DispatchQueue(label: "p2.io", qos: .userInteractive)
        var status = AudioDeviceCreateIOProcIDWithBlock(&procID, dev.id, q, block)
        guard status == noErr, let proc = procID else { throw Failure("AudioDeviceCreateIOProcIDWithBlock falló (OSStatus \(status)).") }
        defer { AudioDeviceDestroyIOProcID(dev.id, proc) }
        status = AudioDeviceStart(dev.id, proc)
        guard status == noErr else { throw Failure("AudioDeviceStart falló (OSStatus \(status)).") }
        let waited = st.sem.wait(timeout: .now() + seconds + 10)
        AudioDeviceStop(dev.id, proc)
        guard waited == .success else {
            throw Failure("El dispositivo no entregó audio en \(Int(seconds) + 10) s (¿callback bloqueado, dispositivo desconectado?).")
        }

        var inputs: [[Float]] = []
        var allZero = true
        for c in 0..<nIn {
            let ch = Array(UnsafeBufferPointer(start: rec + c * F, count: F))
            if allZero, ch.contains(where: { $0 != 0 }) { allZero = false }
            inputs.append(ch)
        }
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        let tickToSec = Double(tb.numer) / Double(tb.denom) / 1e9
        let stamps = (0..<state.stampCount).map { (state.stamps[$0 * 2], state.stamps[$0 * 2 + 1] * tickToSec) }
        let gaps = (0..<min(state.gapCount, state.gapCap)).map { (atFrame: state.gapAt[$0], missingFrames: state.gapMissing[$0]) }
        return SessionResult(inputs: inputs, sampleRate: fs, frames: F, bufferFrames: dev.bufferFrames,
                             callbacks: state.callbacks, overloads: counter.value, gaps: gaps,
                             gapCount: state.gapCount, stamps: stamps, allInputsExactZero: nIn > 0 && allZero)
    }

    /// Deriva del reloj del dispositivo respecto al del Mac, en ppm, por regresión de mSampleTime sobre mHostTime.
    static func driftPPM(_ stamps: [(sampleTime: Double, hostSeconds: Double)], nominal: Double) -> (ppm: Double, residualMaxMs: Double)? {
        guard stamps.count > 100, let first = stamps.first else { return nil }
        let xs = stamps.map { $0.hostSeconds - first.hostSeconds }
        let ys = stamps.map { $0.sampleTime - first.sampleTime }
        let n = Double(xs.count)
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        var sxy = 0.0, sxx = 0.0
        for i in 0..<xs.count { sxy += (xs[i] - mx) * (ys[i] - my); sxx += (xs[i] - mx) * (xs[i] - mx) }
        guard sxx > 0 else { return nil }
        let slope = sxy / sxx
        var res = 0.0
        for i in 0..<xs.count { res = max(res, abs(ys[i] - (my + slope * (xs[i] - mx)))) }
        return ((slope / nominal - 1) * 1e6, res / nominal * 1000)
    }
}
