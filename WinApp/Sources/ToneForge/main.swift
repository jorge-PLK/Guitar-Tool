// ToneForge para Windows (plan, «Fase 7c», paso 8, parte 8.0): ventana WebView2 + puente AppCore.
// Fuera de Windows este ejecutable no hace nada.
#if os(Windows)
import AppCore
import CWebView2Host
import Foundation
import NativeONNX
import NativePlatform
import WinSDK

/// Estado compartido con los callbacks C (que no pueden capturar): se pasa como `ctx`.
final class App: @unchecked Sendable {
    let options: LaunchOptions
    let bridge: Bridge
    let supportDir: URL
    var host: OpaquePointer?
    var exitCode: Int32 = 0

    init(options: LaunchOptions, bridge: Bridge, supportDir: URL) {
        self.options = options
        self.bridge = bridge
        self.supportDir = supportDir
    }
}

/// Segundos que se espera, en modo --snapshot, a que la página termine de cargar antes de rendirse.
let snapshotWatchdogSeconds = 90.0

/// Exclusión mutua asíncrona (una carga del navegador oculto a la vez; las demás esperan su turno, en orden).
final class AsyncMutex: @unchecked Sendable {
    private let lock = NSLock()
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        let mustWait: Bool = lock.withLock {
            if busy { return true }
            busy = true
            return false
        }
        if mustWait { await withCheckedContinuation { c in lock.withLock { waiters.append(c) } } }   // el turno se hereda (busy sigue true)
    }

    func release() {
        let next: CheckedContinuation<Void, Never>? = lock.withLock {
            if waiters.isEmpty { busy = false; return nil }
            return waiters.removeFirst()
        }
        next?.resume()
    }
}

/// Una carga en vuelo del navegador oculto: el callback C la recibe como `ctx` (retenida hasta `done`).
final class HiddenLoadBox: @unchecked Sendable {
    let id: UInt64
    let continuation: CheckedContinuation<HiddenPage, Error>
    private let lock = NSLock()
    private var _cancelled = false
    init(id: UInt64, continuation: CheckedContinuation<HiddenPage, Error>) { self.id = id; self.continuation = continuation }
    var cancelled: Bool { lock.withLock { _cancelled } }
    func markCancelled() { lock.withLock { _cancelled = true } }
}

/// Diálogos nativos del anfitrión: `IFileOpenDialog` modal sobre la ventana, en el hilo de UI (el shim hace el SendMessage).
/// Se llaman desde un hilo propio para no bloquear el pool cooperativo mientras el diálogo está abierto.
final class WindowsHostServices: HostServices, @unchecked Sendable {
    weak var app: App?

