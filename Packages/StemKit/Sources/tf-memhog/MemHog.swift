import Foundation

/// Solo para tests de MemoryGuard/SeparationRunner: habla el mismo JSON que tf-separate, reserva y
/// toca `<MB>` megabytes (con datos aleatorios para que no se compriman) y espera hasta 60 s.
/// Uso: tf-memhog <MB>
@main
struct MemHog {
    static func main() {
        let mb = CommandLine.arguments.dropFirst().first.flatMap { Int($0) } ?? 400
        FileHandle.standardOutput.write(Data(#"{"stage":"loading"}"#.utf8 + [0x0A]))
        var blocks: [UnsafeMutableRawPointer] = []
        for _ in 0..<mb {
            let p = UnsafeMutableRawPointer.allocate(byteCount: 1 << 20, alignment: 16)
            arc4random_buf(p, 1 << 20)
            blocks.append(p)
        }
        FileHandle.standardOutput.write(Data(#"{"stage":"separating","chunk":0,"of":1}"#.utf8 + [0x0A]))
        Thread.sleep(forTimeInterval: 60)
        withExtendedLifetime(blocks) {}
    }
}
