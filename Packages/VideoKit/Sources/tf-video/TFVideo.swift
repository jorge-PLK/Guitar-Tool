import Foundation

@main
struct TFVideo {
    @MainActor
    static func main() async {
        let code = await CLI.run(Array(CommandLine.arguments.dropFirst()), env: .standard())
        exit(code)
    }
}
