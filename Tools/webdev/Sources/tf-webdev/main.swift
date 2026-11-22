import AppKit
import AppCore
import UniformTypeIdentifiers
import WebKit

// tf-webdev [--web-dir D] [--alphatab-dir D] [--projects-folder D] [--support-dir D] [--screen S] [--project P] [--window WxH]
//           [--snapshot out.png] [--snapshot-delay s] [--foreground] [--mock] [--camera real|simulated (por omisión)]
//           [--eval js] [--eval-delay s] [--eval-file f.js [--eval-exit]]   (--eval-file como el de ToneForge.exe; --eval-exit sale al acabar)
// Páginas en tf-app://app/…, carpeta de proyectos en tf-media://media/… (mediaBase de app.info).

let args = Array(CommandLine.arguments.dropFirst())
/// W2-E2: sin `--camera real`, cámara simulada (la de AVFoundation pediría permiso de cámara al abrir Grabar o Ajustes).
let options: LaunchOptions = {
    var o = LaunchOptions.parse(args)
    if o.camera == nil { o.camera = .simulated }
    return o
}()
let mock = args.contains("--mock")
let background = (options.snapshot != nil || args.contains("--eval-file")) && !args.contains("--foreground")

func flagValue(_ name: String) -> String? {
    if let i = args.firstIndex(of: name), i + 1 < args.count { return args[i + 1] }
    return args.first { $0.hasPrefix(name + "=") }.map { String($0.dropFirst(name.count + 1)) }
}

/// WinApp/Web: `--web-dir`, o subiendo desde el directorio actual y desde el ejecutable.
func findWebDir() -> URL? {
    if let d = flagValue("--web-dir") { return URL(fileURLWithPath: d, isDirectory: true) }
    let starts = [URL(fileURLWithPath: FileManager.default.currentDirectoryPath), URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()]
    for var dir in starts {
        for _ in 0..<8 {
            let c = dir.appendingPathComponent("WinApp/Web/index.html")
            if FileManager.default.fileExists(atPath: c.path) { return dir.appendingPathComponent("WinApp/Web", isDirectory: true) }
            dir.deleteLastPathComponent()
        }
    }
    return nil
}

/// App/Resources/alphaTab: `--alphatab-dir`, o junto a WinApp/Web subiendo hasta la raíz del repo.
func findAlphaTabDir(web: URL) -> URL {
    if let d = flagValue("--alphatab-dir") { return URL(fileURLWithPath: d, isDirectory: true) }
    return web.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("App/Resources/alphaTab", isDirectory: true)
}

func fail(_ m: String) -> Never { FileHandle.standardError.write(Data("tf-webdev: \(m)\n".utf8)); exit(2) }

let mimeTypes = [
    "html": "text/html; charset=utf-8", "js": "text/javascript; charset=utf-8", "mjs": "text/javascript; charset=utf-8",
    "css": "text/css; charset=utf-8", "json": "application/json; charset=utf-8", "svg": "image/svg+xml",
    "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "webp": "image/webp", "woff2": "font/woff2",
    "wav": "audio/wav", "mp3": "audio/mpeg", "flac": "audio/flac", "mov": "video/quicktime", "mp4": "video/mp4",
    "txt": "text/plain; charset=utf-8", "md": "text/plain; charset=utf-8", "sf2": "application/octet-stream",
]

