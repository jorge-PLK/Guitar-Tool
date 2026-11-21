import Foundation
@testable import NativePlatform
import XCTest

/// Reglas de `CommandLineToArgvW` y del CRT de MSVC (Microsoft, «Parsing C++ command-line arguments»): referencia
/// independiente de `WindowsCommandLine.quote` para comprobar la ida y vuelta.
/// - argv[0]: entre comillas hasta la siguiente comilla, o hasta espacio/tabulador; sin escapes.
/// - Resto: espacio y tabulador separan fuera de comillas; n barras + comilla dan n/2 barras y, si n es impar, una
///   comilla literal (si es par, la comilla abre o cierra); barras sin comilla detrás, tal cual; `""` dentro de
///   comillas es una comilla literal (CRT 2008+).
func parseWindowsCommandLine(_ line: String) -> [String] {
    let s = Array(line.unicodeScalars)
    var i = 0
    var args: [String] = []
    var first = String.UnicodeScalarView()
    if i < s.count, s[i] == "\"" {
        i += 1
        while i < s.count, s[i] != "\"" { first.append(s[i]); i += 1 }
        if i < s.count { i += 1 }
    } else {
        while i < s.count, s[i] != " ", s[i] != "\t" { first.append(s[i]); i += 1 }
    }
    args.append(String(first))
    while true {
        while i < s.count, s[i] == " " || s[i] == "\t" { i += 1 }
        if i >= s.count { break }
        var arg = String.UnicodeScalarView()
        var inQuotes = false
        while i < s.count {
            let c = s[i]
            if c == "\\" {
                var n = 0
                while i < s.count, s[i] == "\\" { n += 1; i += 1 }
                if i < s.count, s[i] == "\"" {
                    for _ in 0..<(n / 2) { arg.append("\\") }
                    if n % 2 == 1 { arg.append("\""); i += 1 }
                } else {
                    for _ in 0..<n { arg.append("\\") }
                }
                continue
            }
            if c == "\"" {
                if inQuotes, i + 1 < s.count, s[i + 1] == "\"" { arg.append("\""); i += 2; continue }
                inQuotes.toggle()
                i += 1
                continue
            }
            if !inQuotes, c == " " || c == "\t" { break }
            arg.append(c)
            i += 1
        }
        args.append(String(arg))
    }
    return args
}

final class WindowsCommandLineTests: XCTestCase {
    let exe = "C:\\Program Files\\ToneForge\\Helpers\\yt-dlp.exe"

    /// Tabla de casos con la salida exacta esperada (la inversa de la tabla de Microsoft).
    func testQuoteVectors() {
        let cases: [(String, String)] = [
            ("abc", "abc"),
            ("", "\"\""),
            ("a b", "\"a b\""),
            ("a\tb", "\"a\tb\""),
            ("a\"b", "\"a\\\"b\""),               // a"b      → "a\"b"
            ("a\\\\b", "a\\\\b"),                  // a\\b     → tal cual (sin espacio ni comilla)
            ("a\\\"b", "\"a\\\\\\\"b\""),          // a\"b     → "a\\\"b"
            ("ab\\", "ab\\"),                       // ab\      → tal cual
            ("C:\\Program Files\\", "\"C:\\Program Files\\\\\""),   // barra final doblada antes del cierre
            ("bestaudio[ext=m4a]/bestaudio", "bestaudio[ext=m4a]/bestaudio"),
            ("%(title)s - %(id)s.%(ext)s", "\"%(title)s - %(id)s.%(ext)s\""),
            ("\"\u{301}", "\"\\\"\u{301}\""),      // comilla + acento combinante: se escapa la comilla
        ]
        for (raw, quoted) in cases {
            XCTAssertEqual(Array(WindowsCommandLine.quote(raw).unicodeScalars), Array(quoted.unicodeScalars),
                           "quote(\(raw.debugDescription))")
        }
    }

    /// Argumentos reales de los helpers (rutas con espacios y acentos, plantillas de yt-dlp, JSON).
    func testRealArgumentsRoundTrip() {
        let args = ["--newline", "-f", "bestaudio[ext=m4a]/bestaudio", "-o",
                    "C:\\Users\\Jorge Fernández\\AppData\\Local\\ToneForge\\Downloads\\%(id)s.%(ext)s",
                    "--print", "after_move:%(filepath)s", "https://www.youtube.com/watch?v=abc&t=10",
                    "{\"stems\":[\"guitar\",\"other\"],\"path\":\"C:\\\\tmp\\\\\"}", "", "C:\\dir with space\\"]
        let line = WindowsCommandLine.build(executable: exe, arguments: args)
        XCTAssertEqual(parseWindowsCommandLine(line), [exe] + args)
    }

