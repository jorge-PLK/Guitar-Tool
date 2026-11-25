import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    // El runner de macOS no pasa los argumentos de línea de comandos a main(args).
    let project = FlutterDartProject()
    project.dartEntrypointArguments = MainFlutterWindow.entrypointArguments()
    let flutterViewController = FlutterViewController(project: project)
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Tabla de texturas para el núcleo (solo si se encuentra la biblioteca de AppCoreFFI).
    TfTextureHost.shared.install(registry: flutterViewController.engine.registrar(forPlugin: "TfTexture").textures)

    super.awakeFromNib()
  }

  // desktop_drop instala un NSView `DropTarget` a pantalla completa por encima de FlutterView y su hitTest se queda
  // con el ratón: los WKWebView (platform views) no reciben clics. Se oculta solo mientras se despacha un evento de
  // ratón; el arrastre de ficheros entra por NSDraggingDestination, no por sendEvent, y el registro no cambia.
  private weak var dropTarget: NSView?

  private static let mouseTypes: Set<NSEvent.EventType> = [
    .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .rightMouseDragged,
    .otherMouseDown, .otherMouseUp, .otherMouseDragged, .mouseMoved, .scrollWheel,
  ]

  override func sendEvent(_ event: NSEvent) {
    guard MainFlutterWindow.mouseTypes.contains(event.type) else { return super.sendEvent(event) }
    if dropTarget == nil {
      dropTarget = contentView?.subviews.first { String(describing: type(of: $0)).contains("DropTarget") }
    }
    let target = dropTarget
    let wasHidden = target?.isHidden ?? true
    target?.isHidden = true
    defer { target?.isHidden = wasHidden }
    super.sendEvent(event)
  }

  /// Argumentos del usuario, sin los que inyecta macOS (-psn_, -NSxxx y su valor, -AppleLanguages…).
  static func entrypointArguments() -> [String] {
    var result: [String] = []
    var skipNext = false
    for arg in CommandLine.arguments.dropFirst() {
      if skipNext {
        skipNext = false
        continue
      }
      if arg.hasPrefix("-psn_") { continue }
      if arg.hasPrefix("-NS") || arg.hasPrefix("-Apple") {
        skipNext = true
        continue
      }
      result.append(arg)
    }
    return result
  }
}
