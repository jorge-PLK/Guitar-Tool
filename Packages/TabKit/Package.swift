// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TabKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TabKit", targets: ["TabKit"])
    ],
    dependencies: [
        // Capa de plataforma (plan, «Fase 7c», paso 6): DSP, lectura de audio y errores de pieza pendiente.
        .package(path: "../NativeKit")
    ],
    targets: [
        .target(name: "TabKit", dependencies: [
            .product(name: "NativeDSP", package: "NativeKit"),
            .product(name: "NativeAudioFile", package: "NativeKit"),
            .product(name: "NativePlatform", package: "NativeKit"),
            // Paso 7 (parte 7.4): sintetizador de Windows (también en el Mac, para compararlo con el sampler) y
            // remuestreador de `MonoAudio` solo en Windows (en el Mac sigue `AVAudioConverter`).
            .product(name: "CTinySoundFont", package: "NativeKit"),
            .product(name: "NativeResample", package: "NativeKit", condition: .when(platforms: [.windows])),
            // ONNX Runtime: Basic Pitch y ADTOF en Windows (parte 7.8).
            .product(name: "NativeONNX", package: "NativeKit", condition: .when(platforms: [.windows])),
        ]),
        .testTarget(name: "TabKitTests", dependencies: [
            "TabKit",
            .product(name: "NativeDSP", package: "NativeKit"),
            .product(name: "NativeAudioFile", package: "NativeKit"),
            .product(name: "NativePlatform", package: "NativeKit"),
            // Proveedor con que se abre ADTOF en Windows (OnnxDrumProviderTests).
            .product(name: "NativeONNX", package: "NativeKit", condition: .when(platforms: [.windows])),
        ], resources: [.copy("Fixtures")])
    ]
)
