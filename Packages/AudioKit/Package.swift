// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AudioKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AudioKit", targets: ["AudioKit"]),
        // Solo desarrollo (no se embebe): las medidas con el dispositivo desde la terminal.
        .executable(name: "tf-audio", targets: ["tf-audio"])
    ],
    targets: [
        // Optimizado también en Debug: la mezcla, el medidor y el limitador del montaje son bucles por muestra que sin
        // optimizar tardan 13-15× más (la app se usa en Debug). Solo este target; la app y el resto de paquetes siguen
        // en -Onone. `-O` no relaja la aritmética de coma flotante (sin fast-math ni FMA), así que el audio es el mismo.
        .target(name: "AudioKit", swiftSettings: [.unsafeFlags(["-O"], .when(configuration: .debug))]),
        .executableTarget(name: "tf-audio", dependencies: ["AudioKit"]),
        .testTarget(name: "AudioKitTests", dependencies: ["AudioKit", "tf-audio"], resources: [.copy("Fixtures")])
    ]
)
