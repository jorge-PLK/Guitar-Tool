// swift-tools-version: 6.0
import PackageDescription

// La biblioteca no depende de AudioKit: recibe el reloj del audio con tipos propios (`HostTimeMap`) y la app
// hace de puente. Solo `tf-video` y los tests de la puerta (con el audio simulado de la Fase 3) lo usan.
// Plan, «Fase 7c», paso 6: el reloj de host sale de NativePlatform (`mach_absolute_time` o QPC, misma unidad) y
// CryptoKit, que no existe en Windows, se cambia allí por swift-crypto. Paso 7: Media Foundation (CMediaFoundation).
let package = Package(
    name: "VideoKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "VideoKit", targets: ["VideoKit"]),
        // Solo desarrollo (no se embebe): cámaras, grabación y sincronía desde la terminal.
        .executable(name: "tf-video", targets: ["tf-video"])
    ],
    dependencies: [
        .package(path: "../AudioKit"),
        .package(path: "../NativeKit"),
        .package(url: "https://github.com/apple/swift-crypto", from: "3.0.0")
    ],
    targets: [
        .target(
            name: "VideoKit",
            dependencies: [
                .product(name: "NativePlatform", package: "NativeKit"),
                .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.windows])),
                // Paso 7 (parte 7.2): captura, escritor y exportador con Media Foundation; WAV de la mezcla con dr_wav.
                .product(name: "CMediaFoundation", package: "NativeKit", condition: .when(platforms: [.windows])),
                .product(name: "NativeAudioFile", package: "NativeKit", condition: .when(platforms: [.windows])),
                // Parte 7.9: compositor del montaje con Direct2D + DirectWrite.
                .product(name: "CDirect2D", package: "NativeKit", condition: .when(platforms: [.windows])),
                // Parte 7.11: pose del encuadre con MoveNet sobre ONNX Runtime (en el Mac sigue Vision).
                .product(name: "NativeONNX", package: "NativeKit", condition: .when(platforms: [.windows]))
            ]
        ),
        // Parte 7.11b: en Windows, `tf-video` escribe el WAV de silencio con dr_wav (en el Mac, AVAudioFile).
        .executableTarget(name: "tf-video", dependencies: [
            "VideoKit", .product(name: "AudioKit", package: "AudioKit"),
            .product(name: "NativeAudioFile", package: "NativeKit", condition: .when(platforms: [.windows]))
        ]),
        // CMiniz: lector de PNG de los tests de pose (mismo código en el Mac y en Windows).
        .testTarget(name: "VideoKitTests", dependencies: ["VideoKit", "tf-video", .product(name: "AudioKit", package: "AudioKit"),
                                                          .product(name: "CMiniz", package: "NativeKit")])
    ]
)
