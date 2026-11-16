import Foundation

struct CLIError: Error, CustomStringConvertible {
    let description: String
    init(_ text: String) { description = text }
}

enum Command: String {
    case cameras, record, sync, frame, montage
}

struct Options {
    var command: Command = .cameras
    var help = false
    var input: String?
    var output: String?
    var guitar: [Int] = []
    var backing = [1, 2]
    var rate: Double?
    var seconds: Double?
    var song: String?
    var camera: String?
    var width = 1920
    var height = 1080
    var fps = 30.0
    /// Latencia del audio simulado en muestras (activa el modo sin hardware).
    var simulated: Double?
    /// Deriva del reloj del audio simulado frente al host, en ppm.
    var simDriftPPM = 0.0
    /// Retardo de la cámara simulada, en ms.
    var simCameraDelayMs = 40.0
    /// Pierde uno de cada N fotogramas en la cámara simulada.
    var simDropEvery: Int?
    /// Argumentos sin guion (`frame <video>`, `montage <plan> <salida>`).
    var positional: [String] = []
    /// `frame`: PNG con la caja dibujada e intervalo de muestreo.
    var png: String?
    var interval: Double?
    /// `montage`: WAV de la mezcla y códec; tamaño y fps solo si se dan.
    var mix: String?
    var codec: String = "hevc"
    var sizeGiven = false
    var fpsGiven = false
}

enum Parse {
    static func number(_ text: String, _ name: String) throws -> Double {
        guard let v = Double(text.replacingOccurrences(of: ",", with: ".")), v.isFinite else {
            throw CLIError("\(name) espera un número y recibió «\(text)».")
        }
        return v
    }

    static func channels(_ text: String) throws -> [Int] {
        let parts = text.split(separator: ",").map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard !parts.isEmpty, parts.count <= 2, parts.allSatisfy({ ($0 ?? 0) >= 1 }) else {
            throw CLIError("--guitar espera uno o dos canales desde 1, p. ej. 1 o 1,2.")
        }
        return parts.map { $0! }
    }

    static func options(_ args: [String]) throws -> Options {
        var o = Options()
        var rest = args[...]
        if let first = rest.first, !first.hasPrefix("-") {
            guard let c = Command(rawValue: first) else { throw CLIError("Orden desconocida «\(first)». Usa cameras, record, sync, frame o montage.") }
            o.command = c
            rest = rest.dropFirst()
        } else if rest.isEmpty {
            o.help = true
        }
        var it = rest.makeIterator()
        func value(_ flag: String) throws -> String {
            guard let v = it.next() else { throw CLIError("\(flag) necesita un valor.") }
            return v
        }
        while let flag = it.next() {
            switch flag {
            case "--help", "-h": o.help = true
            case "--in": o.input = try value(flag)
            case "--out": o.output = try value(flag)
            case "--guitar": o.guitar = try channels(try value(flag))
            case "--backing":
                let b = try channels(try value(flag))
                guard b.count == 2, b[0] != b[1] else { throw CLIError("--backing espera dos canales distintos, p. ej. 1,2.") }
                o.backing = b
            case "--rate": o.rate = try number(try value(flag), flag)
            case "--seconds":
                let s = try number(try value(flag), flag)
                guard s > 0 else { throw CLIError("--seconds debe ser mayor que 0.") }
                o.seconds = s
            case "--song": o.song = try value(flag)
            case "--camera": o.camera = try value(flag)
            case "--width": o.width = Int(try number(try value(flag), flag)); o.sizeGiven = true
            case "--height": o.height = Int(try number(try value(flag), flag)); o.sizeGiven = true
            case "--fps": o.fps = try number(try value(flag), flag); o.fpsGiven = true
            case "--png": o.png = try value(flag)
            case "--interval":
                let s = try number(try value(flag), flag)
                guard s > 0 else { throw CLIError("--interval debe ser mayor que 0.") }
                o.interval = s
            case "--mix": o.mix = try value(flag)
            case "--codec":
                let c = try value(flag)
                guard c == "hevc" || c == "h264" else { throw CLIError("--codec espera hevc o h264.") }
                o.codec = c
            case let arg where !arg.hasPrefix("-") && (o.command == .frame || o.command == .montage):
                o.positional.append(arg)
            case "--simulated":
                let l = try number(try value(flag), flag)
                guard l >= 33 else { throw CLIError("--simulated espera una latencia de 33 muestras o más.") }
                o.simulated = l
            case "--sim-drift": o.simDriftPPM = try number(try value(flag), flag)
            case "--sim-camera-delay": o.simCameraDelayMs = try number(try value(flag), flag)
            case "--sim-drop": o.simDropEvery = Int(try number(try value(flag), flag))
            default: throw CLIError("Opción desconocida «\(flag)».")
            }
        }
        if (o.command == .record || o.command == .sync) && !o.help && o.seconds == nil { throw CLIError("Falta --seconds.") }
        if o.command == .frame && !o.help && o.positional.count != 1 { throw CLIError("frame espera un vídeo: tf-video frame <video.mov>.") }
        if o.command == .montage && !o.help && o.positional.count != 2 {
            throw CLIError("montage espera el plan y la salida: tf-video montage <plan.json> <salida.mov>.")
        }
        return o
    }
}

extension Double {
    func fixed(_ decimals: Int) -> String { String(format: "%.\(decimals)f", self) }
}
