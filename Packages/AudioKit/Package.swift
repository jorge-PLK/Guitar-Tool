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
    dependencies: [
        // Fachada DSP, ficheros de audio y reloj de host (plan, «Fase 7c», paso 6): vDSP/AVAudioFile/mach en el
        // Mac, portátil en Windows.
        .package(path: "../NativeKit"),
        // CryptoKit no existe en Windows (plan, «Fase 7c», paso 6): swift-crypto solo allí.
        .package(url: "https://github.com/apple/swift-crypto", from: "3.0.0")
    ],
    targets: [
        // Optimizado también en Debug: la mezcla, el medidor y el limitador del montaje son bucles por muestra que sin
        // optimizar tardan 13-15× más (la app se usa en Debug). Solo este target; la app y el resto de paquetes siguen
        // en -Onone. `-O` no relaja la aritmética de coma flotante (sin fast-math ni FMA), así que el audio es el mismo.
        .target(
            name: "AudioKit",
            dependencies: [
                .product(name: "NativeDSP", package: "NativeKit"),
                .product(name: "NativeAudioFile", package: "NativeKit"),
                .product(name: "NativePlatform", package: "NativeKit"),
                // r8brain: el conversor de `AudioImporter` en Windows (plan, «Corte del paso 7», parte 7.1).
                .product(name: "NativeResample", package: "NativeKit"),
                // Signalsmith Stretch: velocidad y tono del reproductor portátil (plan, «Corte del paso 7», parte 7.6).
                .product(name: "CSignalsmith", package: "NativeKit"),
                // Shim WASAPI de `WASAPIAudioIO` (plan, «Corte del paso 7», partes 7.7 y 7.10); solo existe en Windows.
                .product(name: "CWASAPI", package: "NativeKit", condition: .when(platforms: [.windows])),
                .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.windows]))
            ],
            swiftSettings: [.unsafeFlags(["-O"], .when(configuration: .debug))]
        ),
        // En Windows lee/escribe WAV con NativeAudioFile y usa el reloj de NativePlatform (parte 7.6).
        .executableTarget(name: "tf-audio", dependencies: [
            "AudioKit",
            .product(name: "NativeAudioFile", package: "NativeKit"),
            .product(name: "NativePlatform", package: "NativeKit")
        ]),
        .testTarget(
            name: "AudioKitTests",
            dependencies: [
                "AudioKit", "tf-audio",
                .product(name: "NativeDSP", package: "NativeKit"),
                .product(name: "NativeAudioFile", package: "NativeKit"),
                .product(name: "NativePlatform", package: "NativeKit")
            ],
            resources: [.copy("Fixtures")]
        )
    ]
)
