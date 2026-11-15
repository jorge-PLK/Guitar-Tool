// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AnalysisKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AnalysisKit", targets: ["AnalysisKit"])
    ],
    targets: [
        .target(name: "AnalysisKit"),
        .testTarget(name: "AnalysisKitTests", dependencies: ["AnalysisKit"])
    ]
)
