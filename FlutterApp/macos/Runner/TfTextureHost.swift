import Cocoa
import CoreVideo
import FlutterMacOS

// El runner no enlaza AppCoreFFI. Hace dlopen de la dylib (`--core-lib <ruta>` o, si no, la de Contents/Frameworks)
// y le da una tabla de tres punteros C. El mismo dlopen devuelve la misma imagen, por tanto el mismo estado global.
// Si la biblioteca o los símbolos no existen, la app arranca sin texturas.

/// Mismo diseño que `tf_texture_host` de tf_core.h.
struct TfTextureHostTable {
  var register_texture: (@convention(c) (Int32) -> Int64)?
  var frame_available: (@convention(c) (Int64) -> Void)?
  var unregister_texture: (@convention(c) (Int64) -> Void)?
}

/// Textura externa de un canal: Flutter llama a `copyPixelBuffer` desde su hilo de raster.
final class TfTexture: NSObject, FlutterTexture {
  let channel: Int32
  init(channel: Int32) { self.channel = channel }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    // tf_frame_copy devuelve el CVPixelBuffer retenido (+1); Flutter lo suelta.
    guard let copy = TfTextureHost.shared.frameCopy, let p = copy(channel) else { return nil }
    return Unmanaged<CVPixelBuffer>.fromOpaque(p)
  }
}

final class TfTextureHost: @unchecked Sendable {
  static let shared = TfTextureHost()

  fileprivate var frameCopy: (@convention(c) (Int32) -> UnsafeMutableRawPointer?)?
  private var registry: FlutterTextureRegistry?
  private var textures: [Int64: TfTexture] = [:]  // solo hilo principal
  private let table = UnsafeMutablePointer<TfTextureHostTable>.allocate(capacity: 1)

  /// Ruta de la dylib: `--core-lib <ruta>` o `Contents/Frameworks/libAppCoreFFI.dylib`.
  private static func corePath() -> String? {
    let args = CommandLine.arguments
    if let i = args.firstIndex(of: "--core-lib"), i + 1 < args.count { return args[i + 1] }
    guard let dir = Bundle.main.privateFrameworksPath else { return nil }
    let path = dir + "/libAppCoreFFI.dylib"
    return FileManager.default.fileExists(atPath: path) ? path : nil
  }

  /// Eager, desde `awakeFromNib` (antes de que arranque Dart). Sin biblioteca o sin símbolos no hace nada.
  func install(registry: FlutterTextureRegistry) {
    guard let path = TfTextureHost.corePath(),
          let handle = dlopen(path, RTLD_NOW),
          let setHost = dlsym(handle, "tf_core_set_texture_host"),
          let copy = dlsym(handle, "tf_frame_copy") else { return }
    self.registry = registry
    frameCopy = unsafeBitCast(copy, to: (@convention(c) (Int32) -> UnsafeMutableRawPointer?).self)
    table.initialize(to: TfTextureHostTable(
      register_texture: { channel in
        // El registro de Flutter solo se toca desde el hilo de plataforma.
        let work: () -> Int64 = {
          let h = TfTextureHost.shared
          guard let reg = h.registry else { return -1 }
          let t = TfTexture(channel: channel)
          let id = reg.register(t)
          h.textures[id] = t
          return id
        }
        return Thread.isMainThread ? work() : DispatchQueue.main.sync(execute: work)
      },
      frame_available: { id in
        // Se llama desde el hilo del generador: reencola a main.
        let work: () -> Void = { TfTextureHost.shared.registry?.textureFrameAvailable(id) }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
      },
      unregister_texture: { id in
        let work = {
          let h = TfTextureHost.shared
          h.registry?.unregisterTexture(id)
          h.textures[id] = nil
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync(execute: work) }
      }))
    let set = unsafeBitCast(setHost, to: (@convention(c) (UnsafeRawPointer?) -> Void).self)
    set(UnsafeRawPointer(table))
  }
}
