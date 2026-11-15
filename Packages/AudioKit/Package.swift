// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AudioKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AudioKit", targets: ["AudioKit"]),
        // Solo desarrollo (no se embebe): las medidas con el dispositivo desde la terminal.
        .executable(name: "tf-audio", targets: ["tf-audio"])
    ],
    targets: [
        .target(name: "AudioKit"),
        .executableTarget(name: "tf-audio", dependencies: ["AudioKit"]),
        .testTarget(name: "AudioKitTests", dependencies: ["AudioKit", "tf-audio"], resources: [.copy("Fixtures")])
    ]
)
