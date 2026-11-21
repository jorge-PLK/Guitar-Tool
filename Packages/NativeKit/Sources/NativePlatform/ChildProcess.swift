import Foundation
#if canImport(Darwin)
import Darwin
#elseif os(Windows)
import WinSDK
import CChildProcess
#endif

/// Proceso hijo que, al terminarlo, se lleva también a sus descendientes (plan, «Fase 7c», mini-spec:
/// «`Process` con Job Object para que mueran los nietos»): yt-dlp lanza ffmpeg, y matar solo al padre los
/// dejaba huérfanos.
///
/// Se configura `process` como un `Process` normal (ejecutable, argumentos, entorno, directorio, tuberías) y se
/// lanza con `run()`, no con `process.run()`. El aviso de salida va en `terminationHandler` de este objeto, y el
/// estado se lee de este objeto (`terminationStatus`, `terminationReason`, `isRunning`), no de `process`.
/// - Mac: se lanza `process` tal cual. `Process` ya crea al hijo como jefe de su propio grupo de procesos
///   (pgid = pid, comprobado en `run()`); terminar manda la señal al grupo (`kill(-pid, …)`).
/// - Windows (paso 8): `process` solo guarda la configuración; el hijo se crea con `CreateProcessW` y
///   `CREATE_NO_WINDOW` (`CChildProcess`), porque Foundation no pasa ese flag y la app, de subsistema GUI, abría
///   una consola por cada hijo de consola. El hijo nace suspendido, entra en un Job Object con
///   `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` y solo entonces arranca: sus hijos (ffmpeg, deno) heredan el job y la
///   consola invisible. Terminar es `TerminateJobObject` (no hay SIGTERM; la parada ordenada va aparte, por
///   `StopEvent`). Este objeto se mantiene vivo hasta que sale el hijo; si se libera con el job abierto, el
///   sistema mata lo que quede del árbol.
public final class ChildProcess: @unchecked Sendable {
    /// Código de salida que deja `terminate` en Windows: 128 + SIGTERM, el mismo número que da hoy en el Mac
    /// un hijo muerto por SIGTERM una vez sumado 128 al `terminationStatus` (SourceKit, `ProcessRunning`).
    public static let terminatedExitCode: UInt32 = 143
    /// Ídem para `kill`: 128 + SIGKILL.
    public static let killedExitCode: UInt32 = 137

    /// Configuración del hijo. En Windows no se lanza: su `terminationHandler`, `terminationStatus` e
    /// `isRunning` no sirven; se usan los de `ChildProcess`.
    public let process = Process()
    private let lock = NSLock()
    private var pid: Int32 = 0
    private var handler: (@Sendable (ChildProcess) -> Void)?
    /// Mac: el hijo encabeza su grupo y se puede señalar el grupo entero.
    private var ownsGroup = false
    #if os(Windows)
    private var job: HANDLE?
    private var inJob = false
    private var processHandle: HANDLE?
    private var launched = false
    private var exitCode: DWORD?
    private let exitGroup = DispatchGroup()
    #endif

    public init() {}

    public convenience init(executableURL: URL, arguments: [String] = []) {
        self.init()
        process.executableURL = executableURL
        process.arguments = arguments
    }

    deinit {
        #if os(Windows)
        if let processHandle { CloseHandle(processHandle) }
        if let job { CloseHandle(job) }   // KILL_ON_JOB_CLOSE: si aún corre algo del árbol, muere
        #endif
    }

    /// Se llama una vez, desde otro hilo, cuando sale el hijo (lo que era `process.terminationHandler`).
    /// Mantiene vivo este objeto hasta entonces.
    public var terminationHandler: (@Sendable (ChildProcess) -> Void)? {
        get { lock.withLock { handler } }
        set {
            lock.withLock { handler = newValue }
            #if !os(Windows)
            guard let newValue else { process.terminationHandler = nil; return }
            process.terminationHandler = { [self] p in
                p.terminationHandler = nil   // rompe el ciclo self → process → cierre → self
                newValue(self)
            }
            #endif
        }
    }

    /// Lanza el proceso (lo que lanzaría `process.run()`).
    public func run() throws {
        #if os(Windows)
        try runHidden()
        #else
        try process.run()
        let pid = process.processIdentifier
        #if canImport(Darwin)
        let owns = getpgid(pid) == pid
        lock.withLock { self.pid = pid; ownsGroup = owns }
        #else
        lock.withLock { self.pid = pid }
        #endif
        #endif
    }

