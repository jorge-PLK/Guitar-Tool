// swift-tools-version: 6.0
import PackageDescription

// P9 prueba 2 (Fase 7f): biblioteca dinámica con ABI C sobre AppCore + ejecutable de humo sin Flutter.
let package = Package(
    name: "AppCoreFFI",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AppCoreFFI", type: .dynamic, targets: ["AppCoreFFI"]),
        .executable(name: "ffi-smoke", targets: ["ffi-smoke"]),
        .executable(name: "ffi-smoke-win", targets: ["ffi-smoke-win"]),
    ],
    dependencies: [
        .package(path: "../../../Packages/AppCore"),
    ],
    targets: [
        // P9 7h: tf_mfvideo.c/tf_d3d.c en Windows (además de sus #pragma comment, por si el enlazador los ignora).
        .target(name: "CAppCoreFFI", cSettings: [.headerSearchPath("dart")],
                linkerSettings: ["mfplat", "mfreadwrite", "mfuuid", "d3d11", "dxguid", "ole32"].map {
                    .linkedLibrary($0, .when(platforms: [.windows]))
                }),
        .target(name: "AppCoreFFI", dependencies: ["CAppCoreFFI", .product(name: "AppCore", package: "AppCore")]),
        .executableTarget(name: "ffi-smoke", dependencies: ["CAppCoreFFI", "AppCoreFFI"]),
        // P9 7b: humo de Windows; carga la DLL por LoadLibrary (no depende de AppCoreFFI, así prueba la DLL real).
        .executableTarget(name: "ffi-smoke-win"),
    ]
)
