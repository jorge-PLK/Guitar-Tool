// swift-tools-version: 6.0
// Herramienta de desarrollo (solo macOS, NO forma parte de la app): ventana WKWebView que sirve WinApp/Web/ y conecta
// el puente con Packages/AppCore, para iterar la interfaz de Windows sin la VM (plan, «Fase 7c», paso 8, parte 8.2).
import PackageDescription

let package = Package(
    name: "tf-webdev",
    platforms: [.macOS(.v15)],
    dependencies: [.package(path: "../../Packages/AppCore")],
    targets: [
        .executableTarget(
            name: "tf-webdev",
            dependencies: [.product(name: "AppCore", package: "AppCore")],
            swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
