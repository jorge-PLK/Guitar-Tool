// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MatchKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MatchKit", targets: ["MatchKit"])
    ],
    targets: [
        .target(name: "MatchKit"),
        .testTarget(name: "MatchKitTests", dependencies: ["MatchKit"])
    ]
)
