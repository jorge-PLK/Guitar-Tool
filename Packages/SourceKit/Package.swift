// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SourceKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SourceKit", targets: ["SourceKit"]),
        // Solo desarrollo (no se embebe): hace el recorrido real de «Fuentes externas» desde la terminal.
        .executable(name: "tf-fetch", targets: ["tf-fetch"])
    ],
    targets: [
        .target(name: "SourceKit"),
        .executableTarget(name: "tf-fetch", dependencies: ["SourceKit"]),
        .testTarget(
            name: "SourceKitTests",
            dependencies: ["SourceKit"],
            resources: [.copy("Fixtures")])
    ]
)
