// swift-tools-version: 5.9
// Paquete de humo del port a Windows (plan, Fase 7c, mini-spec del paso 3).
import PackageDescription

let package = Package(
    name: "tf-smoke",
    targets: [
        .executableTarget(name: "tf-smoke", path: "Sources/tf-smoke")
    ]
)
