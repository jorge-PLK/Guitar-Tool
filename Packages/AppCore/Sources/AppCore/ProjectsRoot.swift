import Foundation

/// Carpeta de proyectos viva, compartida por la cola, el estudio, Montaje, las listas y Ajustes. Cambia en caliente cuando
/// `library.relocate` termina (como `Library.relocate` en el Mac: sin reiniciar). Seguro desde cualquier hilo.
final class ProjectsRoot: @unchecked Sendable, ExpressibleByNilLiteral {
    private let lock = NSLock()
    private var _url: URL?

    init(_ url: URL?) { _url = url }
    init(nilLiteral: ()) { _url = nil }

    var url: URL? {
        get { lock.withLock { _url } }
        set { lock.withLock { _url = newValue } }
    }
}
