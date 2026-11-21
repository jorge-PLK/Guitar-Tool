import Foundation

/// Solo para tests de MemoryGuard/SeparationRunner: habla el mismo JSON que tf-separate, reserva y
/// toca `<MB>` megabytes (con datos aleatorios para que no se compriman) y espera hasta 60 s.
/// Uso: tf-memhog <MB>
@main
struct MemHog {
    static func main() {
        let mb = CommandLine.arguments.dropFirst().first.flatMap { Int($0) } ?? 400
        FileHandle.standardOutput.write(Data(#"{"stage":"loading"}"#.utf8 + [0x0A]))
        // Semilla de `SystemRandomNumberGenerator` y SplitMix64 para el relleno: pedir cada palabra al sistema
        // (BCryptGenRandom en Windows) costaría una llamada por cada 8 bytes; SplitMix64 tampoco se comprime.
        var sys = SystemRandomNumberGenerator()
        var state = sys.next()
        var blocks: [UnsafeMutableRawPointer] = []
        for _ in 0..<mb {
            let p = UnsafeMutableRawPointer.allocate(byteCount: 1 << 20, alignment: 16)
            let words = p.bindMemory(to: UInt64.self, capacity: (1 << 20) / 8)
            for i in 0..<(1 << 20) / 8 {
                state &+= 0x9E37_79B9_7F4A_7C15
                var z = state
                z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
                z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
                words[i] = z ^ (z >> 31)
            }
            blocks.append(p)
        }
        FileHandle.standardOutput.write(Data(#"{"stage":"separating","chunk":0,"of":1}"#.utf8 + [0x0A]))
        Thread.sleep(forTimeInterval: 60)
        withExtendedLifetime(blocks) {}
    }
}