    public var processIdentifier: Int32 { lock.withLock { pid } }

    public var isRunning: Bool {
        #if os(Windows)
        lock.withLock { launched && exitCode == nil }
        #else
        process.isRunning
        #endif
    }

    public var terminationStatus: Int32 {
        #if os(Windows)
        lock.withLock { Int32(bitPattern: exitCode ?? 0) }
        #else
        process.terminationStatus
        #endif
    }

    /// Windows: siempre `.exit` (no hay señales; `terminate` deja `terminatedExitCode`).
    public var terminationReason: Process.TerminationReason {
        #if os(Windows)
        .exit
        #else
        process.terminationReason
        #endif
    }

    public func waitUntilExit() {
        #if os(Windows)
        exitGroup.wait()
        #else
        process.waitUntilExit()
        #endif
    }

    /// Termina el árbol. Mac: SIGTERM al grupo y, si pasado `grace` queda alguien, SIGKILL al grupo.
    /// Windows: `TerminateJobObject` en el acto (código `terminatedExitCode`); `grace` no se usa.
    public func terminate(grace: TimeInterval) {
        #if canImport(Darwin)
        let (pid, group) = lock.withLock { (self.pid, ownsGroup) }
        guard pid > 0 else { return }
        let target = group ? -pid : pid
        Darwin.kill(target, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + grace) {
            if Darwin.kill(target, 0) == 0 { Darwin.kill(target, SIGKILL) }
        }
        #else
        hardStop(code: Self.terminatedExitCode)
        #endif
    }

    /// Mata el árbol en el acto (SIGKILL al grupo; `TerminateJobObject` con `killedExitCode`).
    public func kill() {
        #if canImport(Darwin)
        let (pid, group) = lock.withLock { (self.pid, ownsGroup) }
        guard pid > 0 else { return }
        Darwin.kill(group ? -pid : pid, SIGKILL)
        #else
        hardStop(code: Self.killedExitCode)
        #endif
    }

    #if !canImport(Darwin)
    private func hardStop(code: UInt32) {
        #if os(Windows)
        let (job, inJob, handle, running) = lock.withLock {
            (self.job, self.inJob, self.processHandle, self.launched && self.exitCode == nil)
        }
        if inJob, let job, TerminateJobObject(job, code) { return }
        if running, let handle { _ = TerminateProcess(handle, code) }
        #else
        if process.isRunning { process.terminate() }
        #endif
    }
    #endif

    /// Procesos vivos del árbol (tests). Mac: miembros del grupo (≥ 1 si queda alguno; el número exacto no se
    /// puede preguntar sin recorrer la tabla, así que 1 o 0). Windows: `ActiveProcesses` del job.
    var activeProcessCount: Int {
        #if canImport(Darwin)
        let (pid, group) = lock.withLock { (self.pid, ownsGroup) }
        guard pid > 0 else { return 0 }
        return Darwin.kill(group ? -pid : pid, 0) == 0 ? 1 : 0
        #elseif os(Windows)
        let job = lock.withLock { self.job }
        guard let job else { return 0 }
        var info = JOBOBJECT_BASIC_ACCOUNTING_INFORMATION()
        let ok = QueryInformationJobObject(job, JobObjectBasicAccountingInformation, &info,
                                           DWORD(MemoryLayout<JOBOBJECT_BASIC_ACCOUNTING_INFORMATION>.size), nil)
        return ok ? Int(info.ActiveProcesses) : 0
        #else
        return 0
        #endif
    }

