// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StemKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "StemKit", targets: ["StemKit"]),
        // Helper que la app lanza en un proceso aparte por tema (P6 lo embebe en Contents/MacOS).
        .executable(name: "tf-separate", targets: ["tf-separate"])
    ],
    targets: [
        .target(name: "StemKit"),
        .executableTarget(name: "tf-separate", dependencies: ["StemKit"]),
        // Solo para tests: reserva y toca memoria para probar MemoryGuard/SeparationRunner. No es producto.
        .executableTarget(name: "tf-memhog"),
        // Fixtures/LeadRhythm: paridad del modelo de solista (entrada + salida de PyTorch, ver su reference.json).
        .testTarget(name: "StemKitTests", dependencies: ["StemKit", "tf-separate", "tf-memhog"],
                    resources: [.copy("Fixtures")])
    ]
)
