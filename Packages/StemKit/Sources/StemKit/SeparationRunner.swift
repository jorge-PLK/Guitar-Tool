import Darwin
import Foundation

/// Eventos de una separación lanzada con `SeparationRunner`.
public enum SeparationEvent: Sendable, Equatable {
    /// El helper está cargando el modelo.
    case loading
    /// Fracción de trozos completados, de 0 a 1.
    case progress(Double)
    /// El helper terminó bien. `seconds`: duración de la separación según el helper;
    /// `peakBytes`: pico de memoria del helper medido por `MemoryGuard`.
    case finished(seconds: Double, peakBytes: UInt64)
}

public enum SeparationError: Error, Sendable, Equatable {
    /// `MemoryGuard` mató al helper por pasar del límite.
    case memoryLimitExceeded(peakBytes: UInt64)
    /// El helper salió con un código ≠ 0 (o 128 + señal si murió por una señal).
    case helperFailed(code: Int32, stderrTail: String)
    case cancelled
    case invalidInput(String)
}

/// Lado de la app: lanza `tf-separate` en un proceso aparte por tema, interpreta su JSON de progreso y
/// lo vigila con `MemoryGuard`. Si pasa del límite se le mata sin afectar a la app.
public struct SeparationRunner: Sendable {
    /// Espera tras SIGTERM antes de mandar SIGKILL al cancelar.
    static let terminateGrace: Double = 5
    /// Bytes de stderr que se conservan para `helperFailed`.
    static let stderrTailBytes = 4096

    public let helperURL: URL
    public let memoryLimitBytes: UInt64
    /// Solo tests: periodo de sondeo de `MemoryGuard` y aviso con el pid del helper al lanzarlo.
    var guardInterval: Double = MemoryGuard.defaultInterval
    var onLaunch: (@Sendable (pid_t) -> Void)?

    public init(helperURL: URL, memoryLimitBytes: UInt64 = MemoryGuard.defaultLimitBytes) {
        self.helperURL = helperURL
        self.memoryLimitBytes = memoryLimitBytes
    }

    /// Separa `input` con el modelo compilado `model` y deja `<stem>.wav` en `outputDirectory`.
    /// Cancelar el Task que consume el stream manda SIGTERM al helper y, si no sale en 5 s, SIGKILL.
    public func run(model: URL, input: URL, outputDirectory: URL) -> AsyncThrowingStream<SeparationEvent, Error> {
        let fm = FileManager.default
        for (what, url) in [("modelo", model), ("entrada", input)] where !fm.fileExists(atPath: url.path) {
            return Self.failed(.invalidInput("no existe el \(what): \(url.path)"))
        }
        return launch(arguments: ["--model", model.path, "--input", input.path, "--out", outputDirectory.path])
    }

    static func failed(_ error: SeparationError) -> AsyncThrowingStream<SeparationEvent, Error> {
        AsyncThrowingStream { $0.finish(throwing: error) }
    }

    /// Lanza el helper con `arguments` tal cual (los tests añaden los flags de simulación).
    func launch(arguments: [String]) -> AsyncThrowingStream<SeparationEvent, Error> {
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            return Self.failed(.invalidInput("no existe el helper: \(helperURL.path)"))
        }
        let helperURL = helperURL, limit = memoryLimitBytes, interval = guardInterval, onLaunch = onLaunch
        return AsyncThrowingStream { continuation in
            let run = HelperRun(continuation: continuation)
            let process = Process()
            process.executableURL = helperURL
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            out.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty { h.readabilityHandler = nil; run.stdoutClosed() } else { run.stdout(d) }
            }
            err.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty { h.readabilityHandler = nil; run.stderrClosed() } else { run.stderr(d) }
            }
            process.terminationHandler = { p in
                run.exited(reason: p.terminationReason, status: p.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                continuation.finish(throwing: SeparationError.helperFailed(
                    code: -1, stderrTail: "no se pudo lanzar el helper: \(error.localizedDescription)"))
                return
            }
            let pid = process.processIdentifier
            let memGuard = MemoryGuard(pid: pid, limitBytes: limit, interval: interval)
            run.started(process: process, guard: memGuard)
            memGuard.start()
            onLaunch?(pid)
            continuation.onTermination = { reason in
                if case .cancelled = reason { run.cancel() }
            }
        }
    }
}

