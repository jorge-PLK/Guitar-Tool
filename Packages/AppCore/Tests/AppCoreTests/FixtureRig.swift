import Foundation
import Store
import XCTest
@testable import AppCore

// 0.S2/Ola0.S5: volcado de `Contract/fixtures/<área>/` desde métodos reales del Router.
// Área nueva = fichero nuevo `ContractFixtures+<Área>.swift` con `final class ContractFixtures<Área>Tests: XCTestCase`
// que arma `FixtureRig(area: "<carpeta>")` y llama a `rig.run/runExpectingError/event`. Nada que registrar ni editar aquí.
// Vuelca en `Contract/fixtures/<carpeta>/<método>.{params,result,error,event}.json`; `TF_WRITE_FIXTURES=1` regenera,
// sin la variable compara con el disco y falla si hay deriva.

// MARK: - Dobles

final class FixtureGate: @unchecked Sendable {
    private let lock = NSLock()
    private var open = false
    var isOpen: Bool { lock.withLock { open } }
}

struct FixtureImporter: AudioImporting {
    func importAudio(from source: URL, to destination: URL, sampleRate: Double,
                     progress: @escaping @Sendable (Double) -> Void) async throws -> ImportedAudioInfo {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "wav".write(to: destination, atomically: true, encoding: .utf8)
        progress(1)
        return ImportedAudioInfo(title: nil, artist: nil, duration: 10, sourceFormat: source.pathExtension,
                                 sourceSampleRate: 44100, sourceChannels: 2)
    }
    func resample(_ file: URL, to destination: URL, sampleRate: Double) async throws {
        try "stem".write(to: destination, atomically: true, encoding: .utf8)
    }
}

/// Separador que se queda esperando (puerta cerrada): el trabajo sigue vivo para `jobs.list` y `jobs.cancel`.
struct FixtureSeparator: StemSeparating {
    let gate: FixtureGate
    var modelIdentifier: String? { "fake@1" }
    func separate(input: URL, outputDirectory: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        progress(0.25)
        while !gate.isOpen { try await Task.sleep(for: .milliseconds(10)) }
    }
}

struct FixtureHost: HostServices {
    var file: URL?
    var many: [URL] = []
    func pickFile(types: [String]) async -> URL? { file }
    func pickFiles(types: [String]) async -> [URL] { many }
    func pickFolder() async -> URL? { nil }
    func openURL(_ url: URL) async -> Bool { url.scheme == "spotify" }
    func showPreview(url: URL, rect: PreviewRect) async -> Bool { true }
}

// MARK: - Volcado

enum FixtureKind: String { case params, result, error, event }

struct FixtureRig {
    let dir: URL
    let projects: URL
    let bridge: Bridge
    let area: String

    init(area: String) throws {
        self.area = area
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("appcore-fixtures-\(UUID().uuidString)", isDirectory: true)
        projects = dir.appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let services = JobServices(importer: FixtureImporter(), separator: FixtureSeparator(gate: FixtureGate()),
                                   levelMeter: nil, analyzer: nil, guitarSplitter: nil)
        bridge = try Bridge(options: LaunchOptions(projectsFolder: projects, supportDir: dir.appendingPathComponent("Support")),
                            mediaBase: "https://tf.media/", reveal: nil, services: services)
    }

    func cleanup() { try? FileManager.default.removeItem(at: dir) }

    /// Raíz del repo a partir de este fichero: Packages/AppCore/Tests/AppCoreTests/<este>.
    static var fixturesRoot: URL {
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { u.deleteLastPathComponent() }
        return u.appendingPathComponent("Contract/fixtures", isDirectory: true)
    }

    // Normalización: sin rutas de la máquina, con UUID ordinales y fechas fijas.
    static let uuidRegex = try! NSRegularExpression(pattern: "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")
    static let dateRegex = try! NSRegularExpression(pattern: "\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z")

