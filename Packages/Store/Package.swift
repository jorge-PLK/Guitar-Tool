// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Store",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Store", targets: ["Store"])
    ],
    targets: [
        .target(name: "Store"),
        .testTarget(name: "StoreTests", dependencies: ["Store"])
    ]
)
