import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  static var activity: NSObjectProtocol?

  override func awakeFromNib() {
    // El runner de macOS no pasa los argumentos de línea de comandos a main(args).
    // Sin App Nap: la app se lanza con open -g y no debe quedar suspendida.
    MainFlutterWindow.activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "P9 probe")
    let project = FlutterDartProject()
    project.dartEntrypointArguments = MainFlutterWindow.entrypointArguments()
    let flutterViewController = FlutterViewController(project: project)
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

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
