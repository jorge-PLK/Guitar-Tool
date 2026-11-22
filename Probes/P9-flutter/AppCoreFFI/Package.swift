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
        .target(name: "CAppCoreFFI", cSettings: [.headerSearchPath("dart")]),
        .target(name: "AppCoreFFI", dependencies: ["CAppCoreFFI", .product(name: "AppCore", package: "AppCore")]),
        .executableTarget(name: "ffi-smoke", dependencies: ["CAppCoreFFI", "AppCoreFFI"]),
        // P9 7b: humo de Windows; carga la DLL por LoadLibrary (no depende de AppCoreFFI, así prueba la DLL real).
        .executableTarget(name: "ffi-smoke-win"),
    ]
)
