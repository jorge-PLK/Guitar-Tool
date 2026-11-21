// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StudyKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "StudyKit", targets: ["StudyKit"])
    ],
    dependencies: [
        .package(path: "../NativeKit")
    ],
    targets: [
        .target(name: "StudyKit", dependencies: [
            .product(name: "NativeDSP", package: "NativeKit"),
            .product(name: "NativeAudioFile", package: "NativeKit"),
            .product(name: "NativePlatform", package: "NativeKit"),
            // r8brain: el remuestreo de `MonoResampler` en Windows (plan, «Corte del paso 7», parte 7.1).
            .product(name: "NativeResample", package: "NativeKit"),
            // ONNX Runtime: Beat This! y BTC en Windows (parte 7.8).
            .product(name: "NativeONNX", package: "NativeKit", condition: .when(platforms: [.windows]))
        ]),
        .testTarget(name: "StudyKitTests", dependencies: ["StudyKit"],
                    resources: [.copy("Fixtures")])
    ]
)
