// swift-tools-version: 6.0
// Prueba c del paso 4 (Fase 7c): miniaudio (dominio público / MIT-0, fuente vendorizada) como target C:
// contexto WASAPI y dispositivos, hilo de audio llamando a Swift, dúplex por defecto si lo hay, y los
// decodificadores dr_wav/dr_mp3/dr_flac frente a AVAudioFile.
import PackageDescription

let package = Package(
    name: "tf-p8-miniaudio",
    targets: [
        .target(name: "MiniAudioShim", path: "Sources/MiniAudioShim",
                exclude: ["miniaudio.h"],
                linkerSettings: [.linkedLibrary("ole32", .when(platforms: [.windows]))]),
        .executableTarget(name: "tf-p8-miniaudio", dependencies: ["MiniAudioShim"], path: "Sources/tf-p8-miniaudio"),
    ]
)
