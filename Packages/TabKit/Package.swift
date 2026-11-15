// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TabKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TabKit", targets: ["TabKit"])
    ],
    targets: [
        .target(name: "TabKit"),
        .testTarget(name: "TabKitTests", dependencies: ["TabKit"])
    ]
)