    /// Ida y vuelta con 2000 listas aleatorias (generador fijo) sobre el alfabeto que rompe las citas ingenuas:
    /// espacios, tabuladores, saltos, barras, comillas y no ASCII. Deben volver todas idénticas.
    func testRandomArgumentsRoundTrip() {
        let alphabet: [String] = ["a", " ", "\t", "\\", "\"", "ñ", "\u{301}", "\n", "="]
        var state: UInt64 = 0x2545_F491_4F6C_DD1D
        func next(_ n: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(n))
        }
        var failures = 0
        let total = 2000
        for _ in 0..<total {
            let args = (0..<(1 + next(4))).map { _ in (0..<next(9)).map { _ in alphabet[next(alphabet.count)] }.joined() }
            let line = WindowsCommandLine.build(executable: exe, arguments: args)
            if parseWindowsCommandLine(line) != [exe] + args {
                failures += 1
                if failures <= 3 { XCTFail("no vuelve: \(args.debugDescription) → \(line.debugDescription)") }
            }
        }
        print("ida y vuelta: \(total - failures)/\(total)")
        XCTAssertEqual(failures, 0)
    }

    func testEnvironmentBlock() {
        XCTAssertEqual(WindowsCommandLine.environmentBlock([:]), [0, 0])
        let block = WindowsCommandLine.environmentBlock(["b": "2", "A": "1", "TF_STOP_EVENT": "Local\\ToneForge-stop-1",
                                                         "bad\0key": "x", "": "vacía"])
        XCTAssertEqual(block, Array("A=1\0b=2\0TF_STOP_EVENT=Local\\ToneForge-stop-1\0\0".utf16))
        XCTAssertEqual(WindowsCommandLine.environmentBlock(["ruta": "ñ"]), Array("ruta=ñ\0\0".utf16))
    }

    func testNativePath() {
        XCTAssertEqual(WindowsCommandLine.nativePath("/C:/Program Files/tf-separate.exe"), "C:\\Program Files\\tf-separate.exe")
        XCTAssertEqual(WindowsCommandLine.nativePath("C:/Users/a b/x.exe"), "C:\\Users\\a b\\x.exe")
        XCTAssertEqual(WindowsCommandLine.nativePath("C:\\Windows\\System32\\tar.exe"), "C:\\Windows\\System32\\tar.exe")
        XCTAssertEqual(WindowsCommandLine.nativePath("//srv/share/a.exe"), "\\\\srv\\share\\a.exe")
    }
}

/// Lanzamiento real con la API de `ChildProcess` (en Windows pasa por `CreateProcessW` sin ventana).
final class ChildProcessLaunchTests: XCTestCase {
    #if os(Windows)
    static let shell = URL(fileURLWithPath: "C:\\Windows\\System32\\cmd.exe")
    static func script(_ text: String) -> [String] { ["/c", text] }
    static let outputAndExit = "echo hola& echo error 1>&2& exit /b 7"
    static let cwdAndEnv = "cd& echo %TF_PROBE%"
    static let shortRun = "ping -n 1 127.0.0.1 >nul"
    #else
    static let shell = URL(fileURLWithPath: "/bin/sh")
    static func script(_ text: String) -> [String] { ["-c", text] }
    static let outputAndExit = "echo hola; echo error >&2; exit 7"
    static let cwdAndEnv = "pwd; echo $TF_PROBE"
    static let shortRun = "sleep 0.2"
    #endif

    /// Salida y error por tuberías hasta EOF, código 7 y un único aviso por `terminationHandler`.
    func testPipesExitCodeAndHandler() throws {
        let child = ChildProcess(executableURL: Self.shell, arguments: Self.script(Self.outputAndExit))
        let out = Pipe(), err = Pipe()
        child.process.standardInput = FileHandle.nullDevice
        child.process.standardOutput = out
        child.process.standardError = err
        let done = expectation(description: "sale")
        done.expectedFulfillmentCount = 1
        done.assertForOverFulfill = true
        child.terminationHandler = { c in
            XCTAssertFalse(c.isRunning)
            XCTAssertEqual(c.terminationStatus, 7)
            XCTAssertEqual(c.terminationReason, .exit)
            done.fulfill()
        }
        try child.run()
        XCTAssertGreaterThan(child.processIdentifier, 0)
        // EOF solo llega si el padre soltó su copia del extremo de escritura.
        let stdout = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        wait(for: [done], timeout: 10)
        child.waitUntilExit()
        XCTAssertEqual(stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hola")
        XCTAssertEqual(stderr.trimmingCharacters(in: .whitespacesAndNewlines), "error")
        XCTAssertEqual(child.terminationStatus, 7)
    }

    /// Entorno y directorio de trabajo (con espacio en la ruta) llegan al hijo.
    func testEnvironmentAndDirectory() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tf cwd \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let child = ChildProcess(executableURL: Self.shell, arguments: Self.script(Self.cwdAndEnv))
        var env = ProcessInfo.processInfo.environment
        env["TF_PROBE"] = "tf-ok"
        child.process.environment = env
        child.process.currentDirectoryURL = dir
        let out = Pipe()
        child.process.standardOutput = out
        try child.run()
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        child.waitUntilExit()
        XCTAssertEqual(child.terminationStatus, 0)
        XCTAssertTrue(text.contains(dir.lastPathComponent), text)
        XCTAssertTrue(text.contains("tf-ok"), text)
    }

    /// El aviso llega aunque nadie guarde el `ChildProcess` tras lanzarlo (ModelStore lo deja en una variable local).
    func testHandlerFiresWithoutKeepingTheObject() throws {
        let done = expectation(description: "sale")
        try {
            let child = ChildProcess(executableURL: Self.shell, arguments: Self.script(Self.shortRun))
            child.process.standardOutput = FileHandle.nullDevice
            child.terminationHandler = { c in
                XCTAssertEqual(c.terminationStatus, 0)
                done.fulfill()
            }
            try child.run()
        }()
        wait(for: [done], timeout: 10)
    }

    /// Un ejecutable que no existe hace fallar `run()` (no el aviso de salida).
    func testMissingExecutableThrows() {
        let child = ChildProcess(executableURL: URL(fileURLWithPath: NSTemporaryDirectory() + "no-existe-\(UUID().uuidString)"))
        XCTAssertThrowsError(try child.run())
        XCTAssertFalse(child.isRunning)
    }
}
