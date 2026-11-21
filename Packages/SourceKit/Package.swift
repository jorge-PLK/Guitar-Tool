// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SourceKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SourceKit", targets: ["SourceKit"]),
        // Solo desarrollo (no se embebe): hace el recorrido real de «Fuentes externas» desde la terminal.
        .executable(name: "tf-fetch", targets: ["tf-fetch"])
    ],
    dependencies: [
        // Capa de plataforma (plan, «Fase 7c», paso 6): ChildProcess, SupportFolder y miniz.
        .package(path: "../NativeKit"),
        // CryptoKit no existe en Windows: swift-crypto solo allí.
        .package(url: "https://github.com/apple/swift-crypto", from: "3.0.0")
    ],
    targets: [
        .target(name: "SourceKit", dependencies: [
            .product(name: "NativePlatform", package: "NativeKit"),
            // Deflate crudo de Songsterr: en el Mac sigue con Compression.
            .product(name: "CMiniz", package: "NativeKit", condition: .when(platforms: [.windows])),
            .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.windows]))
        ]),
        .executableTarget(name: "tf-fetch", dependencies: ["SourceKit"]),
        .testTarget(
            name: "SourceKitTests",
            dependencies: [
                "SourceKit",
                .product(name: "NativePlatform", package: "NativeKit"),
                .product(name: "CMiniz", package: "NativeKit", condition: .when(platforms: [.windows])),
                .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.windows]))
            ],
            resources: [.copy("Fixtures")])
    ]
)
