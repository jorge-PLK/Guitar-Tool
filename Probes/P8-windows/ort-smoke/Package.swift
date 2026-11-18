// swift-tools-version:5.9
// Fase 7c paso 4 (tf-ml): ONNX Runtime por su API C desde Swift en Windows (ARM64 y x64).
// Las cabeceras, la import lib y onnxruntime.dll NO van en git: viven en la VM en C:\ort\
// (NuGet oficial Microsoft.ML.OnnxRuntime 1.32.0: build/native/include -> C:\ort\include,
// runtimes/win-<arch>/native -> C:\ort\<arch>). Solo compila en Windows. Al ejecutar, onnxruntime.dll
// tiene que estar junto al exe (System32 trae otra onnxruntime.dll y va antes que el PATH).
// Uso: build.sh --no-run y copiar exe + C:\ort\<arch>\*.dll a C:\ort\run\<arch>\ (install.ps1 borra C:\ToneForge\<arch>).
import PackageDescription

let package = Package(
    name: "ort-smoke",
    targets: [
        // Envoltorio C mínimo: incluye onnxruntime_c_api.h y enlaza la import lib de la arquitectura.
        .target(name: "COnnxRuntime", path: "Sources/COnnxRuntime"),
        .executableTarget(name: "ort-smoke", dependencies: ["COnnxRuntime"], path: "Sources/ort-smoke"),
    ]
)
