// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VideoKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "VideoKit", targets: ["VideoKit"])
    ],
    targets: [
        .target(name: "VideoKit"),
        .testTarget(name: "VideoKitTests", dependencies: ["VideoKit"])
    ]
)
