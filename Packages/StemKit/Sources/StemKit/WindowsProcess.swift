#if os(Windows)
// Fichero aparte: `import WinSDK` trae un `UUID` que choca con el de Foundation.
import WinSDK

/// Consultas y parada de un proceso por pid en Windows (lo que en el Mac hacen `proc_pid_rusage` y `kill`).
enum WindowsProcess {
    /// `GetExitCodeProcess` de un proceso que sigue vivo (`STILL_ACTIVE`).
    private static let stillActive: DWORD = 259

    /// `max(PrivateUsage, WorkingSetSize)`: el análogo de `max(phys_footprint, resident_size)` del Mac.
    /// nil si el proceso no existe o ya ha salido.
    static func footprint(pid: Int32) -> UInt64? {
        let access = DWORD(PROCESS_QUERY_LIMITED_INFORMATION) | DWORD(PROCESS_VM_READ)
        guard let h = OpenProcess(access, false, DWORD(bitPattern: pid)) else { return nil }
        defer { CloseHandle(h) }
        var code: DWORD = 0
        guard GetExitCodeProcess(h, &code), code == stillActive else { return nil }
        let size = DWORD(MemoryLayout<PROCESS_MEMORY_COUNTERS_EX>.size)
        var counters = PROCESS_MEMORY_COUNTERS_EX()
        counters.cb = size
        let ok = withUnsafeMutablePointer(to: &counters) { p in
            p.withMemoryRebound(to: PROCESS_MEMORY_COUNTERS.self, capacity: 1) { K32GetProcessMemoryInfo(h, $0, size) }
        }
        guard ok else { return nil }
        return UInt64(max(counters.PrivateUsage, counters.WorkingSetSize))
    }

    /// `TerminateProcess` con `code`. `false` si no se pudo abrir o terminar.
    @discardableResult
    static func terminate(pid: Int32, code: UInt32) -> Bool {
        guard let h = OpenProcess(DWORD(PROCESS_TERMINATE), false, DWORD(bitPattern: pid)) else { return false }
        defer { CloseHandle(h) }
        return TerminateProcess(h, code)
    }

    /// `true` mientras el proceso exista y no haya salido.
    static func isAlive(pid: Int32) -> Bool {
        guard let h = OpenProcess(DWORD(PROCESS_QUERY_LIMITED_INFORMATION), false, DWORD(bitPattern: pid)) else {
            return false
        }
        defer { CloseHandle(h) }
        var code: DWORD = 0
        return GetExitCodeProcess(h, &code) && code == stillActive
    }
}
#endif
