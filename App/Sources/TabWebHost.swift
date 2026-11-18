import AppKit
import SwiftUI
import WebKit

/// `WKWebView` con alphaTab (`Contents/Resources/alphaTab/tab.html`, sin CDN) y el puente `window.TF` de
/// `tf-bridge.js`. Un único host por pantalla de Tablatura (mini-spec Fase 5, «Partitura, sonido y exportación»).
@MainActor
final class AlphaTabHost: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    enum Event: Equatable {
        case ready
        case rendered
        case beatClick(track: Int, bar: Int, beat: Int, shift: Bool)
        /// Arrastre con el botón pulsado sobre otro pulso (selección de tramo).
        case beatDrag(track: Int, bar: Int, beat: Int)
        case noteClick(track: Int, bar: Int, beat: Int, string: Int, fret: Int, shift: Bool)
        case error(String)
    }

    let webView: WKWebView
    var onEvent: ((Event) -> Void)?
    private(set) var isReady = false

    /// Diagnóstico: `TF_TAB_LOG=1` imprime los mensajes del puente en stderr y, si además `TF_TAB_LOG_FILE` es una
    /// ruta, los añade a ese fichero. Los errores (`error`) se registran siempre en stderr.
    private let logEvents = ProcessInfo.processInfo.environment["TF_TAB_LOG"] != nil

    private func log(_ text: String) {
        let line = Data((text + "\n").utf8)
        FileHandle.standardError.write(line)
        guard let path = ProcessInfo.processInfo.environment["TF_TAB_LOG_FILE"] else { return }
        if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
        if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(line); try? h.close() }
    }

    /// Carpeta `alphaTab` embebida en la app.
    static var resourceFolder: URL? { Bundle.main.resourceURL?.appendingPathComponent("alphaTab", isDirectory: true) }

    override init() {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        config.userContentController = controller
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        controller.add(WeakScriptHandler(self), name: "tf")
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        #if DEBUG
        webView.isInspectable = true
        #endif
        if let dir = Self.resourceFolder {
            // Lectura permitida a toda la carpeta (script, fuente Bravura y soundfont); nada fuera de ella.
            webView.loadFileURL(dir.appendingPathComponent("tab.html"), allowingReadAccessTo: dir)
        } else {
            onEvent?(.error("Falta la carpeta alphaTab en la app"))
        }
    }

    // MARK: Mensajes

    nonisolated func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let name = body["event"] as? String else { return }
        MainActor.assumeIsolated { handle(name, body) }
    }

    private func handle(_ name: String, _ b: [String: Any]) {
        if (logEvents && name != "cursor") || name == "error" { log("[alphaTab] \(b)") }
        func int(_ k: String) -> Int { (b[k] as? NSNumber)?.intValue ?? 0 }
        switch name {
        case "ready": isReady = true; onEvent?(.ready)
        case "rendered": onEvent?(.rendered)
        case "beatClick":
            onEvent?(.beatClick(track: int("track"), bar: int("bar"), beat: int("beat"), shift: (b["shift"] as? Bool) ?? false))
        case "beatDrag": onEvent?(.beatDrag(track: int("track"), bar: int("bar"), beat: int("beat")))
        case "noteClick":
            onEvent?(.noteClick(track: int("track"), bar: int("bar"), beat: int("beat"), string: int("string"), fret: int("fret"),
                                shift: (b["shift"] as? Bool) ?? false))
        case "error": onEvent?(.error(b["message"] as? String ?? "error de alphaTab"))
        default: break
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { onEvent?(.error(error.localizedDescription)) }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { onEvent?(.error(error.localizedDescription)) }
    }

    // MARK: Llamadas a TF

    /// `TF.load(json, trackIndex)`: construye la partitura entera y pinta la pista `track`.
    func load(json: String, track: Int) {
        run("TF.load(json, track)", ["json": json, "track": track])
    }

    func setCursorTime(_ seconds: Double, follow: Bool) {
        run("TF.setCursorTime(t, f)", ["t": seconds, "f": follow])
    }

    /// Marcador de selección en `bar` a `fraction` (0…1) del compás; `bar < 0` lo oculta.
    func setSelection(bar: Int, fraction: Double) {
        run("TF.setSelection(b, f)", ["b": bar, "f": fraction])
    }

    /// Resalta el tramo seleccionado de `startBar`/`startFraction` a `endBar`/`endFraction`; `startBar < 0` lo quita.
    func setRange(startBar: Int, startFraction: Double, endBar: Int, endFraction: Double) {
        run("TF.setRange(sb, sf, eb, ef)", ["sb": startBar, "sf": startFraction, "eb": endBar, "ef": endFraction])
    }

    /// `.gp` (Guitar Pro 7) de todas las pistas de la última partitura cargada.
    func exportGP() async throws -> Data {
        let result = try await webView.callAsyncJavaScript("return TF.exportGpBase64({});", arguments: [:], in: nil,
                                                           contentWorld: .page)
        guard let b64 = result as? String, let data = Data(base64Encoded: b64) else {
            throw NSError(domain: "ToneForge.Tab", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "alphaTab no devolvió el fichero"])
        }
        return data
    }

    private func run(_ body: String, _ args: [String: Any]) {
        guard isReady else { return }
        let web = webView
        Task { [weak self] in
            do {
                _ = try await web.callAsyncJavaScript(body, arguments: args, in: nil, contentWorld: .page)
            } catch {
                // WebKit solo dice «A JavaScript exception occurred»: el mensaje y la línea van en `userInfo`.
                let info = (error as NSError).userInfo
                let detail = ["WKJavaScriptExceptionMessage", "WKJavaScriptExceptionLineNumber", "WKJavaScriptExceptionSourceURL"]
                    .compactMap { k in info[k].map { "\($0)" } }.joined(separator: " · ")
                let text = "\(body): \(detail.isEmpty ? error.localizedDescription : detail)"
                self?.log("[alphaTab] run failed: \(text)")
                self?.onEvent?(.error(text))
            }
        }
    }
}

/// El controlador de contenido retiene a su manejador: se le da una referencia débil para no formar un ciclo.
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: AlphaTabHost?
    init(_ t: AlphaTabHost) { target = t }
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(c, didReceive: message)
    }
}

struct AlphaTabView: NSViewRepresentable {
    let host: AlphaTabHost
    func makeNSView(context: Context) -> WKWebView { host.webView }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
