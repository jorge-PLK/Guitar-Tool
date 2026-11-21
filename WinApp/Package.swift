// swift-tools-version: 6.0
// Interfaz WebView2 de Windows (plan, «Fase 7c», paso 8, parte 8.0; ADR-020): anfitrión Win32 + WebView2 (shim C++
// CWebView2Host) y el ejecutable ToneForge que lo une a AppCore. Solo x64. En macOS los dos objetivos compilan vacíos.
//
// Cabeceras y WebView2LoaderStatic.lib salen de Vendor/win/webview2 (Tools/win/fetch-webview2.sh), que
// Tools/win/build.sh copia a C:\tf-webview2 en la VM (TF_WEBVIEW2_DIR lo cambia).
import Foundation
import PackageDescription

let webview2Dir = (ProcessInfo.processInfo.environment["TF_WEBVIEW2_DIR"] ?? "C:/tf-webview2").replacingOccurrences(of: "\\", with: "/")
let onWindows: BuildSettingCondition = .when(platforms: [.windows])

let package = Package(
    name: "WinApp",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "ToneForge", targets: ["ToneForge"])
    ],
    dependencies: [
        .package(path: "../Packages/AppCore"),
        .package(path: "../Packages/NativeKit"),
    ],
    targets: [
        .target(
            name: "CWebView2Host",
            cxxSettings: [
                .unsafeFlags(["-I", "\(webview2Dir)/include"], onWindows),
                .define("NOMINMAX", onWindows),
                .define("UNICODE", onWindows),
                .define("_UNICODE", onWindows),
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "/LIBPATH:\(webview2Dir)/x64"], onWindows)
            ]),
        .executableTarget(
            name: "ToneForge",
            dependencies: [
                .product(name: "AppCore", package: "AppCore"),
                .product(name: "NativePlatform", package: "NativeKit"),
                "CWebView2Host",
            ],
            linkerSettings: [
                // Subsistema Windows (sin consola); el punto de entrada sigue siendo el main de Swift.
                .unsafeFlags(["-Xlinker", "/SUBSYSTEM:WINDOWS", "-Xlinker", "/ENTRY:mainCRTStartup"], onWindows)
            ]),
    ],
    swiftLanguageModes: [.v5]
)