/// Sirve ficheros de `root`; rechaza cualquier ruta que salga de él.
final class FileSchemeHandler: NSObject, WKURLSchemeHandler {
    let root: () -> URL?
    /// Prefijos de ruta servidos desde otra carpeta (p. ej. `alphaTab` -> App/Resources/alphaTab).
    let overlays: [String: URL]
    init(_ root: @escaping () -> URL?, overlays: [String: URL] = [:]) { self.root = root; self.overlays = overlays }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return respond(task, status: 400, body: Data()) }
        var path = url.path.removingPercentEncoding ?? url.path
        var base = root()
        for (prefix, dir) in overlays where path.hasPrefix("/" + prefix + "/") {
            base = dir
            path = String(path.dropFirst(prefix.count + 1))
        }
        guard let root = base?.standardizedFileURL else { return respond(task, status: 404, body: Data("sin carpeta".utf8)) }
        if path.isEmpty || path == "/" { path = "/index.html" }
        let file = root.appendingPathComponent(String(path.dropFirst())).standardizedFileURL
        guard file.path.hasPrefix(root.path + "/"), let data = try? Data(contentsOf: file) else {
            return respond(task, status: 404, body: Data("no encontrado: \(path)".utf8))
        }
        let mime = mimeTypes[file.pathExtension.lowercased()] ?? "application/octet-stream"
        // Range: bytes=a-b | a- | -n (audio y vídeo piden tramos).
        if let range = task.request.value(forHTTPHeaderField: "Range"), range.hasPrefix("bytes="), !data.isEmpty {
            let spec = range.dropFirst(6).split(separator: ",").first.map(String.init) ?? ""
            let parts = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            var lo = 0, hi = data.count - 1
            if parts.count == 2 {
                if parts[0].isEmpty, let n = Int(parts[1]) { lo = max(0, data.count - n) }
                else if let a = Int(parts[0]) { lo = a; if let b = Int(parts[1]) { hi = min(b, data.count - 1) } }
            }
            guard lo <= hi, lo < data.count else {
                return respond(task, status: 416, body: Data(), headers: ["Content-Range": "bytes */\(data.count)"])
            }
            return respond(task, status: 206, body: data.subdata(in: lo..<(hi + 1)), mime: mime, url: url,
                           headers: ["Content-Range": "bytes \(lo)-\(hi)/\(data.count)", "Accept-Ranges": "bytes"])
        }
        respond(task, status: 200, body: data, mime: mime, url: url, headers: ["Accept-Ranges": "bytes"])
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    private func respond(_ task: WKURLSchemeTask, status: Int, body: Data, mime: String = "text/plain", url: URL? = nil, headers: [String: String] = [:]) {
        let u = url ?? task.request.url!
        var fields = ["Content-Type": mime, "Content-Length": "\(body.count)", "Cache-Control": "no-store"]
        fields.merge(headers) { $1 }
        let r = HTTPURLResponse(url: u, statusCode: status, httpVersion: "HTTP/1.1", headerFields: fields)!
        task.didReceive(r); task.didReceive(body); task.didFinish()
    }
}

/// Mensajes de la página: `tf` (puente JSON) y `log` (consola y errores a stderr).
final class MessageHandler: NSObject, WKScriptMessageHandler {
    var onBridge: ((String) -> Void)?
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        if m.name == "tf", let s = m.body as? String { onBridge?(s) }
        else if m.name == "log" { FileHandle.standardError.write(Data("[web] \(m.body)\n".utf8)) }
    }
}

/// Navegador oculto (W2-G/W2-H, `HiddenPageLoading`): segundo `WKWebView` sin ventana, almacén no persistente, una carga cada
/// vez, sondeo de `readyScript` cada 250 ms. Igual que `SongsterrWebLoader` del Mac.
@MainActor
final class HiddenBrowser: NSObject, WKNavigationDelegate {
    /// Cada cuánto se evalúa `readyScript` (contrato W2-G, `SongsterrHiddenPage.pollMillis`).
    static let pollInterval: Duration = .milliseconds(250)
    private let webView: WKWebView
    private var navigation: CheckedContinuation<Void, Error>?
    private var status = 200
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800), configuration: config)
        super.init()
        webView.navigationDelegate = self
    }

    func load(url: URL, userAgent: String?, readyScript: String?, timeout: TimeInterval) async throws -> HiddenPage {
        guard url.scheme == "https" else { throw HiddenPageError.unsupported }
        while busy {
            await withCheckedContinuation { waiters.append($0) }
            try Task.checkCancellation()
        }
        busy = true
        defer {
            busy = false
            if !waiters.isEmpty { waiters.removeFirst().resume() }
        }
        webView.customUserAgent = userAgent
        status = 200
        let deadline = Date().addingTimeInterval(timeout)
        try await navigate(url, deadline: deadline)
        while true {
            try Task.checkCancellation()
            var ready = true
            if let readyScript { ready = (try? await webView.evaluateJavaScript(readyScript) as? Bool) == true }
            if ready, let html = try await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String {
                return HiddenPage(status: status, html: html)
            }
            guard Date() < deadline else { throw HiddenPageError.readyTimeout }
            try await Task.sleep(for: Self.pollInterval)
        }
    }

    private func navigate(_ url: URL, deadline: Date) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                navigation = c
                webView.load(URLRequest(url: url, timeoutInterval: max(1, deadline.timeIntervalSinceNow)))
            }
        } onCancel: {
            Task { @MainActor in self.finish(.failure(HiddenPageError.cancelled)); self.webView.stopLoading() }
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let c = navigation else { return }
        navigation = nil
        c.resume(with: result)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        if navigationResponse.isForMainFrame, let http = navigationResponse.response as? HTTPURLResponse {
            status = http.statusCode
            if http.statusCode >= 400 {
                finish(.failure(HiddenPageError.httpStatus(http.statusCode)))
                return .cancel
            }
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(.success(())) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(.failure(Self.map(error))) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(Self.map(error)))
    }

    private static func map(_ error: Error) -> HiddenPageError {
        guard let e = error as? URLError else { return .offline }
        return e.code == .cancelled ? .cancelled : .offline
    }
}

