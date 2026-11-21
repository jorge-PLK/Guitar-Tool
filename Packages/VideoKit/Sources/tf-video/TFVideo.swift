import Foundation

@main
struct TFVideo {
    @MainActor
    static func main() async {
        #if canImport(AVFoundation)
        let code = await CLI.run(Array(CommandLine.arguments.dropFirst()), env: .standard())
        exit(code)
        #else
        FileHandle.standardError.write(Data("tf-video: no disponible en Windows (paso 7: media-foundation, wasapi)\n".utf8))
        exit(1)
        #endif
    }
}
