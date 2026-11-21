// swift-tools-version: 6.0
// Probe de la parte 7.7 (Fase 7c, paso 7): el shim CWASAPI de NativeKit en dúplex por eventos, con las marcas por búfer
// que necesita DuplexClockSync. Renderiza silencio y descarta lo capturado. Solo hace algo en Windows.
import PackageDescription

let package = Package(
    name: "tf-p8-wasapi",
    platforms: [.macOS(.v15)],
    dependencies: [.package(path: "../../../Packages/NativeKit")],
    targets: [
        .executableTarget(
            name: "tf-p8-wasapi",
            dependencies: [
                .product(name: "CWASAPI", package: "NativeKit"),
                .product(name: "NativePlatform", package: "NativeKit"),
            ],
            path: "Sources/tf-p8-wasapi",
            swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
