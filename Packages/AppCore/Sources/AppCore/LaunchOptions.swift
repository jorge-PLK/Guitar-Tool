import Foundation

/// `--camera real|simulated` (W2-E2): de dónde salen las cámaras de Grabar y de la vista previa de Ajustes.
public enum CameraMode: String, Sendable, Equatable {
    /// Las del sistema (Media Foundation en Windows, AVFoundation en el Mac: pide permiso al abrir la cámara).
    case real
    /// «Cámara simulada» con imagen; no abre ningún dispositivo ni pide permiso.
    case simulated
}

/// Opciones de línea de órdenes del anfitrión (plan, «Fase 7c», paso 8).
public struct LaunchOptions: Sendable {
    public var projectsFolder: URL?
    public var supportDir: URL?
    public var screen: String?
    public var project: String?
    public var snapshot: URL?
    /// Segundos de espera antes de la captura (`--snapshot-delay`).
    public var snapshotDelay: Double
    public var window: (width: Int, height: Int)?
    /// `--audio simulated|device` (8.5): `simulated` no abre ningún dispositivo de audio (QA y tests).
    public var audio: AudioMode
    /// `--camera` (W2-E2); nil = según `--audio` (`simulated` -> cámara simulada; si no, las del sistema).
    public var camera: CameraMode?

    /// Espera por defecto antes de la captura, en segundos.
    public static let defaultSnapshotDelay = 2.0

    public init(projectsFolder: URL? = nil, supportDir: URL? = nil, screen: String? = nil, project: String? = nil,
                snapshot: URL? = nil, snapshotDelay: Double = LaunchOptions.defaultSnapshotDelay,
                window: (width: Int, height: Int)? = nil, audio: AudioMode = .device) {
        self.audio = audio
        self.projectsFolder = projectsFolder
        self.supportDir = supportDir
        self.screen = screen
        self.project = project
        self.snapshot = snapshot
        self.snapshotDelay = snapshotDelay
        self.window = window
    }

    /// `--flag valor` o `--flag=valor`; lo desconocido (incluido el nombre del ejecutable) se ignora.
    public static func parse(_ args: [String]) -> LaunchOptions {
        var o = LaunchOptions()
        var i = 0
        while i < args.count {
            var key = args[i]
            var value: String?
            if key.hasPrefix("--"), let eq = key.firstIndex(of: "=") {
                value = String(key[key.index(after: eq)...])
                key = String(key[..<eq])
            } else if key.hasPrefix("--"), i + 1 < args.count {
                value = args[i + 1]
            }
            guard key.hasPrefix("--"), let v = value, !v.isEmpty else { i += 1; continue }
            var consumed = false
            switch key {
            case "--projects-folder": o.projectsFolder = URL(fileURLWithPath: v, isDirectory: true); consumed = true
            case "--support-dir": o.supportDir = URL(fileURLWithPath: v, isDirectory: true); consumed = true
            case "--screen": o.screen = v; consumed = true
            case "--project": o.project = v; consumed = true
            case "--snapshot": o.snapshot = URL(fileURLWithPath: v); consumed = true
            case "--snapshot-delay":
                if let d = Double(v), d >= 0 { o.snapshotDelay = d }
                consumed = true
            case "--window":
                let parts = v.lowercased().split(separator: "x")
                if parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]), w > 0, h > 0 { o.window = (w, h) }
                consumed = true
            case "--audio":
                if let m = AudioMode(rawValue: v.lowercased()) { o.audio = m }
                consumed = true
            case "--camera":
                if let m = CameraMode(rawValue: v.lowercased()) { o.camera = m }
                consumed = true
            default: break
            }
            // Solo se salta el valor si el flag era nuestro y venía en dos argumentos.
            i += (consumed && !args[i].contains("=")) ? 2 : 1
        }
        return o
    }
}
