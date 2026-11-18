// swift-tools-version: 6.0
// Prueba b del paso 4 (Fase 7c): pocketfft (C, BSD-3, vendorizado en fuente) como sustituto de vDSP_DFT,
// comparado con referencias calculadas en el Mac con vDSP.
import PackageDescription

let package = Package(
    name: "tf-p8-fft",
    targets: [
        .target(name: "PocketFFTC", path: "Sources/PocketFFTC",
                exclude: ["LICENSE.md"]),
        .executableTarget(name: "tf-p8-fft", dependencies: ["PocketFFTC"], path: "Sources/tf-p8-fft"),
    ]
)
