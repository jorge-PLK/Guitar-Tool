import Foundation
import P2Core

/// Argumentos `--clave valor` y banderas `--clave`.
struct Args {
    var values: [String: String] = [:]
    var positional: [String] = []

    init(_ a: [String]) {
        var i = 0
        while i < a.count {
            if a[i].hasPrefix("--") {
                let k = String(a[i].dropFirst(2))
                if i + 1 < a.count, !a[i + 1].hasPrefix("--") { values[k] = a[i + 1]; i += 2 } else { values[k] = "true"; i += 1 }
            } else { positional.append(a[i]); i += 1 }
        }
    }

    func string(_ k: String) -> String? { values[k] }
    func require(_ k: String) throws -> String {
        guard let v = values[k] else { throw Failure("Falta --\(k).") }
        return v
    }
    func double(_ k: String, default d: Double? = nil) throws -> Double {
        guard let s = values[k] else { if let d { return d }; throw Failure("Falta --\(k).") }
        guard let v = Double(s), v.isFinite else { throw Failure("--\(k) no es un número: \(s)") }
        return v
    }
    func int(_ k: String, default d: Int? = nil) throws -> Int {
        guard let s = values[k] else { if let d { return d }; throw Failure("Falta --\(k).") }
        guard let v = Int(s) else { throw Failure("--\(k) no es un entero: \(s)") }
        return v
    }
    func flag(_ k: String) -> Bool { values[k] != nil }

    /// Canales 1-based ("1,2") → índices 0-based.
    func channels(_ k: String, max: Int) throws -> [Int] {
        let parts = try require(k).split(separator: ",").map { s -> Int in
            guard let v = Int(s.trimmingCharacters(in: .whitespaces)) else { throw Failure("--\(k): \"\(s)\" no es un canal.") }
            return v
        }
        guard !parts.isEmpty else { throw Failure("--\(k) vacío.") }
        for v in parts where v < 1 || v > max { throw Failure("--\(k): canal \(v) fuera de 1...\(max).") }
        return parts.map { $0 - 1 }
    }
}

/// Consola + fichero de log (`<out>/p2.log`), sin redirecciones del shell.
enum Log {
    static var file: URL?

    static func setDir(_ dir: URL) { file = dir.appendingPathComponent("p2.log") }

    static func say(_ s: String) {
        print(s)
        guard let f = file else { return }
        let line = Data((s + "\n").utf8)
        if let h = try? FileHandle(forWritingTo: f) {
            h.seekToEndOfFile(); h.write(line); try? h.close()
        } else {
            try? line.write(to: f)
        }
    }
}

enum Out {
    static func dir(_ path: String) throws -> URL {
        let u = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        Log.setDir(u)
        return u
    }

    /// Sustituye NaN/inf por null y escribe JSON ordenado.
    static func json(_ obj: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: clean(obj), options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }

    static func clean(_ v: Any) -> Any {
        switch v {
        case let d as Double: return d.isFinite ? d : NSNull()
        case let f as Float: return f.isFinite ? Double(f) : NSNull()
        case let a as [Any]: return a.map(clean)
        case let m as [String: Any]: return m.mapValues(clean)
        default: return v
        }
    }

    static func writeChannels(_ chans: [[Float]], fs: Double, to dir: URL) throws {
        for (i, x) in chans.enumerated() {
            try WAV.write(x, sampleRate: fs, to: dir.appendingPathComponent(String(format: "ch%02d.wav", i + 1)))
        }
    }
}

func f1(_ v: Double) -> String { v.isFinite ? String(format: "%.1f", v) : "n/d" }
func f2(_ v: Double) -> String { v.isFinite ? String(format: "%.2f", v) : "n/d" }
func iso8601() -> String { ISO8601DateFormatter().string(from: Date()) }

func deviceHeader(_ d: DeviceInfo) -> [String: Any] {
    ["name": d.name, "uid": d.uid, "nominalRate": d.nominalRate, "inputChannels": d.inputChannels,
     "outputChannels": d.outputChannels, "bufferFrames": Int(d.bufferFrames), "date": iso8601()]
}

func rmsDb(_ x: [Float]) -> Double {
    guard !x.isEmpty else { return -240 }
    return dB((x.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(x.count)).squareRoot())
}

func peakDb(_ x: [Float]) -> Double { dB(Double(x.reduce(0) { max($0, abs($1)) })) }

func sessionJSON(_ r: SessionResult) -> [String: Any] {
    ["frames": r.frames, "callbacks": r.callbacks, "bufferFrames": Int(r.bufferFrames),
     "overloadNotifications": r.overloads, "gapCount": r.gapCount,
     "gapMissingFramesTotal": r.gaps.reduce(0) { $0 + $1.missingFrames },
     "gaps": r.gaps.prefix(100).map { ["atFrame": $0.atFrame, "missingFrames": $0.missingFrames] },
     "allInputsExactZero": r.allInputsExactZero]
}

func reportHealth(_ r: SessionResult) {
    Log.say("  sobrecargas (overload): \(r.overloads) · huecos/discontinuidades: \(r.gapCount) (\(r.gaps.reduce(0) { $0 + $1.missingFrames }) muestras) · callbacks: \(r.callbacks)")
    if r.allInputsExactZero {
        Log.say("  AVISO: todas las entradas son cero exacto. ¿Permiso de micrófono denegado para el terminal o pedalera sin audio USB?")
    }
}
