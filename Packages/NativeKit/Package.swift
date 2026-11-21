// swift-tools-version: 6.0
// Capa de plataforma (plan, «Fase 7c», paso 6, parte 6.0; ADR-020): dependencias C vendorizadas en fuente
// (sin binarios) y las fachadas que usan los demás paquetes para compilar en macOS y en Windows.
import PackageDescription

let package = Package(
    name: "NativeKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "NativeDSP", targets: ["NativeDSP"]),
        .library(name: "NativeAudioFile", targets: ["NativeAudioFile"]),
        .library(name: "NativePlatform", targets: ["NativePlatform"]),
        .library(name: "CMiniz", targets: ["CMiniz"]),
        // Paso 7 (parte 7.0): objetivos creados de una vez; las partes 7.1-7.8 los rellenan.
        .library(name: "NativeResample", targets: ["NativeResample"]),
        .library(name: "NativeONNX", targets: ["NativeONNX"]),
        .library(name: "CSignalsmith", targets: ["CSignalsmith"]),
        .library(name: "CTinySoundFont", targets: ["CTinySoundFont"]),
        .library(name: "CWASAPI", targets: ["CWASAPI"]),
        .library(name: "CMediaFoundation", targets: ["CMediaFoundation"]),
        .library(name: "CDirect2D", targets: ["CDirect2D"]),
    ],
    targets: [
        // pocketfft C (BSD-3).
        .target(name: "CPocketFFT", exclude: ["LICENSE.md"]),
        // dr_wav, dr_flac, dr_mp3 (dominio público / MIT-0) con un shim propio.
        .target(name: "CDrAudio", exclude: ["LICENSE", "dr_wav.h", "dr_flac.h", "dr_mp3.h"]),
        // miniz (MIT): inflado de deflate crudo para SourceKit (sustituye a Compression `.zlib`).
        .target(name: "CMiniz", exclude: ["LICENSE"],
                cSettings: [.define("MINIZ_NO_STDIO"), .define("MINIZ_NO_TIME"),
                            .define("MINIZ_NO_ARCHIVE_APIS"), .define("MINIZ_NO_ZLIB_COMPATIBLE_NAMES")]),
        // r8brain-free-src (MIT, C++ de cabeceras) con su envoltorio extern "C".
        .target(name: "CResampler", exclude: ["LICENSE", "r8brain"], cxxSettings: [.define("NOMINMAX")]),
        // Signalsmith Stretch 1.3.x + signalsmith-linear 0.6.6 (MIT, cabeceras en third_party/).
        .target(name: "CSignalsmith",
                exclude: ["third_party"],
                cxxSettings: [.headerSearchPath("third_party"), .define("NOMINMAX")]),
        // tsf.h y tml.h (MIT) con su implementación.
        .target(name: "CTinySoundFont", exclude: ["LICENSE"]),
        // Shims C/COM solo Windows (en el resto compilan vacíos); enlazan sus libs con #pragma comment.
        .target(name: "CWASAPI"),
        .target(name: "CMediaFoundation"),
        .target(name: "CDirect2D"),
        // Cabeceras de la API C de ONNX Runtime 1.32.0; solo Windows. onnxruntime.dll se carga en ejecución (sin import lib).
        .target(name: "COnnxRuntime", exclude: ["LICENSE"]),
        .target(name: "NativeResample", dependencies: ["CResampler"]),
        .target(name: "NativeONNX",
                dependencies: ["NativePlatform", .target(name: "COnnxRuntime", condition: .when(platforms: [.windows]))]),
        .target(name: "NativeDSP", dependencies: ["CPocketFFT"], exclude: ["README.md"]),
        .target(name: "NativeAudioFile", dependencies: ["CDrAudio", "NativeDSP"]),
        .target(name: "NativePlatform"),
        .testTarget(name: "NativeKitTests",
                    dependencies: ["NativeDSP", "NativeAudioFile", "NativePlatform", "CMiniz", "NativeResample", "NativeONNX",
                                   "CSignalsmith", "CTinySoundFont", "CWASAPI", "CMediaFoundation", "CDirect2D"],
                    resources: [.copy("Fixtures")]),
    ]
)
