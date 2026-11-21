import Foundation
#if canImport(Darwin)
import Darwin
#elseif os(Windows)
import WinSDK
#endif

/// Proceso hijo que, al terminarlo, se lleva también a sus descendientes (plan, «Fase 7c», mini-spec:
/// «`Process` con Job Object para que mueran los nietos»): yt-dlp lanza ffmpeg, y matar solo al padre los
/// dejaba huérfanos.
///
/// Se configura `process` como un `Process` normal (ejecutable, argumentos, tuberías, `terminationHandler`)
/// y se lanza con `run()`, no con `process.run()`.
/// - Mac: `Process` ya crea al hijo como jefe de su propio grupo de procesos (pgid = pid, comprobado en
///   `run()`); terminar manda la señal al grupo (`kill(-pid, …)`).
/// - Windows: al lanzar, el hijo entra en un Job Object con `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`; sus hijos
///   heredan el job. Terminar es `TerminateJobObject` (no hay SIGTERM: no hay salida ordenada). Si este
///   objeto se libera con el job abierto, el sistema mata el árbol: hay que conservarlo mientras corra.
///   Los nietos lanzados antes de entrar en el job (el instante entre `CreateProcess` y la asignación)
///   escaparían; los helpers no lanzan nada tan pronto.
public final class ChildProcess: @unchecked Sendable {
    /// Código de salida que deja `terminate` en Windows: 128 + SIGTERM, el mismo número que da hoy en el Mac
    /// un hijo muerto por SIGTERM una vez sumado 128 al `terminationStatus` (SourceKit, `ProcessRunning`).
    public static let terminatedExitCode: UInt32 = 143
    /// Ídem para `kill`: 128 + SIGKILL.
    public static let killedExitCode: UInt32 = 137

    public let process = Process()
    private let lock = NSLock()
    private var pid: Int32 = 0
    /// Mac: el hijo encabeza su grupo y se puede señalar el grupo entero.
    private var ownsGroup = false
    #if os(Windows)
    private var job: HANDLE?
    private var inJob = false
    #endif

    public init() {}

    public convenience init(executableURL: URL, arguments: [String] = []) {
        self.init()
        process.executableURL = executableURL
        process.arguments = arguments
    }

    deinit {
        #if os(Windows)
        if let job { CloseHandle(job) }   // KILL_ON_JOB_CLOSE: si aún corre algo del árbol, muere
        #endif
    }

    /// Lanza el proceso (lo que lanzaría `process.run()`).
    public func run() throws {
        #if os(Windows)
        let job = Self.makeKillOnCloseJob()
        #endif
        try process.run()
        let pid = process.processIdentifier
        #if canImport(Darwin)
        let owns = getpgid(pid) == pid
        lock.withLock { self.pid = pid; ownsGroup = owns }
        #elseif os(Windows)
        var assigned = false
        if let job, let h = OpenProcess(DWORD(PROCESS_SET_QUOTA | PROCESS_TERMINATE), false, DWORD(pid)) {
            assigned = AssignProcessToJobObject(job, h)
            CloseHandle(h)
        }
        lock.withLock { self.pid = pid; self.job = job; inJob = assigned }
        #else
        lock.withLock { self.pid = pid }
        #endif
    }

    public var processIdentifier: Int32 { lock.withLock { pid } }
    public var isRunning: Bool { process.isRunning }
    public var terminationStatus: Int32 { process.terminationStatus }
    public var terminationReason: Process.TerminationReason { process.terminationReason }
    public func waitUntilExit() { process.waitUntilExit() }

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
        let (job, inJob) = lock.withLock { (self.job, self.inJob) }
        if inJob, let job, TerminateJobObject(job, code) { return }
        #endif
        if process.isRunning { process.terminate() }
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
