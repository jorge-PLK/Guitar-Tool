import Foundation

// Mac: AVFoundation, CoreAudio y Vision. Windows (plan, «Corte del paso 7», parte 7.11b): Media Foundation, WASAPI y
// MoveNet, con los mismos comandos.
@main
struct TFVideo {
    @MainActor
    static func main() async {
        let code = await CLI.run(Array(CommandLine.arguments.dropFirst()), env: .standard())
        exit(code)
    }
}
