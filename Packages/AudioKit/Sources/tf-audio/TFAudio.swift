import Foundation

/// Ejecutable de desarrollo (mini-spec Fase 3, «Código»): no se embebe en la app.
@main
struct TFAudio {
    @MainActor
    static func main() async {
        // En Windows solo `--simulated` hasta la parte 7.10 (WASAPI).
        let code = await CLI.run(Array(CommandLine.arguments.dropFirst()), env: .standard())
        exit(code)
    }
}
