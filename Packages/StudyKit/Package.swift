// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StudyKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "StudyKit", targets: ["StudyKit"])
    ],
    targets: [
        .target(name: "StudyKit"),
        .testTarget(name: "StudyKitTests", dependencies: ["StudyKit"])
    ]
)
