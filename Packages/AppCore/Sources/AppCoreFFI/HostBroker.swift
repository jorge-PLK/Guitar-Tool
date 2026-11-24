import AppCore
import Foundation

/// `HostServices` de AppCore sobre el puerto de Dart (arquitectura.md, «Servicios de anfitrión»): cada llamada sale como
/// `{hostRequest:{id,method,params}}` y se resuelve con el `{hostResponse:{id,result|error}}` que llega por `tf_core_send`.
/// No bloquea ningún hilo: la llamada espera en una continuación y `resolve` la reanuda desde el hilo de Dart.
///
/// Métodos de `hostRequest` (el nombre es el de `HostServices`): `pickFile {types}` -> `{path}`; `pickFiles {types}` ->
/// `{paths}`; `pickFolder {initial}` -> `{path}`; `projectsFolderChanged {path}` -> `{ok}`; `saveFile {suggestedName,types}`
/// -> `{path}`; `openURL {url}` -> `{opened}`; `showPreview {url,rect}` -> `{shown}`; `hidePreview {}`;
/// `load {url,userAgent,readyScript,timeout}` -> `{status,html}`. Error: `{code,message,status?}`; en `load`, `code` es uno de
/// `offline`, `readyTimeout`, `httpStatus`, `cancelled`, `unsupported`.
/// Respuesta JSON de Dart (solo valores de JSON, inmutables una vez creada).
struct Reply: @unchecked Sendable { var value: [String: Any] }

final class HostBroker: HostServices, @unchecked Sendable {
    private let lock = NSLock()
    private var nextID: Int64 = 0
    private var pending: [Int64: CheckedContinuation<Reply, Never>] = [:]
    nonisolated(unsafe) var emit: @Sendable (String) -> Void = { _ in }

    /// Envía la petición y espera la respuesta. `[:]` con `error` si el núcleo se cierra antes de que llegue.
    func request(_ method: String, _ params: [String: Any] = [:]) async -> [String: Any] {
        let reply: Reply = await withCheckedContinuation { cont in
            lock.lock()
            nextID += 1
            let id = nextID
            pending[id] = cont
            lock.unlock()
            let msg: [String: Any] = ["hostRequest": ["id": id, "method": method, "params": params]]
            guard let data = try? JSONSerialization.data(withJSONObject: msg), let text = String(data: data, encoding: .utf8) else {
                resolve(id: id, response: ["error": ["code": "internal", "message": "Petición no serializable."]])
                return
            }
            emit(text)
        }
        return reply.value
    }

    /// `{hostResponse:{id,result|error}}`. `false` si el mensaje no tiene esa forma (entonces va a `Bridge.receive`).
    func resolve(_ json: String) -> Bool {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let r = obj["hostResponse"] as? [String: Any],
              let id = (r["id"] as? NSNumber)?.int64Value else { return false }
        resolve(id: id, response: r)
        return true
    }

    private func resolve(id: Int64, response: [String: Any]) {
        lock.lock(); let cont = pending.removeValue(forKey: id); lock.unlock()
        cont?.resume(returning: Reply(value: response))
    }

    /// Cierre del núcleo: nadie va a responder.
    func failAll() {
        lock.lock(); let all = pending; pending = [:]; lock.unlock()
        for (_, c) in all { c.resume(returning: Reply(value: ["error": ["code": "cancelled", "message": "El núcleo se cierra."]])) }
    }

    private static func result(_ r: [String: Any]) -> [String: Any]? { r["result"] as? [String: Any] }
    private static func path(_ r: [String: Any]) -> URL? {
        (result(r)?["path"] as? String).map { URL(fileURLWithPath: $0) }
    }

    func pickFile(types: [String]) async -> URL? { Self.path(await request("pickFile", ["types": types])) }

    func pickFiles(types: [String]) async -> [URL] {
        let paths = Self.result(await request("pickFiles", ["types": types]))?["paths"] as? [String] ?? []
        return paths.map { URL(fileURLWithPath: $0) }
    }

    func pickFolder() async -> URL? { await pickFolder(initial: nil) }

    func pickFolder(initial: URL?) async -> URL? {
        Self.path(await request("pickFolder", initial.map { ["initial": $0.path] } ?? [:]))
    }

    func projectsFolderChanged(_ url: URL) async -> Bool {
        Self.result(await request("projectsFolderChanged", ["path": url.path]))?["ok"] as? Bool ?? false
    }

    func saveFile(suggestedName: String, types: [String]) async -> URL? {
        Self.path(await request("saveFile", ["suggestedName": suggestedName, "types": types]))
    }

    func openURL(_ url: URL) async -> Bool {
        Self.result(await request("openURL", ["url": url.absoluteString]))?["opened"] as? Bool ?? false
    }

    func showPreview(url: URL, rect: PreviewRect) async -> Bool {
        let rectJSON: [String: Any] = ["x": rect.x, "y": rect.y, "width": rect.width, "height": rect.height]
        return Self.result(await request("showPreview", ["url": url.absoluteString, "rect": rectJSON]))?["shown"] as? Bool ?? false
    }

    func hidePreview() async { _ = await request("hidePreview") }

    func load(url: URL, userAgent: String?, readyScript: String?, timeout: TimeInterval) async throws -> HiddenPage {
        var params: [String: Any] = ["url": url.absoluteString, "timeout": timeout]
        if let userAgent { params["userAgent"] = userAgent }
        if let readyScript { params["readyScript"] = readyScript }
        let r = await request("load", params)
        if let e = r["error"] as? [String: Any] {
            switch e["code"] as? String {
            case "offline": throw HiddenPageError.offline
            case "readyTimeout": throw HiddenPageError.readyTimeout
            case "httpStatus": throw HiddenPageError.httpStatus((e["status"] as? Int) ?? 0)
            case "cancelled": throw HiddenPageError.cancelled
            default: throw HiddenPageError.unsupported
            }
        }
        guard let res = Self.result(r), let status = res["status"] as? Int, let html = res["html"] as? String else {
            throw HiddenPageError.unsupported
        }
        return HiddenPage(status: status, html: html)
    }
}
