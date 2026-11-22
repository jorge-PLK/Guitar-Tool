// swift-tools-version: 6.0
// Núcleo portátil de la interfaz WebView2 de Windows (plan, «Fase 7c», paso 8, parte 8.1; ADR-020):
// opciones de arranque, router JSON y métodos de la Biblioteca. Solo Foundation y Store.
import PackageDescription

let package = Package(
    name: "AppCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AppCore", targets: ["AppCore"])
    ],
    dependencies: [
        .package(path: "../Store"),
        // 8.3a: servicios de importación, separación y análisis (`Services.swift`).
        .package(path: "../AudioKit"),
        .package(path: "../ModelKit"),
        .package(path: "../StemKit"),
        .package(path: "../StudyKit"),
        // 8.3b: importación por enlace (`ExternalSources.swift`, `LinkMethods.swift`).
        .package(path: "../SourceKit"),
        // 8.7: tablatura (`Tab*.swift`).
        .package(path: "../TabKit"),
        // L-F8: duración de las tomas (`AudioFileReader`, también en Windows).
        .package(path: "../NativeKit"),
        // W2-C: Grabar y Montaje en Windows (`VideoKit`).
        .package(path: "../VideoKit")
    ],
    targets: [
        .target(name: "AppCore", dependencies: ["Store", "AudioKit", "ModelKit", "StemKit", "StudyKit", "SourceKit", "TabKit", "VideoKit",
                                          .product(name: "NativeAudioFile", package: "NativeKit")]),
        // W2-E2: los tests usan VideoKit y AudioKit directamente (FrameRelayTests, RecordTests): declarados, no transitivos.
        // B1: ModelKit y StemKit para GuitarSplitterTests (catálogo de prueba y separador simulado).
        .testTarget(name: "AppCoreTests", dependencies: ["AppCore", "Store", "SourceKit", "StudyKit", "TabKit", "VideoKit", "AudioKit",
                                                         "ModelKit", "StemKit"])
    ]
)
