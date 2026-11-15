// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AppleRender",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "applerender", path: "Sources/applerender")
    ]
)
