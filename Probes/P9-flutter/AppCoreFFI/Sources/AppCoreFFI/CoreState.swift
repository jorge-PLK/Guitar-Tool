import AppCore
import CAppCoreFFI
import Foundation

/// Sumidero de salida enchufable: la siguiente parte añadirá la variante por puerto nativo de Dart.
enum Sink: @unchecked Sendable {
    case none
    case callback(tf_message_cb)
}

/// Estado global del núcleo tras un lock. Todo acceso pasa por `lock`.
final class CoreState: @unchecked Sendable {
    private let lock = NSLock()
    private var bridge: Bridge?
    private var sink: Sink = .none
    private var started = false
    private var closed = false
    private var liveBuffers: Int64 = 0

    /// 0 ok; 1 ya arrancado; 2 opciones inválidas; 3 falló Bridge.init.
    func start(optionsJSON: String, sink newSink: Sink) -> Int32 {
        lock.lock()
        if started { lock.unlock(); return 1 }
        guard let data = optionsJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let args = obj["args"] as? [String] else { lock.unlock(); return 2 }
        started = true
        sink = newSink
        lock.unlock()

        let created: Bridge
        do { created = try Bridge(options: LaunchOptions.parse(args), mediaBase: "") } catch {
            lock.lock(); started = false; sink = .none; lock.unlock()
            return 3
        }
        // `send` antes de `start()` (arquitectura.md, AppCoreFFI).
        created.send = { [self] json in emit(json) }
        lock.lock(); bridge = created; lock.unlock()
        created.start()
        return 0
    }

    func send(_ json: String) {
        lock.lock()
        let b = closed ? nil : bridge
        lock.unlock()
        b?.receive(json)
    }

    /// Copia el mensaje a un búfer `malloc` y lo entrega por el sumidero, desde el hilo que llame.
    func emit(_ json: String) {
        lock.lock()
        let current = sink
        lock.unlock()
        switch current {
        case .none: return
        case .callback(let cb):
            let utf8 = Array(json.utf8)
            guard let raw = malloc(max(utf8.count, 1)) else { return }
            utf8.withUnsafeBytes { if !$0.isEmpty { memcpy(raw, $0.baseAddress!, $0.count) } }
            lock.lock(); liveBuffers += 1; lock.unlock()
            cb(raw.assumingMemoryBound(to: UInt8.self), Int32(utf8.count))
        }
    }

    func free(_ ptr: UnsafePointer<UInt8>) {
        Foundation.free(UnsafeMutableRawPointer(mutating: ptr))
        lock.lock(); liveBuffers -= 1; lock.unlock()
    }

    func live() -> Int64 {
        lock.lock(); defer { lock.unlock() }
        return liveBuffers
    }

    /// Asíncrono. Carrera entre `shutdownAsync()` y el tope; el primero emite `core.shutdown` y cierra los envíos.
    func shutdown(timeoutMs: Int32) {
        lock.lock()
        guard let b = bridge, !closed else { lock.unlock(); return }
        bridge = nil
        lock.unlock()
        let once = Once { [self] clean in
            lock.lock(); closed = true; lock.unlock()
            emit("{\"event\":\"core.shutdown\",\"payload\":{\"clean\":\(clean)}}")
        }
        Task.detached {
            await b.shutdownAsync()
            once.fire(true)
        }
        Task.detached {
            try? await Task.sleep(nanoseconds: UInt64(max(timeoutMs, 0)) * 1_000_000)
            once.fire(false)
        }
    }
}

private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    private let action: @Sendable (Bool) -> Void
    init(_ action: @escaping @Sendable (Bool) -> Void) { self.action = action }
    func fire(_ clean: Bool) {
        lock.lock()
        if done { lock.unlock(); return }
        done = true
        lock.unlock()
        action(clean)
    }
}

let coreState = CoreState()