/// Vista previa visible (W2-H): `WKWebView` hijo de la página principal, almacén por defecto (cookies persistentes como el Mac).
@MainActor
final class PreviewPanel {
    private(set) var view: WKWebView?
    private var loaded: URL?
    var parent: NSView?

    func show(url: URL, rect: PreviewRect) {
        guard let parent else { return }
        let v: WKWebView
        if let view { v = view } else {
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .default()
            v = WKWebView(frame: .zero, configuration: config)
            v.allowsBackForwardNavigationGestures = true
            view = v
        }
        if v.superview !== parent { parent.addSubview(v) }
        // Los puntos de AppKit son los píxeles CSS (zoom 1); el WKWebView padre está volteado: y desde arriba.
        v.frame = NSRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
        v.isHidden = false
        if loaded != url { loaded = url; v.load(URLRequest(url: url)) }
    }

    func hide() {
        guard let v = view, !v.isHidden || loaded != nil else { return }
        v.isHidden = true
        if loaded != nil { loaded = nil; v.load(URLRequest(url: URL(string: "about:blank")!)) }   // detiene el audio de Songsterr
    }

    /// Captura del panel visible, con su marco en la página (para componerla sobre la captura principal).
    func snapshot() async -> (NSImage, NSRect)? {
        guard let v = view, !v.isHidden, v.superview != nil else { return nil }
        let cfg = WKSnapshotConfiguration()
        cfg.snapshotWidth = NSNumber(value: Double(v.bounds.width))
        guard let image = try? await v.takeSnapshot(configuration: cfg) else { return nil }
        return (image, v.frame)
    }
}

/// Diálogos nativos del puente (host.pickAudioFile / host.pickProjectsFolder) con NSOpenPanel.
final class PanelHost: HostServices, @unchecked Sendable {
    let hidden = MainActor.assumeIsolated { HiddenBrowser() }
    let preview = MainActor.assumeIsolated { PreviewPanel() }

    func load(url: URL, userAgent: String?, readyScript: String?, timeout: TimeInterval) async throws -> HiddenPage {
        try await hidden.load(url: url, userAgent: userAgent, readyScript: readyScript, timeout: timeout)
    }

    func showPreview(url: URL, rect: PreviewRect) async -> Bool {
        await MainActor.run { preview.show(url: url, rect: rect); return preview.parent != nil }
    }

    func hidePreview() async { await MainActor.run { preview.hide() } }

    func pickFile(types: [String]) async -> URL? {
        await MainActor.run {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
            panel.allowedContentTypes = types.compactMap { UTType(filenameExtension: $0) }
            panel.title = "Importar tema"
            return panel.runModal() == .OK ? panel.url : nil
        }
    }

    func pickFiles(types: [String]) async -> [URL] {
        await MainActor.run {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
            panel.allowedContentTypes = types.compactMap { UTType(filenameExtension: $0) }
            panel.title = "Importar tema"; panel.prompt = "Importar"
            return panel.runModal() == .OK ? panel.urls : []
        }
    }

    func pickFolder() async -> URL? {
        await MainActor.run {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.title = "Carpeta de proyectos"
            return panel.runModal() == .OK ? panel.url : nil
        }
    }
}

