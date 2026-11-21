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
    dependencies: [
        // Capa de plataforma (plan, «Fase 7c», paso 6): DSP, ficheros de audio y procesos hijos.
        .package(path: "../NativeKit")
    ],
    targets: [
        .target(name: "StemKit", dependencies: [
            .product(name: "NativeDSP", package: "NativeKit"),
            .product(name: "NativeAudioFile", package: "NativeKit"),
            .product(name: "NativePlatform", package: "NativeKit"),
            // Windows (plan, «Corte del paso 7», parte 7.8): ONNX Runtime y el remuestreador r8brain.
            .product(name: "NativeONNX", package: "NativeKit", condition: .when(platforms: [.windows])),
            .product(name: "NativeResample", package: "NativeKit", condition: .when(platforms: [.windows]))
        ]),
        .executableTarget(name: "tf-separate", dependencies: ["StemKit"]),
        // Solo para tests: reserva y toca memoria para probar MemoryGuard/SeparationRunner. No es producto.
        .executableTarget(name: "tf-memhog"),
        // Fixtures/LeadRhythm: paridad del modelo de solista (entrada + salida de PyTorch, ver su reference.json).
        .testTarget(name: "StemKitTests", dependencies: ["StemKit", "tf-separate", "tf-memhog"],
                    resources: [.copy("Fixtures")])
    ]
)