/// Estado de una ejecución del helper. Termina el stream cuando el proceso ha salido y sus dos
/// tuberías han llegado a EOF (así no se pierde la última línea de stdout ni la cola de stderr).
private final class HelperRun: @unchecked Sendable {
    private struct Message: Decodable {
        let stage: String
        let chunk: Int?
        let of: Int?
        let seconds: Double?
    }

    private let lock = NSLock()
    private let continuation: AsyncThrowingStream<SeparationEvent, Error>.Continuation
    private var process: Process?
    private var memGuard: MemoryGuard?
    private var pid: pid_t = 0
    private var lineBuffer = Data()
    private var stderrTail = Data()
    private var stdoutEOF = false, stderrEOF = false
    private var exit: (reason: Process.TerminationReason, status: Int32)?
    private var doneSeconds: Double?
    private var cancelled = false
    private var completed = false

    init(continuation: AsyncThrowingStream<SeparationEvent, Error>.Continuation) {
        self.continuation = continuation
    }

    func started(process: Process, guard g: MemoryGuard) {
        lock.withLock {
            self.process = process
            self.memGuard = g
            self.pid = process.processIdentifier
        }
        tryComplete()   // por si el proceso ya terminó antes de llegar aquí
    }

    func stdout(_ data: Data) {
        var events: [SeparationEvent] = []
        lock.withLock {
            lineBuffer.append(data)
            while let nl = lineBuffer.firstIndex(of: 0x0A) {
                let line = lineBuffer[lineBuffer.startIndex..<nl]
                lineBuffer.removeSubrange(lineBuffer.startIndex...nl)
                guard let msg = try? JSONDecoder().decode(Message.self, from: Data(line)) else { continue }
                switch msg.stage {
                case "loading": events.append(.loading)
                case "separating":
                    if let k = msg.chunk, let n = msg.of, n > 0 { events.append(.progress(Double(k) / Double(n))) }
                case "done": doneSeconds = msg.seconds ?? 0
                default: break
                }
            }
        }
        for e in events { continuation.yield(e) }
    }

    func stderr(_ data: Data) {
        lock.withLock {
            stderrTail.append(data)
            if stderrTail.count > SeparationRunner.stderrTailBytes {
                stderrTail = Data(stderrTail.suffix(SeparationRunner.stderrTailBytes))
            }
        }
    }

    func stdoutClosed() { lock.withLock { stdoutEOF = true }; tryComplete() }
    func stderrClosed() { lock.withLock { stderrEOF = true }; tryComplete() }

    func exited(reason: Process.TerminationReason, status: Int32) {
        lock.withLock { exit = (reason, status) }
        tryComplete()
    }

    /// SIGTERM ahora y SIGKILL si sigue vivo pasado el margen.
    func cancel() {
        let target: pid_t? = lock.withLock {
            cancelled = true
            return exit == nil && pid > 0 ? pid : nil
        }
        guard let pid = target else { return }
        Darwin.kill(pid, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + SeparationRunner.terminateGrace) { [self] in
            let alive = lock.withLock { exit == nil }
            if alive { Darwin.kill(pid, SIGKILL) }
        }
    }

    private func tryComplete() {
        let outcome: Result<SeparationEvent, SeparationError>? = lock.withLock {
            guard !completed, let exit, stdoutEOF, stderrEOF, let memGuard else { return nil }
            completed = true
            memGuard.stop()
            process = nil
            let peak = memGuard.peakBytes
            let tail = String(decoding: stderrTail, as: UTF8.self)
            if memGuard.limitExceeded { return .failure(.memoryLimitExceeded(peakBytes: peak)) }
            if cancelled { return .failure(.cancelled) }
            if exit.reason == .exit, exit.status == 0, let s = doneSeconds {
                return .success(.finished(seconds: s, peakBytes: peak))
            }
            let code = exit.reason == .uncaughtSignal ? 128 + exit.status : exit.status
            return .failure(.helperFailed(code: code, stderrTail: tail))
        }
        switch outcome {
        case nil: return
        case .success(let event)?:
            continuation.yield(event)
            continuation.finish()
        case .failure(let error)?:
            continuation.finish(throwing: error)
        }
    }
}
