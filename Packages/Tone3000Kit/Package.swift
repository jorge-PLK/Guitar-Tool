// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tone3000Kit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Tone3000Kit", targets: ["Tone3000Kit"])
    ],
    targets: [
        .target(name: "Tone3000Kit"),
        .testTarget(name: "Tone3000KitTests", dependencies: ["Tone3000Kit"])
    ]
)
