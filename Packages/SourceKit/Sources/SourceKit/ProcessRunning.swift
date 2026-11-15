import Darwin
import Foundation

/// Tiempo límite de un helper (spec, «Errores»: 15 s metadatos, 30 s búsqueda, 60 s de descarga sin avance).
public enum ProcessTimeout: Sendable, Equatable {
    /// Desde el lanzamiento.
    case total(TimeInterval)
    /// Sin salida por stdout ni stderr durante ese tiempo.
    case idle(TimeInterval)
}

public struct ProcessRequest: Sendable {
    public var executable: URL
    public var arguments: [String]
    public var timeout: ProcessTimeout?

    public init(executable: URL, arguments: [String], timeout: ProcessTimeout? = nil) {
        self.executable = executable
        self.arguments = arguments
        self.timeout = timeout
    }
}

public struct ProcessResult: Sendable {
    public var status: Int32
    public var stdout: Data
    public var stderr: String

    public init(status: Int32, stdout: Data = Data(), stderr: String = "") {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// Lanza un helper, entrega su salida (`onLine` recibe cada línea de stdout) y lo cancela.
/// Lanza `SourceError.cancelled`, `.timedOut` o `.launchFailed`; un código de salida ≠ 0 no lanza.
public protocol ProcessRunning: Sendable {
    func run(_ request: ProcessRequest, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult
}

public extension ProcessRunning {
    func run(_ request: ProcessRequest) async throws -> ProcessResult { try await run(request, onLine: nil) }
}

/// Implementación real con `Process`. Cancelar la tarea manda SIGTERM y, pasado el margen, SIGKILL
/// (igual que `SeparationRunner`).
public struct SystemProcessRunner: ProcessRunning {
    /// Espera tras SIGTERM antes de SIGKILL.
    public static let terminateGrace: TimeInterval = 5
    /// Bytes de stderr que se conservan.
    static let stderrTailBytes = 64 * 1024

    private let grace: TimeInterval

    public init(terminateGrace: TimeInterval = SystemProcessRunner.terminateGrace) { grace = terminateGrace }

    public func run(_ request: ProcessRequest, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        let session = ProcessSession(request: request, grace: grace, onLine: onLine)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { session.start($0) }
        } onCancel: {
            session.cancel()
        }
    }
}

private final class ProcessSession: @unchecked Sendable {
    private let lock = NSLock()
    private let request: ProcessRequest
    private let grace: TimeInterval
    private let onLine: (@Sendable (String) -> Void)?
    private let process = Process()
    private var continuation: CheckedContinuation<ProcessResult, Error>?
    private var stdout = Data(), stderr = Data(), lineBuffer = Data()
    private var stdoutEOF = false, stderrEOF = false
    private var exit: (reason: Process.TerminationReason, status: Int32)?
    private var cancelled = false, timedOut = false, completed = false, launched = false
    private var lastActivity = Date()
    private var timer: DispatchSourceTimer?

    init(request: ProcessRequest, grace: TimeInterval, onLine: (@Sendable (String) -> Void)?) {
        self.request = request
        self.grace = grace
        self.onLine = onLine
    }

    func start(_ continuation: CheckedContinuation<ProcessResult, Error>) {
        lock.lock()
        if cancelled { lock.unlock(); continuation.resume(throwing: SourceError.cancelled); return }
        self.continuation = continuation
        lock.unlock()

        process.executableURL = request.executable
        process.arguments = request.arguments
        process.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        out.fileHandleForReading.readabilityHandler = { [self] h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; closed(stdout: true) } else { received(stdout: d) }
        }
        err.fileHandleForReading.readabilityHandler = { [self] h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; closed(stdout: false) } else { received(stderr: d) }
        }
        process.terminationHandler = { [self] p in
            lock.withLock { exit = (p.terminationReason, p.terminationStatus) }
            tryComplete()
        }
        do {
            try process.run()
        } catch {
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            finish(.failure(SourceError.launchFailed(error.localizedDescription)))
            return
        }
        let wasCancelled: Bool = lock.withLock { launched = true; lastActivity = Date(); return cancelled }
        if wasCancelled { terminate() }
        if let timeout = request.timeout { startTimer(timeout) }
    }

    func cancel() {
        let launched: Bool = lock.withLock { cancelled = true; return self.launched }
        if launched { terminate() }
    }

    private func startTimer(_ timeout: ProcessTimeout) {
        let t = DispatchSource.makeTimerSource(queue: .global())
        t.schedule(deadline: .now() + 0.1, repeating: 0.1)
        t.setEventHandler { [self] in
            let started: Date = lock.withLock { lastActivity }
            let (limit, since): (TimeInterval, Date)
            switch timeout {
            case .total(let s): (limit, since) = (s, launchDate)
            case .idle(let s): (limit, since) = (s, started)
            }
            if Date().timeIntervalSince(since) >= limit {
                lock.withLock { timedOut = true }
                terminate()
                t.cancel()
            }
        }
        lock.withLock { timer = t }
        t.resume()
    }

