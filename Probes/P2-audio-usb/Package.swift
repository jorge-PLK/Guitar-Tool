// swift-tools-version:5.9
import PackageDescription

// P2 · Audio USB de la HeadRush Flex Prime (Fase 0).
// P2Core: DSP y análisis puros (testeables sin hardware). p2: CLI sobre CoreAudio.
let package = Package(
    name: "P2AudioUSB",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "P2Core"),
        .executableTarget(
            name: "p2",
            dependencies: ["P2Core"],
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AVFoundation"),
            ]
        ),
        .testTarget(name: "P2CoreTests", dependencies: ["P2Core"]),
    ]
)
