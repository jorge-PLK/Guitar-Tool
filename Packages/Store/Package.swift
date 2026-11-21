// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Store",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Store", targets: ["Store"])
    ],
    dependencies: [
        // CryptoKit no existe en Windows (plan, «Fase 7c», paso 6): swift-crypto solo allí.
        .package(url: "https://github.com/apple/swift-crypto", from: "3.0.0")
    ],
    targets: [
        .target(name: "Store", dependencies: [
            .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.windows]))
        ]),
        .testTarget(name: "StoreTests", dependencies: ["Store"])
    ]
)
