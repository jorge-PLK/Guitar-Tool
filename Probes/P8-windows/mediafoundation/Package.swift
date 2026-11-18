// swift-tools-version: 6.0
// Prueba d del paso 4 (Fase 7c): shim C sobre Media Foundation (MFStartup + IMFSinkWriter) que escribe
// 2 s de vídeo sintético H.264 + audio AAC a MP4, y comprueba si hay codificador HEVC (VideoTakeWriter usa HEVC).
import PackageDescription

let package = Package(
    name: "tf-p8-mf",
    targets: [
        .target(name: "MFShim", path: "Sources/MFShim",
                linkerSettings: [
                    .linkedLibrary("mfplat", .when(platforms: [.windows])),
                    .linkedLibrary("mfreadwrite", .when(platforms: [.windows])),
                    .linkedLibrary("mfuuid", .when(platforms: [.windows])),
                    .linkedLibrary("ole32", .when(platforms: [.windows])),
                ]),
        .executableTarget(name: "tf-p8-mf", dependencies: ["MFShim"], path: "Sources/tf-p8-mf"),
    ]
)
