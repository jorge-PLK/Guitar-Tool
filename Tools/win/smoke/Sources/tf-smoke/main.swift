// Imprime arquitectura, sistema, locale y un NumberFormatter(.decimal).
// `--wait <s>` deja el proceso abierto s segundos (para la captura de `build.sh --gui`).
import Foundation

#if arch(arm64)
let arch = "arm64"
#elseif arch(x86_64)
let arch = "x86_64"
#else
let arch = "desconocida"
#endif

let args = CommandLine.arguments
let formatter = NumberFormatter()
formatter.numberStyle = .decimal

print("tf-smoke arch=\(arch)")
print("os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
print("locale=\(Locale.current.identifier)")
print("decimal(1234.5)=\(formatter.string(from: NSNumber(value: 1234.5)) ?? "nil")")
fflush(stdout)

if let i = args.firstIndex(of: "--wait"), i + 1 < args.count, let s = Double(args[i + 1]) {
    print("esperando \(s) s")
    fflush(stdout)
    Thread.sleep(forTimeInterval: s)
}
print("tf-smoke fin")
