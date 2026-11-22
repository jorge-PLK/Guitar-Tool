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

    // P9 prueba 3: tabla de texturas para el núcleo (solo si hay --core-lib).
    TfTextureHost.shared.install(registry: flutterViewController.engine.registrar(forPlugin: "TfTexture").textures)

    super.awakeFromNib()
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