    private let launchDate = Date()

    /// SIGTERM ahora y SIGKILL si sigue vivo pasado el margen.
    private func terminate() {
        let pid: pid_t? = lock.withLock { exit == nil ? process.processIdentifier : nil }
        guard let pid, pid > 0 else { return }
        Darwin.kill(pid, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + grace) { [self] in
            if lock.withLock({ exit == nil }) { Darwin.kill(pid, SIGKILL) }
        }
    }

    private func received(stdout data: Data) {
        var lines: [String] = []
        lock.withLock {
            lastActivity = Date()
            stdout.append(data)
            lineBuffer.append(data)
            while let nl = lineBuffer.firstIndex(of: 0x0A) {
                lines.append(String(decoding: lineBuffer[lineBuffer.startIndex..<nl], as: UTF8.self))
                lineBuffer.removeSubrange(lineBuffer.startIndex...nl)
            }
        }
        if let onLine { for l in lines { onLine(l) } }
    }

    private func received(stderr data: Data) {
        lock.withLock {
            lastActivity = Date()
            stderr.append(data)
            if stderr.count > SystemProcessRunner.stderrTailBytes {
                stderr = Data(stderr.suffix(SystemProcessRunner.stderrTailBytes))
            }
        }
    }

    private func closed(stdout isStdout: Bool) {
        lock.withLock { if isStdout { stdoutEOF = true } else { stderrEOF = true } }
        tryComplete()
    }

    private func tryComplete() {
        let result: Result<ProcessResult, Error>? = lock.withLock {
            guard !completed, let exit, stdoutEOF, stderrEOF else { return nil }
            completed = true
            timer?.cancel()
            if cancelled { return .failure(SourceError.cancelled) }
            if timedOut { return .failure(SourceError.timedOut) }
            let code = exit.reason == .uncaughtSignal ? 128 + exit.status : exit.status
            return .success(ProcessResult(status: code, stdout: stdout, stderr: String(decoding: stderr, as: UTF8.self)))
        }
        if let result { finish(result) }
    }

    private func finish(_ result: Result<ProcessResult, Error>) {
        let c: CheckedContinuation<ProcessResult, Error>? = lock.withLock {
            completed = true
            defer { continuation = nil }
            return continuation
        }
        c?.resume(with: result)
    }
}

/// Respuesta grabada para `ScriptedProcessRunner`.
public struct ScriptedResponse: Sendable {
    public var stdout: String
    public var stderr: String
    public var status: Int32
    /// Líneas que se entregan a `onLine` antes de terminar (progreso).
    public var progressLines: [String]
    /// Efecto sobre el disco (p. ej. crear el fichero que «descargaría» el helper).
    public var sideEffect: (@Sendable (ProcessRequest) throws -> Void)?
    /// No termina hasta que se cancela la tarea.
    public var hangs: Bool

    public init(stdout: String = "", stderr: String = "", status: Int32 = 0, progressLines: [String] = [],
                sideEffect: (@Sendable (ProcessRequest) throws -> Void)? = nil, hangs: Bool = false) {
        self.stdout = stdout
        self.stderr = stderr
        self.status = status
        self.progressLines = progressLines
        self.sideEffect = sideEffect
        self.hangs = hangs
    }
}

/// Versión simulada: responde con lo grabado, sin lanzar nada. Una regla casa si su texto está contenido en
/// `<nombre del ejecutable> <argumentos separados por espacios>`; gana la primera que case. Sin regla: código 127.
public final class ScriptedProcessRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var rules: [(needle: String, response: ScriptedResponse)] = []
    private var log: [ProcessRequest] = []

    public init() {}

    public func on(_ needle: String, _ response: ScriptedResponse) {
        lock.withLock { rules.append((needle, response)) }
    }

    /// Peticiones recibidas, en orden.
    public var requests: [ProcessRequest] { lock.withLock { log } }

    public func run(_ request: ProcessRequest, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        let key = ([request.executable.lastPathComponent] + request.arguments).joined(separator: " ")
        let response: ScriptedResponse? = lock.withLock {
            log.append(request)
            return rules.first { key.contains($0.needle) }?.response
        }
        guard let response else {
            return ProcessResult(status: 127, stderr: "ScriptedProcessRunner: sin regla para \(key)")
        }
        if Task.isCancelled { throw SourceError.cancelled }
        if response.hangs {
            do { while true { try await Task.sleep(for: .milliseconds(10)) } } catch { throw SourceError.cancelled }
        }
        for l in response.progressLines { onLine?(l) }
        try response.sideEffect?(request)
        return ProcessResult(status: response.status, stdout: Data(response.stdout.utf8), stderr: response.stderr)
    }
}