    private func pick(_ call: @escaping @Sendable (OpaquePointer, UnsafeMutablePointer<CChar>, Int32) -> Int32) async -> URL? {
        await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
            Thread.detachNewThread { [weak self] in
                guard let host = self?.app?.host else { continuation.resume(returning: nil); return }
                var buffer = [CChar](repeating: 0, count: 4096)
                let rc = buffer.withUnsafeMutableBufferPointer { call(host, $0.baseAddress!, Int32($0.count)) }
                continuation.resume(returning: rc == 1 ? URL(fileURLWithPath: String(cString: buffer)) : nil)
            }
        }
    }

    func pickFile(types: [String]) async -> URL? {
        let spec = types.joined(separator: ";")
        return await pick { host, out, cap in
            "Elegir archivo".withCString { title in spec.withCString { tfhost_pick_file(host, title, $0, out, cap) } }
        }
    }

    /// Búfer de la selección múltiple: rutas UTF-8 separadas por "\n" (1 MiB, unas 4000 rutas de 260 caracteres). Si aun así
    /// no cupiera, el shim devuelve negativo y se trata como cancelado (reintentar reabriría el selector).
    static let multiPickBufferBytes = 1 << 20

    func pickFiles(types: [String]) async -> [URL] {
        let spec = types.joined(separator: ";")
        return await withCheckedContinuation { (continuation: CheckedContinuation<[URL], Never>) in
            Thread.detachNewThread { [weak self] in
                guard let host = self?.app?.host else { continuation.resume(returning: []); return }
                var buffer = [CChar](repeating: 0, count: Self.multiPickBufferBytes)
                let rc = buffer.withUnsafeMutableBufferPointer { out in
                    "Elegir archivos".withCString { title in
                        spec.withCString { tfhost_pick_files(host, title, $0, out.baseAddress!, Int32(out.count)) }
                    }
                }
                if rc < 0 { tfLog("pickFiles: el selector devolvio \(rc)") }
                let paths = rc > 0 ? String(cString: buffer).split(separator: "\n").map(String.init) : []
                continuation.resume(returning: paths.map { URL(fileURLWithPath: $0) })
            }
        }
    }

    /// `ShellExecuteEx` "open" en el hilo de UI (lo hace el shim); `false` si el esquema no tiene aplicacion.
    func openURL(_ url: URL) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            Thread.detachNewThread { [weak self] in
                guard let host = self?.app?.host else { continuation.resume(returning: false); return }
                continuation.resume(returning: url.absoluteString.withCString { tfhost_open_url(host, $0) } == 1)
            }
        }
    }

    /// Cambio de carpeta de proyectos en caliente (B2): el shim reenvia al hilo de UI y vuelve a mapear `media.toneforge`.
    func projectsFolderChanged(_ url: URL) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            Thread.detachNewThread { [weak self] in
                guard let host = self?.app?.host else { continuation.resume(returning: false); return }
                let rc = url.path.withCString { tfhost_map_folder(host, "media.toneforge", $0) }
                tfLog("remapeo de media.toneforge: rc=\(rc) \(String(cString: tfhost_last_map_log()))")
                continuation.resume(returning: rc == 0)
            }
        }
    }

    func pickFolder(initial: URL?) async -> URL? {
        let start = initial?.path ?? ""
        return await pick { host, out, cap in
            "Elegir carpeta".withCString { title in start.withCString { tfhost_pick_folder_at(host, title, $0, out, cap) } }
        }
    }

    func pickFolder() async -> URL? {
        await pick { host, out, cap in
            "Elegir carpeta".withCString { tfhost_pick_folder(host, $0, out, cap) }
        }
    }

    // MARK: Navegador oculto (W2-H, contrato W2-G): segundo WebView2 InPrivate del shim.

    private let hiddenTurn = AsyncMutex()
    private let hiddenIDLock = NSLock()
    private var nextHiddenID: UInt64 = 0

    /// El `userAgent` que llega (Safari del Mac) se IGNORA: el navegador usa el propio de WebView2, que coincide con el motor.
    func load(url: URL, userAgent: String?, readyScript: String?, timeout: TimeInterval) async throws -> HiddenPage {
        await hiddenTurn.acquire()
        defer { hiddenTurn.release() }
        try Task.checkCancellation()
        guard let host = app?.host else { throw HiddenPageError.unsupported }
        let id: UInt64 = hiddenIDLock.withLock { nextHiddenID += 1; return nextHiddenID }
        let box = Box<HiddenLoadBox?>(nil)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HiddenPage, Error>) in
                let load = HiddenLoadBox(id: id, continuation: continuation)
                box.value = load
                let ctx = Unmanaged.passRetained(load).toOpaque()
                let done: @convention(c) (Int32, Int32, UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void = { result, status, html, ctx in
                    let load = Unmanaged<HiddenLoadBox>.fromOpaque(ctx!).takeRetainedValue()
                    switch result {
                    case 0: load.continuation.resume(returning: HiddenPage(status: Int(status), html: html.map { String(cString: $0) } ?? ""))
                    case 1: load.continuation.resume(throwing: HiddenPageError.offline)
                    case 2: load.continuation.resume(throwing: HiddenPageError.readyTimeout)
                    case 3: load.continuation.resume(throwing: HiddenPageError.httpStatus(Int(status)))
                    case 4: load.continuation.resume(throwing: HiddenPageError.cancelled)
                    default: load.continuation.resume(throwing: HiddenPageError.unsupported)
                    }
                }
                let timeoutMs = Int32(max(1, min(timeout, 600)) * 1000)
                let post: (UnsafePointer<CChar>?) -> Void = { ready in
                    url.absoluteString.withCString { tfhost_hidden_load(host, id, $0, ready, timeoutMs, done, ctx) }
                }
                if let readyScript { readyScript.withCString { post($0) } } else { post(nil) }
                // Cancelada antes de que el shim recibiera la carga: el aviso de cancelar pudo llegar antes y perderse.
                if load.cancelled { tfhost_hidden_cancel(host, id) }
            }
        } onCancel: {
            box.value?.markCancelled()
            if let host = self.app?.host { tfhost_hidden_cancel(host, id) }
        }
    }

    // MARK: Vista previa visible (W2-H): rect en píxeles CSS de la página; el shim aplica la escala del monitor.

    func showPreview(url: URL, rect: PreviewRect) async -> Bool {
        guard let host = app?.host else { return false }
        url.absoluteString.withCString { tfhost_preview_show(host, $0, rect.x, rect.y, rect.width, rect.height) }
        return true
    }

    func hidePreview() async {
        guard let host = app?.host else { return }
        tfhost_preview_hide(host)
    }
}