    func normalize(_ text: String) -> String {
        var s = text
        for p in Set([dir.path, dir.resolvingSymlinksInPath().path]).sorted(by: { $0.count > $1.count }) {
            s = s.replacingOccurrences(of: p, with: "/<dir>")
        }
        s = Self.dateRegex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s),
                                                    withTemplate: "2026-01-01T00:00:00Z")
        var seen: [String] = []
        let ns = s as NSString
        for m in Self.uuidRegex.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            let id = ns.substring(with: m.range).uppercased()
            if !seen.contains(id) { seen.append(id) }
        }
        // Dos pasos para que un UUID sustituido no coincida con otro aún por sustituir.
        for (i, id) in seen.enumerated() {
            s = s.replacingOccurrences(of: id, with: "<uuid\(i + 1)>", options: .caseInsensitive)
        }
        for i in seen.indices {
            s = s.replacingOccurrences(of: "<uuid\(i + 1)>", with: String(format: "00000000-0000-0000-0000-%012d", i + 1))
        }
        return s
    }

    /// JSON canónico: claves ordenadas, sangría de 2 espacios, salto de línea final.
    func canonical(_ json: String) throws -> String {
        let value = try JSONSerialization.jsonObject(with: Data(normalize(json).utf8), options: [.fragmentsAllowed])
        let data = try JSONSerialization.data(withJSONObject: value,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    func golden(_ name: String, _ kind: FixtureKind, _ json: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let url = Self.fixturesRoot.appendingPathComponent(area).appendingPathComponent("\(name).\(kind.rawValue).json")
        let text = try canonical(json)
        if ProcessInfo.processInfo.environment["TF_WRITE_FIXTURES"] == "1" {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        } else {
            let onDisk = try? String(contentsOf: url, encoding: .utf8)
            XCTAssertEqual(onDisk, text, "Deriva del contrato en \(area)/\(name).\(kind.rawValue).json (TF_WRITE_FIXTURES=1 para regenerar)",
                           file: file, line: line)
        }
    }

    /// Llama al Router real y vuelca params y result (o error). Devuelve el objeto de respuesta.
    @discardableResult
    func run(_ method: String, params: String = "{}", paramsOnly: Bool = false,
             file: StaticString = #filePath, line: UInt = #line) async throws -> [String: Any] {
        try golden(method, .params, params, file: file, line: line)
        if paramsOnly { return [:] }
        let r = await bridge.router.handle("{\"id\":1,\"method\":\"\(method)\",\"params\":\(params)}")
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(r.utf8)) as? [String: Any])
        if let e = o["error"] {
            try golden(method, .error, try Self.text(e), file: file, line: line)
        } else {
            try golden(method, .result, try Self.text(try XCTUnwrap(o["result"])), file: file, line: line)
        }
        return o
    }

    /// Variante que espera un error y vuelca solo `<método>.error.json` (los params ya se volcaron o no importan).
    func runExpectingError(_ method: String, params: String, file: StaticString = #filePath, line: UInt = #line) async throws {
        let r = await bridge.router.handle("{\"id\":1,\"method\":\"\(method)\",\"params\":\(params)}")
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(r.utf8)) as? [String: Any])
        let e = try XCTUnwrap(o["error"], "\(method) debía fallar", file: file, line: line)
        try golden(method, .error, try Self.text(e), file: file, line: line)
    }

    func event<T: Encodable>(_ name: String, _ payload: T, file: StaticString = #filePath, line: UInt = #line) throws {
        let m = try XCTUnwrap(Router.eventMessage(name, payload))
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(m.utf8)) as? [String: Any])
        XCTAssertEqual(o["event"] as? String, name)
        try golden(name, .event, try Self.text(try XCTUnwrap(o["payload"])), file: file, line: line)
    }

    static func text(_ any: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: any, options: [.fragmentsAllowed, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    func jsonString(_ s: String) -> String {
        String(decoding: (try? JSONEncoder().encode(s)) ?? Data(), as: UTF8.self)
    }
}
