import AudioKit
import Foundation

/// Error de uso o de dispositivo (código de salida 2).
struct CLIError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}

enum Command: String {
    case devices, latency, verify, record
}

/// Opciones de la línea de órdenes (mini-spec Fase 3, «Código»: `tf-audio`).
struct Options: Equatable {
    var command: Command
    var input: String?
    var output: String?
    var guitar: [Int] = []
    var backing: [Int] = [1, 2]
    var rate: Double?
    var restarts: Int?
    var seconds: Double?
    var song: String?
    /// Latencia simulada en muestras (con decimales): usa `SimulatedAudioIO` en vez del hardware.
    var simulated: Double?
    /// Retardo del rig simulado, en muestras; con él hay además un canal de referencia interno.
    var simRig: Double?
    /// Solo para probar el fallo: suma estas muestras a la latencia con la que se alinea.
    var simMiscalibration: Double?
    /// Solo Windows (WASAPI, parte 7.10b): modo de compartición (`nil` = compartido) y periodo pedido en fotogramas
    /// (`nil` = `AudioSetup.bufferFrames`, 512; 0 = el mínimo del camino).
    var mode: WASAPIShareMode?
    var period: Int?
    var help = false
}

enum Parse {
    /// `1` o `1,2`: uno o dos canales distintos, desde 1.
    static func channels(_ text: String) throws -> [Int] {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false).map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard (1...2).contains(parts.count), parts.allSatisfy({ ($0 ?? 0) >= 1 }) else {
            throw CLIError("Canales no válidos «\(text)»: uno o dos números desde 1, por ejemplo 1 o 1,2.")
        }
        let list = parts.compactMap { $0 }
        guard Set(list).count == list.count else { throw CLIError("Canales repetidos en «\(text)».") }
        return list
    }

    /// `1,2`: exactamente dos canales distintos.
    static func pair(_ text: String) throws -> [Int] {
        let list = try channels(text)
        guard list.count == 2 else { throw CLIError("El par «\(text)» necesita dos canales, por ejemplo 1,2.") }
        return list
    }

    static func number(_ text: String, _ name: String) throws -> Double {
        guard let v = Double(text.replacingOccurrences(of: ",", with: ".")), v.isFinite else {
            throw CLIError("Valor no válido para \(name): «\(text)».")
        }
        return v
    }

    /// Tope de `--period` (decisión propia: 100 ms a 48 kHz; WASAPI no pasa de 2 s y por encima no sirve para medir).
    static let maxPeriodFrames = 4_800

    /// `shared`/`compartido` o `exclusive`/`exclusivo`.
    static func mode(_ text: String) throws -> WASAPIShareMode {
        switch text.lowercased() {
        case "shared", "compartido": return .shared
        case "exclusive", "exclusivo": return .exclusive
        default: throw CLIError("--mode admite shared (compartido) o exclusive (exclusivo), no «\(text)».")
        }
    }

    static func options(_ args: [String]) throws -> Options {
        var rest = args[...]
        guard let first = rest.popFirst() else { return Options(command: .devices, help: true) }
        if first == "--help" || first == "-h" || first == "help" { return Options(command: .devices, help: true) }
        guard let command = Command(rawValue: first) else {
            throw CLIError("Subcomando desconocido «\(first)». Usa devices, latency, verify o record (--help).")
        }
        var o = Options(command: command)
        func value(_ flag: String) throws -> String {
            guard let v = rest.popFirst() else { throw CLIError("Falta el valor de \(flag).") }
            return v
        }
        while let flag = rest.popFirst() {
            switch flag {
            case "--help", "-h": o.help = true
            case "--in": o.input = try value(flag)
            case "--out": o.output = try value(flag)
            case "--guitar": o.guitar = try channels(try value(flag))
            case "--backing": o.backing = try pair(try value(flag))
            case "--rate":
                let r = try number(try value(flag), flag)
                guard r == 44_100 || r == 48_000 else { throw CLIError("--rate admite 44100 o 48000, no \(Int(r)).") }
                o.rate = r
            case "--restarts":
                guard let n = Int(try value(flag)), n >= 1 else { throw CLIError("--restarts necesita un entero de 1 en adelante.") }
                o.restarts = n
            case "--seconds":
                let s = try number(try value(flag), flag)
                guard s > 0 else { throw CLIError("--seconds debe ser mayor que 0.") }
                o.seconds = s
            case "--song": o.song = try value(flag)
            case "--simulated":
                let l = try number(try value(flag), flag)
                guard l >= 100 else { throw CLIError("--simulated: la latencia debe ser de 100 muestras o más.") }
                o.simulated = l
            case "--sim-rig":
                let r = try number(try value(flag), flag)
                guard r >= 0 else { throw CLIError("--sim-rig no puede ser negativo.") }
                o.simRig = r
            case "--sim-miscalibrate": o.simMiscalibration = try number(try value(flag), flag)
            case "--mode": o.mode = try mode(try value(flag))
            case "--period":
                guard let n = Int(try value(flag)), (0...maxPeriodFrames).contains(n) else {
                    throw CLIError("--period necesita un entero de 0 (el mínimo) a \(maxPeriodFrames) fotogramas.")
                }
                o.period = n
            default: throw CLIError("Opción desconocida «\(flag)» (--help).")
            }
        }
        if o.simulated == nil, o.simRig != nil || o.simMiscalibration != nil {
            throw CLIError("--sim-rig y --sim-miscalibrate solo valen con --simulated.")
        }
        if o.simulated != nil, o.mode != nil || o.period != nil {
            throw CLIError("--mode y --period son de los dispositivos WASAPI (Windows), no de --simulated.")
        }
        if command == .record, o.seconds == nil, !o.help { throw CLIError("record necesita --seconds N.") }
        return o
    }

    /// UID exacto o trozo del nombre sin distinguir mayúsculas. Varias coincidencias o ninguna: error con la lista.
    static func device(_ query: String, in devices: [AudioDevice], role: String) throws -> AudioDevice {
        if let exact = devices.first(where: { $0.uid == query }) { return exact }
        let q = query.lowercased()
        let named = devices.filter { $0.name.lowercased() == q }
        if named.count == 1 { return named[0] }
        let hits = devices.filter { $0.name.lowercased().contains(q) || $0.uid.lowercased().contains(q) }
        if hits.count == 1 { return hits[0] }
        func list(_ ds: [AudioDevice]) -> String { ds.map { "  \($0.uid)  \($0.name)" }.joined(separator: "\n") }
        if hits.isEmpty {
            throw CLIError("Ningún dispositivo de \(role) coincide con «\(query)». Disponibles:\n\(list(devices))")
        }
        throw CLIError("«\(query)» coincide con varios dispositivos de \(role); usa el UID o más nombre:\n\(list(hits))")
    }
}

extension Double {
    func fixed(_ decimals: Int) -> String {
        isFinite ? String(format: "%.\(decimals)f", self).replacingOccurrences(of: ".", with: ",") : "n/d"
    }
}