/// Caja mutable mínima para compartir un valor entre el cuerpo y el aviso de cancelación.
final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    init(_ v: T) { _value = v }
    var value: T { get { lock.withLock { _value } } set { lock.withLock { _value = newValue } } }
}

let logLock = NSLock()

/// Escribe en stdout (-11) o stderr (-12) solo si el proceso tiene ese handle. El ejecutable es del subsistema GUI:
/// abierto desde el Explorador no hay handles estandar y `FileHandle.standardError.write` aborta el proceso
/// (0xC000001D) antes de escribir la primera linea del log. Los errores de escritura se ignoran.
func writeStd(_ which: Int32, _ text: String) {
    guard let handle = GetStdHandle(DWORD(bitPattern: which)), handle != INVALID_HANDLE_VALUE else { return }
    let bytes = Array(text.utf8)
    var written: DWORD = 0
    _ = WriteFile(handle, bytes, DWORD(bytes.count), &written, nil)
}

/// Una linea al log con flush inmediato (abre, escribe y cierra). Si TF_LOG_FILE esta puesta, va a ese fichero (QA);
/// si no, a `<soporte>\toneforge.log`.
func tfLog(_ message: String, supportDir: URL? = nil) {
    logLock.lock()
    defer { logLock.unlock() }
    let line = "\(Date()) \(message)\n"
    writeStd(-12, line)
    let file: URL
    if let f = ProcessInfo.processInfo.environment["TF_LOG_FILE"], !f.isEmpty {
        file = URL(fileURLWithPath: f)
    } else {
        let dir = supportDir ?? SupportFolder.toneForge
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        file = dir.appendingPathComponent("toneforge.log")
    }
    if let h = try? FileHandle(forWritingTo: file) {
        h.seekToEndOfFile()
        h.write(Data(line.utf8))
        try? h.close()
    } else {
        try? Data(line.utf8).write(to: file)
    }
}

/// Ultimo paso del arranque y si ya llego on_ready: lo lee el vigilante.
final class Startup: @unchecked Sendable {
    private let lock = NSLock()
    private var _step = "inicio"
    private var _ready = false
    var step: String { lock.lock(); defer { lock.unlock() }; return _step }
    var ready: Bool { lock.lock(); defer { lock.unlock() }; return _ready }
    func mark(_ s: String) { lock.lock(); _step = s; lock.unlock(); tfLog("paso: \(s)") }
    func markReady() { lock.lock(); _ready = true; lock.unlock() }
}
let startup = Startup()
/// Segundos sin on_ready tras los que el vigilante da el arranque por colgado (solo QA: --snapshot o TF_LOG_FILE).
let startupWatchdogSeconds = 20.0

func executableDirectory() -> URL {
    var buffer = [WCHAR](repeating: 0, count: 32768)
    let n = GetModuleFileNameW(nil, &buffer, DWORD(buffer.count))
    let path = String(decoding: buffer[0..<Int(n)], as: UTF16.self)
    return URL(fileURLWithPath: path).deletingLastPathComponent()
}

