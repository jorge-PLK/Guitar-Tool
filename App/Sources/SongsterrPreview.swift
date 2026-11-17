import SwiftUI
import WebKit

/// Vista previa visible de la página de una versión de Songsterr, dentro de la hoja. Es un `WKWebView` aparte del cargador
/// oculto (`SongsterrWebLoader`): navegación normal (desplazar, usar su reproductor), almacén por defecto para que los
/// avisos de cookies queden aceptados entre sesiones y el mismo user agent de Safari. Solo carga `url` cuando existe (la
/// vista solo se crea con la vista previa abierta) y recarga únicamente si `url` cambia.
struct SongsterrPreview: NSViewRepresentable {
    let url: URL

    final class Coordinator { var loaded: URL? }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: config)
        view.customUserAgent = SongsterrWebLoader.userAgent
        view.allowsBackForwardNavigationGestures = true
        view.load(URLRequest(url: url))
        context.coordinator.loaded = url
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.loaded != url else { return }
        context.coordinator.loaded = url
        view.load(URLRequest(url: url))
    }
}