    #if os(Windows)
    /// `CreateProcessW` sin ventana (ver el comentario de la clase) con lo configurado en `process`.
    private func runHidden() throws {
        guard let exe = process.executableURL else { throw CocoaError(.fileNoSuchFile) }
        let exePath = WindowsCommandLine.nativePath(exe.path)
        let commandLine = WindowsCommandLine.build(executable: exePath, arguments: process.arguments ?? [])
        let directory = process.currentDirectoryURL.map { WindowsCommandLine.nativePath($0.path) }
        let environment = process.environment.map(WindowsCommandLine.environmentBlock)
        let stdIn = Self.childHandle(process.standardInput, reading: true, parentStd: 0)
        let stdOut = Self.childHandle(process.standardOutput, reading: false, parentStd: 1)
        let stdErr = Self.childHandle(process.standardError, reading: false, parentStd: 2)
        let job = Self.makeKillOnCloseJob()

        var info = tf_child_info()
        let error: UInt32 = commandLine.withCString(encodedAs: UTF16.self) { cmd in
            Self.withWide(directory) { dir in
                Self.withBlock(environment) { env in
                    tf_child_spawn(cmd, env, dir, stdIn, stdOut, stdErr, job, &info)
                }
            }
        }
        guard error == 0, let handle = info.process else {
            if let job { CloseHandle(job) }
            throw Self.launchError(code: error, executable: exePath)
        }
        // Como `Process.run`: el padre suelta su copia del extremo del hijo; si no, el lector no ve nunca EOF.
        Self.closeChildEnds(of: process)
        exitGroup.enter()
        lock.withLock {
            pid = Int32(bitPattern: info.pid)
            self.job = job
            inJob = info.in_job != 0
            processHandle = handle
            launched = true
        }
        Thread.detachNewThread { self.waitForExit() }   // retiene `self` hasta que sale el hijo
    }

    /// Hilo propio: espera al proceso, guarda el código, avisa y suelta `waitUntilExit`.
    private func waitForExit() {
        guard let handle = lock.withLock({ processHandle }) else { return }
        _ = WaitForSingleObject(handle, INFINITE)
        var code: DWORD = 0
        if !GetExitCodeProcess(handle, &code) { code = DWORD(Self.killedExitCode) }
        let onExit: (@Sendable (ChildProcess) -> Void)? = lock.withLock {
            exitCode = code
            let h = self.handler
            self.handler = nil
            return h
        }
        exitGroup.leave()
        onExit?(self)
    }

    /// Handle que verá el hijo: el extremo que le toca de una `Pipe`, el de un `FileHandle`, nil (`NUL`) para
    /// `FileHandle.nullDevice` y el estándar del padre si no se configuró nada (lo que hace `Process`).
    private static func childHandle(_ value: Any?, reading: Bool, parentStd: Int32) -> HANDLE? {
        switch value {
        case let pipe as Pipe:
            return reading ? pipe.fileHandleForReading._handle : pipe.fileHandleForWriting._handle
        case let file as FileHandle:
            return file === FileHandle.nullDevice ? nil : file._handle
        default:
            return tf_child_parent_std(parentStd)
        }
    }

    private static func closeChildEnds(of process: Process) {
        let outPipe = process.standardOutput as? Pipe
        if let p = process.standardInput as? Pipe { try? p.fileHandleForReading.close() }
        if let p = outPipe { try? p.fileHandleForWriting.close() }
        if let p = process.standardError as? Pipe, p !== outPipe { try? p.fileHandleForWriting.close() }
    }

    private static func withWide<R>(_ text: String?, _ body: (UnsafePointer<UInt16>?) -> R) -> R {
        guard let text else { return body(nil) }
        return text.withCString(encodedAs: UTF16.self) { body($0) }
    }

    private static func withBlock<R>(_ block: [UInt16]?, _ body: (UnsafePointer<UInt16>?) -> R) -> R {
        guard let block else { return body(nil) }
        return block.withUnsafeBufferPointer { body($0.baseAddress) }
    }

    /// ERROR_FILE_NOT_FOUND (2) y ERROR_PATH_NOT_FOUND (3) como `Process.run` con un ejecutable que no existe.
    private static func launchError(code: UInt32, executable: String) -> Error {
        if code == 2 || code == 3 { return CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: executable]) }
        return NSError(domain: "ChildProcess.CreateProcessW", code: Int(code),
                       userInfo: [NSLocalizedDescriptionKey: "No se pudo lanzar \(executable) (error de Windows \(code))"])
    }

    private static func makeKillOnCloseJob() -> HANDLE? {
        guard let job = CreateJobObjectW(nil, nil) else { return nil }
        var limits = JOBOBJECT_EXTENDED_LIMIT_INFORMATION()
        limits.BasicLimitInformation.LimitFlags = DWORD(JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE)
        let ok = SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits,
                                         DWORD(MemoryLayout<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>.size))
        if !ok { CloseHandle(job); return nil }
        return job
    }
    #endif
}
