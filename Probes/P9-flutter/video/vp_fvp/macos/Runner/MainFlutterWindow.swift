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

/// Callback síncrono de mdk onSync. NativeCallable.isolateGroupBound exige --experimental-shared-data (no
/// disponible en release), así que el cálculo pos(t) vive en nativo y Dart solo escribe la memoria compartida
/// (0 seq, 1 seconds, 2 playing, 3 at, 4 rate, 5 epoch, 6 nCalls, 7 tPrimera, 8 tÚltima, 9 maxGap,
/// 10 hiloPrimero, 11 llamadasEnOtroHilo). Reloj: gettimeofday (= DateTime.now de Dart).
@_cdecl("vp_onsync_clock")
public func vpOnSyncClock(_ opaque: UnsafeMutableRawPointer?) -> Double {
  guard let o = opaque else { return 0 }
  let p = o.assumingMemoryBound(to: Double.self)
  var tv = timeval()
  gettimeofday(&tv, nil)
  let now = Double(tv.tv_sec) + Double(tv.tv_usec) / 1e6
  let tid = Double(UInt(bitPattern: pthread_self()) & 0xFFFFFFFFFFFF)
  let n = p[6]
  if n == 0 {
    p[7] = now
    p[10] = tid
  } else {
    let gap = now - p[8]
    if gap > p[9] { p[9] = gap }
    if tid != p[10] { p[11] += 1 }
  }
  p[8] = now
  p[6] = n + 1
  var sec = 0.0, play = 0.0, at = 0.0, rate = 1.0
  for _ in 0..<8 {
    let s1 = p[0]
    sec = p[1]; play = p[2]; at = p[3]; rate = p[4]
    if s1 == p[0] && s1.truncatingRemainder(dividingBy: 2) == 0 { break }
  }
  let r = play != 0 ? sec + (now - at) * rate : sec
  if n == 0 { p[13] = r }
  p[14] = r
  return r
}
