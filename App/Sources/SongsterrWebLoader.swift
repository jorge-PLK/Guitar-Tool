import AppKit
import SourceKit
import WebKit

/// Carga páginas de Songsterr en un `WKWebView` oculto, como un navegador, y devuelve el HTML ya cargado a SourceKit
/// (mini-spec Fase 5b, parte 1). Sin UI: la hoja de Songsterr (parte 5) usa `SongsterrClient(loader:)`.
///
/// Una carga cada vez (las siguientes esperan). Sin bucles: un fallo se devuelve tal cual como `SongsterrError`.
@MainActor
final class SongsterrWebLoader: NSObject, SongsterrPageLoading, WKNavigationDelegate {
    /// Tiempo máximo de una carga completa (navegación + estado embebido).
    static let loadTimeout: TimeInterval = 30
    /// Cada cuánto se mira si el estado ya está en la página tras la navegación.
    static let pollInterval: Duration = .milliseconds(250)
    static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    private let webView: WKWebView
    private var navigation: CheckedContinuation<Void, Error>?
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800), configuration: config)
        webView.customUserAgent = Self.userAgent
        super.init()
        webView.navigationDelegate = self
    }

    nonisolated func html(for url: URL) async throws -> String {
        try await load(url)
    }

    private func load(_ url: URL) async throws -> String {
        guard url.scheme == "https", SongsterrReader.isSongsterrHost(url.host) else { throw SongsterrError.invalidHost }
        while busy { await withCheckedContinuation { waiters.append($0) } }
        busy = true
        defer {
            busy = false
            if !waiters.isEmpty { waiters.removeFirst().resume() }
        }
        let deadline = Date().addingTimeInterval(Self.loadTimeout)
        try await navigate(url, deadline: deadline)
        // El estado va en el HTML inicial; se espera a que esté (la página puede tardar en montarse).
        while true {
            try Task.checkCancellation()
            let hasState = try? await webView.evaluateJavaScript("document.getElementById('state') !== null") as? Bool
            if hasState == true,
               let html = try await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String {
                return html
            }
            guard Date() < deadline else { throw SongsterrError.unknownFormat("sin script de estado") }
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
            Task { @MainActor in self.finish(.failure(SongsterrError.cancelled)); self.webView.stopLoading() }
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let c = navigation else { return }
        navigation = nil
        c.resume(with: result)
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        if navigationResponse.isForMainFrame, let http = navigationResponse.response as? HTTPURLResponse {
            if http.statusCode == 429 {
                finish(.failure(SongsterrError.rateLimited))
                return .cancel
            }
            if http.statusCode >= 400 {
                finish(.failure(SongsterrError.httpStatus(http.statusCode)))
                return .cancel
            }
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(.success(())) }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(Self.map(error)))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(Self.map(error)))
    }

    private static func map(_ error: Error) -> SongsterrError {
        guard let e = error as? URLError else { return .offline }
        return e.code == .cancelled ? .cancelled : .offline
    }
}
