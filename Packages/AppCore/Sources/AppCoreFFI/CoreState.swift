import AppCore
import CAppCoreFFI
import Foundation

/// Sumidero de salida: el puerto nativo de Dart (`Dart_PostCObject_DL`) o, en tests, una closure.
enum Sink: @unchecked Sendable {
    case none
    case port(Int64)
    case handler(@Sendable (String) -> Void)
}

/// Estado del núcleo tras un lock. Todo acceso pasa por `lock`. La ABI usa la instancia global `coreState`.
final class CoreState: @unchecked Sendable {
    private let lock = NSLock()
    private var bridge: Bridge?
    private var sink: Sink = .none
    private var started = false
    private var closed = false
    let hostBroker = HostBroker()

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
        // `send` y `host` antes de `start()` (arquitectura.md, AppCoreFFI).
        hostBroker.emit = { [self] json in emit(json) }
        created.send = { [self] json in emit(json) }
        created.host = hostBroker
        #if canImport(CoreVideo) || os(Windows)
        installFrameSinks(on: created)  // cámara y Montaje por textura, no por `frames.<canal>` en JPEG
        #endif
        lock.lock(); bridge = created; lock.unlock()
        created.start()
        return 0
    }

    /// Mensaje de Dart: `{hostResponse}` resuelve una petición de anfitrión; el resto va a `Bridge.receive`
    /// (que no bloquea: el trabajo corre en una `Task`).
    func send(_ json: String) {
        if json.contains("\"hostResponse\""), hostBroker.resolve(json) { return }
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
        case .handler(let handle): handle(json)
        case .port(let port):
            let utf8 = Array(json.utf8)
            guard let raw = malloc(max(utf8.count, 1)) else { return }
            utf8.withUnsafeBytes { if !$0.isEmpty { memcpy(raw, $0.baseAddress!, $0.count) } }
            let ptr = raw.assumingMemoryBound(to: UInt8.self)
            // Sin copia: Dart toma el búfer y llama al finalizador C (-> tf_core_free). Si falla, lo liberamos aquí.
            if !tf_post_external(port, ptr, utf8.count) { Foundation.free(raw) }
        }
    }

    /// Asíncrono. Carrera entre `shutdownAsync()` y el tope, que cubre el cierre entero (hooks, Montaje, visor de tomas,
    /// tablatura, estudio y cola); el primero emite `core.shutdown` y cierra los envíos.
    func shutdown(timeoutMs: Int32) {
        lock.lock()
        guard let b = bridge, !closed else { lock.unlock(); return }
        bridge = nil
        lock.unlock()
        let once = Once { [self] clean in
            lock.lock(); closed = true; lock.unlock()
            hostBroker.failAll()
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
