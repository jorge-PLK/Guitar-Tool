// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ModelKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ModelKit", targets: ["ModelKit"])
    ],
    dependencies: [
        .package(path: "../NativeKit"),
        // CryptoKit no existe en Windows (plan, «Fase 7c», paso 6): swift-crypto solo allí.
        .package(url: "https://github.com/apple/swift-crypto", from: "3.0.0")
    ],
    targets: [
        .target(name: "ModelKit", dependencies: [
            .product(name: "NativePlatform", package: "NativeKit"),
            .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.windows]))
        ]),
        .testTarget(name: "ModelKitTests", dependencies: [
            "ModelKit",
            .product(name: "NativePlatform", package: "NativeKit"),
            .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.windows]))
        ])
    ]
)
