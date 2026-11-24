import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol ModelDownloading: Sendable {
    func download(from: URL, to: URL, progress: @escaping @Sendable (Double) -> Void) async throws
}

public protocol ModelCompiling: Sendable {
    /// Compila un `.mlpackage` y devuelve la URL del `.mlmodelc` resultante.
    func compile(_ mlpackage: URL) async throws -> URL
}

public enum ModelDownloadError: Error, LocalizedError, Equatable {
    case httpStatus(Int)
    public var errorDescription: String? {
        switch self {
        case .httpStatus(let s): return "El servidor respondió con el código HTTP \(s)."
        }
    }
}

/// Fallo al obtener un modelo, con el nombre visible del modelo y qué pasó (llega tal cual al job y a la página).
public struct ModelUnavailableError: Error, LocalizedError, Equatable {
    public enum Reason: Sendable, Equatable {
        case http(Int)
        case offline
        case other(String)
    }

    public let modelName: String
    public let reason: Reason

    public init(modelName: String, reason: Reason) {
        self.modelName = modelName
        self.reason = reason
    }

    public var errorDescription: String? {
        switch reason {
        case .http(let s): return "No se pudo descargar el modelo «\(modelName)» (HTTP \(s))."
        case .offline: return "Falta el modelo «\(modelName)» y no hay conexión."
        case .other(let m): return "No se pudo preparar el modelo «\(modelName)»: \(m)"
        }
    }

    /// Nombre visible: el del catálogo si el id existe; si no, el propio id.
    public static func displayName(forModelID id: String) -> String {
        ModelCatalog.all.first { $0.id == id }?.displayName ?? id
    }

    /// Envuelve un error de `ModelStore.ensureInstalled`; la cancelación y los errores ya con nombre pasan sin cambios.
    public static func wrapping(_ error: Error, modelID: String) -> Error {
        if error is CancellationError || error is ModelUnavailableError { return error }
        let name = displayName(forModelID: modelID)
        if let d = error as? ModelDownloadError, case .httpStatus(let s) = d {
            return ModelUnavailableError(modelName: name, reason: .http(s))
        }
        if let u = error as? URLError, offlineCodes.contains(u.code) {
            return ModelUnavailableError(modelName: name, reason: .offline)
        }
        return ModelUnavailableError(modelName: name, reason: .other(error.localizedDescription))
    }

    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
        .dnsLookupFailed, .timedOut, .internationalRoamingOff,
    ]
}

/// Descarga con `URLSessionDownloadTask` (sigue redirecciones) e informa del progreso.
public struct URLSessionDownloader: ModelDownloading {
    public init() {}

    public func download(from url: URL, to destination: URL,
                         progress: @escaping @Sendable (Double) -> Void) async throws {
        let delegate = DownloadDelegate(destination: destination, progress: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.downloadTask(with: url)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                delegate.start(cont)
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
        progress(1)
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let progress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var moveError: Error?
    private var last = 0.0

    init(destination: URL, progress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.progress = progress
    }

    func start(_ cont: CheckedContinuation<Void, Error>) {
        lock.lock(); continuation = cont; lock.unlock()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let p = min(0.999, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        lock.lock()
        let advance = p > last
        if advance { last = p }
        lock.unlock()
        if advance { progress(p) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        do {
            if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw ModelDownloadError.httpStatus(http.statusCode)
            }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            lock.lock(); moveError = error; lock.unlock()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let cont = continuation
        continuation = nil
        let failure = error ?? moveError
        lock.unlock()
        if let failure { cont?.resume(throwing: failure) } else { cont?.resume() }
    }
}
