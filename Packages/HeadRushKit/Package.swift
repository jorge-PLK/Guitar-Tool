// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HeadRushKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "HeadRushKit", targets: ["HeadRushKit"])
    ],
    targets: [
        .target(name: "HeadRushKit"),
        .testTarget(name: "HeadRushKitTests", dependencies: ["HeadRushKit"])
    ]
)