/// `--selftest-mainactor`: comprueba que el hilo principal drena `@MainActor` y `DispatchQueue.main`.
final class SelfTestState: @unchecked Sendable {
    private let lock = NSLock()
    private var done: Set<String> = []
    func mark(_ name: String) {
        lock.lock(); done.insert(name); lock.unlock()
        writeStd(-11, "\(name)\n")
        tfLog(name)
    }
    func has(_ name: String) -> Bool { lock.lock(); defer { lock.unlock() }; return done.contains(name) }
}

/// Segundos que se espera en la autoprueba antes de dar FALLO.
let selfTestSeconds = 3.0

func startMainActorSelfTest() {
    let state = SelfTestState()
    Task { @MainActor in state.mark("mainactor ok") }
    DispatchQueue.main.async { state.mark("dispatch-main ok") }
    Thread.detachNewThread {
        let deadline = Date().addingTimeInterval(selfTestSeconds)
        while Date() < deadline, !(state.has("mainactor ok") && state.has("dispatch-main ok")) {
            Thread.sleep(forTimeInterval: 0.05)
        }
        var failed = false
        for name in ["mainactor", "dispatch-main"] where !state.has("\(name) ok") {
            writeStd(-11, "\(name) FALLO\n")
            tfLog("\(name) FALLO")
            failed = true
        }
        exit(failed ? 1 : 0)
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
let options = LaunchOptions.parse(arguments)

/// `--snapshot-hold <s>`: segundos que la ventana sigue abierta tras guardar el PNG (para capturar el escritorio).
let snapshotHold: Double = {
    guard let i = arguments.firstIndex(of: "--snapshot-hold"), i + 1 < arguments.count, let v = Double(arguments[i + 1]), v > 0 else { return 0 }
    return v
}()

/// `--eval-file <ruta.js>`: opción de desarrollo; tras on_ready + `--eval-delay` (2 s por defecto) manda a la página el código
/// como evento `dev.eval`. La página responde con peticiones `dev.log`, que se escriben en el log como `eval| <texto>`.
let evalFile: String? = {
    guard let i = arguments.firstIndex(of: "--eval-file"), i + 1 < arguments.count else { return nil }
    return arguments[i + 1]
}()
let evalDelay: Double = {
    guard let i = arguments.firstIndex(of: "--eval-delay"), i + 1 < arguments.count, let v = Double(arguments[i + 1]), v >= 0 else { return 2.0 }
    return v
}()

/// Manda al JS una cadena JSON ya serializada por el mismo camino que los eventos del puente.
func postToPage(_ app: App, _ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object), let json = String(data: data, encoding: .utf8) else { return }
    json.withCString { tfhost_post(app.host, $0) }
}

/// Si el mensaje es `dev.log` (solo con --eval-file) lo escribe en el log, responde y devuelve true.
func handleDevLog(_ app: App, _ text: String) -> Bool {
    guard evalFile != nil, text.contains("dev.log"),
          let data = text.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          obj["method"] as? String == "dev.log" else { return false }
    let params = obj["params"] as? [String: Any]
    tfLog("eval| \(params?["text"] as? String ?? "")")
    if let id = obj["id"] { postToPage(app, ["id": id, "result": [String: Any]()]) }
    return true
}

tfLog("args parseados: \(arguments.joined(separator: " ")) | pid \(ProcessInfo.processInfo.processIdentifier)")
// Una línea `onnx| modelo -> proveedor (...)` por sesión ONNX creada (ProviderChoice.swift). Solo Windows: el Mac usa Core ML.
OnnxModelLoader.setLogHandler { tfLog($0) }
if arguments.contains("--selftest-mainactor") {
    startMainActorSelfTest()
    dispatchMain()
}

// Segunda instancia: trae la abierta al frente y sale. Las ejecuciones de QA (--snapshot, --support-dir) no cuentan.
if options.snapshot == nil, options.supportDir == nil, tfhost_single_instance() == 0 { exit(0) }
let supportDir = options.supportDir ?? SupportFolder.toneForge
if options.snapshot != nil || ProcessInfo.processInfo.environment["TF_LOG_FILE"] != nil {
    Thread.detachNewThread {
        Thread.sleep(forTimeInterval: startupWatchdogSeconds)
        if !startup.ready {
            tfLog("vigilante: sin on_ready a los \(Int(startupWatchdogSeconds)) s; ultimo paso: \(startup.step)")
            exit(3)
        }
    }
    tfLog("vigilante armado (\(Int(startupWatchdogSeconds)) s)")
}
let webDir = executableDirectory().appendingPathComponent("Web", isDirectory: true)
let userDataDir = supportDir.appendingPathComponent("WebView2", isDirectory: true)
try? FileManager.default.createDirectory(at: userDataDir, withIntermediateDirectories: true)

// Hilos: la ventana y WebView2 viven en un hilo de UI propio (STA, con su bucle de mensajes Win32) y el hilo principal
// queda en dispatchMain(), que es lo que drena DispatchQueue.main y el ejecutor de @MainActor del nucleo (un GetMessage
// en el hilo principal no los drenaria). Bridge, anfitrion y arranque se hacen en el hilo de UI para que nada bloquee
// al hilo principal antes de dispatchMain. on_message sigue en el hilo de UI y no bloquea (receive lanza una Task).
/// Segundos maximos para cerrar el estudio (reproductor) al salir.
let closeStudyBudget = 3.0

func runUI() {
    startup.mark("hilo de UI en marcha")
    // STA antes que nada: crear el Bridge puede tocar Media Foundation (cámaras), que pide MTA; si llegase antes, WebView2
    // fallaría con RPC_E_CHANGED_MODE (0x80010106). Con STA puesto, esas piezas siguen sin cambiar el modo.
    let comHR = tfhost_init_ui_thread()
    startup.mark(comHR == 0 ? "COM en STA en el hilo de UI"
                            : "COM: no se pudo poner STA (HRESULT 0x\(String(UInt32(bitPattern: comHR), radix: 16)))")
    let bridge: Bridge
    startup.mark("creando Bridge")
    do {
        bridge = try Bridge(options: options, mediaBase: "https://media.toneforge/")
    } catch {
        tfLog("no se pudo crear el puente: \(error)", supportDir: supportDir)
        exit(2)
    }
    startup.mark("Bridge creado")
    let app = App(options: options, bridge: bridge, supportDir: supportDir)
    let appContext = Unmanaged.passUnretained(app).toOpaque()
    let size = options.window ?? (width: 1440, height: 900)
    startup.mark("llamando a tfhost_create")
    let created: OpaquePointer? = "ToneForge".withCString { title in
        webDir.path.withCString { web in
            userDataDir.path.withCString { data in
                var config = tfhost_config(
                    title_utf8: title,
                    width: Int32(size.width),
                    height: Int32(size.height),
                    web_dir_utf8: web,
                    user_data_dir_utf8: data,
                    on_ready: { ctx in
                        let app = Unmanaged<App>.fromOpaque(ctx!).takeUnretainedValue()
                        startup.markReady()
                        startup.mark("navegacion terminada (on_ready)")
                        if let file = evalFile {
                            Thread.detachNewThread {
                                Thread.sleep(forTimeInterval: evalDelay)
                                guard let code = try? String(contentsOfFile: file, encoding: .utf8) else {
                                    tfLog("eval: no se pudo leer \(file)")
                                    return
                                }
                                postToPage(app, ["event": "dev.eval", "payload": ["code": code]])
                                tfLog("eval: enviado (\(code.utf8.count) bytes)")
                            }
                        }
                        guard let snapshot = app.options.snapshot else { return }
                        let delay = app.options.snapshotDelay
                        tfLog("snapshot pedido en \(delay) s: \(snapshot.path)")
                        Thread.detachNewThread {
                            Thread.sleep(forTimeInterval: delay)
                            snapshot.path.withCString { path in
                                tfhost_capture_png(app.host, path, { ok, ctx in
                                    let app = Unmanaged<App>.fromOpaque(ctx!).takeUnretainedValue()
                                    if ok == 0 { tfLog("la captura fallo", supportDir: app.supportDir); app.exitCode = 1 }
                                    else { tfLog("snapshot guardado (hold \(snapshotHold) s)") }
                                    if snapshotHold > 0 {
                                        Thread.detachNewThread {
                                            Thread.sleep(forTimeInterval: snapshotHold)
                                            tfhost_quit(app.host)
                                        }
                                    } else {
                                        tfhost_quit(app.host)
                                    }
                                }, Unmanaged.passUnretained(app).toOpaque())
                            }
                        }
                    },
                    on_message: { text, ctx in
                        let app = Unmanaged<App>.fromOpaque(ctx!).takeUnretainedValue()
                        let message = String(cString: text!)
                        if handleDevLog(app, message) { return }
                        app.bridge.receive(message)
                    },
                    on_close: { ctx in
                        // Cierra la cola de trabajos (tope de unos 3 s) antes de que acabe el proceso.
                        tfLog("on_close: cerrando")
                        Unmanaged<App>.fromOpaque(ctx!).takeUnretainedValue().bridge.shutdown()
                    },
                    on_files_dropped: { paths, ctx in
                        // Hilo de UI: solo reenvia a la pagina (tfhost_post no bloquea).
                        let app = Unmanaged<App>.fromOpaque(ctx!).takeUnretainedValue()
                        let list = String(cString: paths!).split(separator: "\n").map(String.init)
                        postToPage(app, ["event": "host.filesDropped", "payload": ["paths": list]])
                    },
                    ctx: appContext)
                return tfhost_create(&config)
            }
        }
    }

    startup.mark("tfhost_create devolvio \(created == nil ? "NULL" : "ventana y WebView2 listos")")
    guard let host = created else {
        let reason = tfhost_last_error().map { String(cString: $0) } ?? "desconocido"
        tfLog("no se pudo crear la ventana WebView2: \(reason)", supportDir: supportDir)
        exit(2)
    }
    app.host = host
    let hostServices = WindowsHostServices()
    hostServices.app = app
    bridge.host = hostServices
    bridge.start()
    startup.mark("bridge.start llamado")

    bridge.send = { json in
        json.withCString { tfhost_post(app.host, $0) }
    }

    if let media = bridge.mediaFolder {
        let rc = media.path.withCString { tfhost_map_folder(host, "media.toneforge", $0) }
        if rc != 0 {
            tfLog("no se pudo mapear media.toneforge a \(media.path): \(tfhost_last_error().map { String(cString: $0) } ?? "?")", supportDir: supportDir)
        }
    }

    if options.snapshot != nil {
        Thread.detachNewThread {
            Thread.sleep(forTimeInterval: snapshotWatchdogSeconds + options.snapshotDelay + snapshotHold)
            tfLog("--snapshot: tiempo agotado sin terminar", supportDir: supportDir)
            exit(3)
        }
    }

    startup.mark("tfhost_run (navegando)")
    let runCode = tfhost_run(host)
    tfLog("tfhost_run volvio con \(runCode)", supportDir: supportDir)
    if runCode != 0 {
        tfLog("la carga inicial fallo: \(tfhost_last_error().map { String(cString: $0) } ?? "?")", supportDir: supportDir)
    }
    // Cierre ordenado: la cola ya se detuvo en on_close; ahora el estudio (puede saltar al actor principal, que corre
    // en el hilo principal dentro de dispatchMain, no en este).
    let closed = DispatchSemaphore(value: 0)
    Task.detached {
        await bridge.closeMontage()   // W2-E2 (ya lo hizo on_close -> shutdown; repetirlo no hace nada)
        await bridge.closeStudy()
        closed.signal()
    }
    _ = closed.wait(timeout: .now() + closeStudyBudget)
    exit(app.exitCode != 0 ? app.exitCode : Int32(runCode))
}

startup.mark("lanzando hilo de UI")
Thread.detachNewThread { runUI() }
dispatchMain()
#endif