/// Ventana que no se encoge al tamaño de la pantalla (iPad secundario, barra de menús): el tamaño pedido manda.
final class FixedWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor
final class Host: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    let handler = MessageHandler()
    var bridge: Bridge?
    var panelHost: PanelHost?
    let webDir: URL
    let alphaTabDir: URL

    init(webDir: URL) { self.webDir = webDir; alphaTabDir = findAlphaTabDir(web: webDir) }

    func applicationDidFinishLaunching(_ n: Notification) {
        let mediaBase = "tf-media://media/"
        if !mock {
            do { bridge = try Bridge(options: options, mediaBase: mediaBase) } catch { fail("AppCore: \(error)") }
            panelHost = PanelHost()
            bridge?.host = panelHost
            bridge?.start()
        }
        let config = WKWebViewConfiguration()
        // En segundo plano la ventana está tapada: sin esto WebKit frena temporizadores, rAF y promesas.
        if #available(macOS 14.0, *) { config.preferences.inactiveSchedulingPolicy = .none }
        config.setURLSchemeHandler(FileSchemeHandler({ [webDir] in webDir }, overlays: ["alphaTab": alphaTabDir]), forURLScheme: "tf-app")
        let media = bridge?.mediaFolder
        config.setURLSchemeHandler(FileSchemeHandler({ media }), forURLScheme: "tf-media")
        let ucc = WKUserContentController()
        ucc.add(handler, name: "tf")
        ucc.add(handler, name: "log")
        ucc.addUserScript(WKUserScript(source: """
            for (const k of ['error','warn']) { const o = console[k].bind(console);
              console[k] = (...a) => { window.webkit.messageHandlers.log.postMessage(k + ': ' + a.join(' ')); o(...a); }; }
            addEventListener('error', e => window.webkit.messageHandlers.log.postMessage('uncaught: ' + e.message + ' ' + e.filename + ':' + e.lineno));
            addEventListener('unhandledrejection', e => window.webkit.messageHandlers.log.postMessage('rejection: ' + e.reason));
            """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController = ucc

        let size = options.window ?? (1440, 900)
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: size.0, height: size.1), configuration: config)
        webView.navigationDelegate = self
        webView.isInspectable = true
        webView.setValue(false, forKey: "drawsBackground")

        if let b = bridge {
            handler.onBridge = { b.receive($0) }
            b.send = { [weak self] json in
                // Literal JSON válido como cadena JS (U+2028/9 escapados por JSONSerialization no hace falta en WebKit actual).
                guard let data = try? JSONSerialization.data(withJSONObject: [json]), let arr = String(data: data, encoding: .utf8) else { return }
                let literal = String(arr.dropFirst().dropLast())
                DispatchQueue.main.async { self?.webView.evaluateJavaScript("window.__tfReceive(\(literal))", completionHandler: nil) }
            }
        }

        window = FixedWindow(contentRect: NSRect(x: 0, y: 0, width: size.0, height: size.1),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "ToneForge (webdev\(mock ? ", mock" : ""))"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(red: 0x0F / 255.0, green: 0x11 / 255.0, blue: 0x13 / 255.0, alpha: 1)
        window.contentView = webView
        panelHost?.preview.parent = webView
        // Siempre en la pantalla principal y con el contenido exactamente del tamaño pedido.
        window.setContentSize(NSSize(width: size.0, height: size.1))
        if let main = NSScreen.screens.first {
            let f = window.frame, v = main.visibleFrame
            window.setFrameOrigin(NSPoint(x: v.midX - f.width / 2, y: v.midY - f.height / 2))
        }
        if background {
            // Detrás de todo, WebKit la da por oculta (visibilityState hidden: sin rAF y con temporizadores a ~1 Hz).
            // Transparente, sin ratón ni foco y fuera del ciclo de ventanas: cuenta como visible y no se ve ni se activa.
            window.alphaValue = 0.01
            window.ignoresMouseEvents = true
            window.hasShadow = false
            window.collectionBehavior = [.stationary, .ignoresCycle, .transient]
            window.orderFrontRegardless()
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        var comps = URLComponents(string: "tf-app://app/index.html")!
        if mock {
            comps.queryItems = [URLQueryItem(name: "mock", value: "1")]
                + [("screen", options.screen), ("project", options.project), ("state", flagValue("--state"))]
                    .compactMap { k, v in v.map { URLQueryItem(name: k, value: $0) } }
                + (flagValue("--mock-query") ?? "").split(separator: "&").map { kv -> URLQueryItem in
                    let p = kv.split(separator: "=", maxSplits: 1).map(String.init)
                    return URLQueryItem(name: p[0], value: p.count > 1 ? p[1] : "") }
        }
        // `--query k=v&k2=v2`: parámetros extra de la URL (QA: ?demo=..., ?study=...), con o sin --mock.
        if let q = flagValue("--query") {
            let extra = q.split(separator: "&").compactMap { pair -> URLQueryItem? in
                let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
                return kv.first.map { URLQueryItem(name: $0, value: kv.count > 1 ? kv[1] : "") }
            }
            comps.queryItems = (comps.queryItems ?? []) + extra
        }
        webView.load(URLRequest(url: comps.url!))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let js = flagValue("--eval") {
            // Ayuda para capturas: ejecuta JS tras la carga (a 1 s por defecto, o `--eval-delay`).
            let d = Double(flagValue("--eval-delay") ?? "") ?? 1.0
            DispatchQueue.main.asyncAfter(deadline: .now() + d) {
                // Imprime el resultado (o error) a stdout: `--eval` también sirve para leer estado.
                webView.callAsyncJavaScript("return await (async () => (\(js)))()", arguments: [:], in: nil, in: .page) { r in
                    switch r {
                    case .success(let v): print("eval: \(v)")
                    case .failure: webView.evaluateJavaScript(js) { v, e in print("eval: \(v.map { "\($0)" } ?? "null")\(e.map { " error: \($0)" } ?? "")") }
                    }
                }
            }
        }
        if let path = flagValue("--eval-file"), let code = try? String(contentsOfFile: path, encoding: .utf8) {
            // Igual que `--eval-file` de ToneForge.exe (WinApp/Web/bridge.js, `dev.eval`): el fichero es el CUERPO de una función async
            // con (bridge, log); `log(t)` sale por stderr como `[web] eval| t`. Termina con `eval| eval: fin -> <valor>` y sale del proceso.
            let d = Double(flagValue("--eval-delay") ?? "") ?? 2.0
            let wrapper = """
                const m = await import('/bridge.js');
                const bridge = { call: m.call, on: m.on, transportName: m.transportName, BridgeError: m.BridgeError, CALL_TIMEOUT_MS: m.CALL_TIMEOUT_MS };
                const log = t => window.webkit.messageHandlers.log.postMessage('eval| ' + String(t));
                const AF = Object.getPrototypeOf(async function () {}).constructor;
                try { const v = await new AF('bridge', 'log', code)(bridge, log); let o; try { o = JSON.stringify(v); } catch (e) { o = String(v); } log('eval: fin -> ' + o); }
                catch (e) { log('eval: excepción -> ' + (e && e.message || e)); }
                return 1;
                """
            DispatchQueue.main.asyncAfter(deadline: .now() + d) {
                webView.callAsyncJavaScript(wrapper, arguments: ["code": code], in: nil, in: .page) { r in
                    if case .failure(let e) = r { print("eval-file error: \(e)") }
                    if flagValue("--eval-exit") != nil { exit(0) }
                }
            }
        }
        guard let out = options.snapshot else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + options.snapshotDelay) { self.snapshot(to: out) }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail("navegación: \(error)") }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail("navegación: \(error)") }

    func snapshot(to url: URL) {
        let cfg = WKSnapshotConfiguration()
        cfg.snapshotWidth = NSNumber(value: Double(webView.bounds.width))
        webView.takeSnapshot(with: cfg) { image, error in
            guard var image else { fail("captura: \(String(describing: error))") }
            Task { @MainActor in
            // La vista previa (W2-H) es otro WKWebView: se compone sobre la captura principal.
            if let (overlay, frame) = await self.panelHost?.preview.snapshot() {
                let base = image
                let out = NSImage(size: base.size)
                out.lockFocus()
                base.draw(in: NSRect(origin: .zero, size: base.size))
                let scale = base.size.width / max(1, self.webView.bounds.width)
                overlay.draw(in: NSRect(x: frame.minX * scale, y: base.size.height - frame.maxY * scale,
                                        width: frame.width * scale, height: frame.height * scale))
                out.unlockFocus()
                image = out
            }
            guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { fail("captura: \(String(describing: error))") }
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try png.write(to: url)
            } catch { fail("escribir captura: \(error)") }
            print("captura: \(url.path) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
            exit(0)  // sin cola de trabajos que esperar: las capturas no lanzan separaciones
            }
        }
    }

    func applicationShouldTerminate(_ app: NSApplication) -> NSApplication.TerminateReply {
        guard let b = bridge else { return .terminateNow }
        Task { await b.shutdownAsync(); NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}

guard let webDir = findWebDir() else { fail("no encuentro WinApp/Web (usa --web-dir)") }
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(background ? .accessory : .regular)
    let host = Host(webDir: webDir)
    app.delegate = host
    app.run()
}
