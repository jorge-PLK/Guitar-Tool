// swift-tools-version: 6.0
import PackageDescription

// La biblioteca no depende de AudioKit: recibe el reloj del audio con tipos propios (`HostTimeMap`) y la app
// hace de puente. Solo `tf-video` y los tests de la puerta (con el audio simulado de la Fase 3) lo usan.
let package = Package(
    name: "VideoKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "VideoKit", targets: ["VideoKit"]),
        // Solo desarrollo (no se embebe): cámaras, grabación y sincronía desde la terminal.
        .executable(name: "tf-video", targets: ["tf-video"])
    ],
    dependencies: [
        .package(path: "../AudioKit")
    ],
    targets: [
        .target(name: "VideoKit"),
        .executableTarget(name: "tf-video", dependencies: ["VideoKit", .product(name: "AudioKit", package: "AudioKit")]),
        .testTarget(name: "VideoKitTests", dependencies: ["VideoKit", "tf-video", .product(name: "AudioKit", package: "AudioKit")])
    ]
)
