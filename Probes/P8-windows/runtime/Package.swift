// swift-tools-version: 6.0
// Prueba mínima del runtime de Swift en Windows (plan, Fase 7c, mini-spec del paso 4, prueba a):
// Mutex, Atomic, @Observable, DispatchSourceTimer, DispatchSource de señal, Process y QueryPerformanceCounter.
import PackageDescription

let package = Package(
    name: "tf-p8-runtime",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "tf-p8-runtime", path: "Sources/tf-p8-runtime",
                          linkerSettings: [.linkedLibrary("winmm", .when(platforms: [.windows]))]),
        // Aparte: si DispatchSource.makeSignalSource no compila en Windows, no tapa el resto.
        .executableTarget(name: "tf-p8-signal", path: "Sources/tf-p8-signal"),
    ]
)
