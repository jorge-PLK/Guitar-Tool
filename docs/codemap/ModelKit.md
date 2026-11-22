# Packages/ModelKit

Descarga, verificación y compilación de modelos (paquete añadido en la Fase 1, ADR-007).

| Fichero | qué hace (ADR-007): APIs públicas |
| --- | --- |
| `Sources/ModelKit/ModelDescriptor.swift` | `ModelDescriptor`, `ModelRole`, `ModelArchiveKind` (`zippedCompiledModel`: zip con `.mlmodelc`, no se compila; `bundledZippedMLPackage`: zip de `.mlpackage` dentro de la app, se compila la primera vez) y `ModelCatalog` (`separatorBSRoformerSW`, `beatsBeatThis` (HF `jessengatai/supracut-beat-this`, commit `33fe1a5`), `chordsBTC` (embebido), `all` con los tres): URL, SHA-256 y tamaño (ADR-007, ADR-009) |
| `Sources/ModelKit/ModelStore.swift` | `actor ModelStore`: `ensureInstalled`, `install(_:fromArchive:)`, `delete`, `state`, `states`, `updates`, `diskUsage`; `ModelState`, `ModelError`. El inicializador admite `bundleResourceDirectory` (la app pasa el bundle, los tests un directorio). Descarga, SHA-256, `ditto`, compila y guarda solo el `.mlmodelc` (351 MB) con su `manifest.json` en `Application Support/ToneForge/Models/<id>/` |
| `Sources/ModelKit/Downloading.swift` | Protocolos `ModelDownloading` y `ModelCompiling`; `URLSessionDownloader`; `ModelDownloadError` |
| `Sources/ModelKit/CoreMLCompiler.swift` | `CoreMLCompiler`: `compileModel` (1,7 s; la especialización para la GPU ocurre en la primera carga) |
| `Sources/ModelKit/ModelDescriptor.swift` (Fase 5) | (ADR-016) `ModelCatalog.drumsADTOF`: ADTOF FP32 con GRU nativa, embebido (zip de `.mlpackage`, 1,7 MB, CC BY-NC-SA), entra en `all` |
| `Sources/ModelKit/ModelDescriptor.swift`, `ModelStore.swift`, `Downloading.swift`, `CoreMLCompiler.swift` (Fase 7c, paso 6) | (ADR-020) `public enum ModelFormat { coreML, onnx; static var native }`. `CoreMLCompiler` en Windows es un stub `[paso 7] onnx-runtime`. La descompresión usa `ChildProcess` (`ditto` en Mac, `tar.exe -xf` en Windows); `defaultRoot` = `SupportFolder.toneForge/Models`; descarga con FoundationNetworking. Depende de `NativeKit` (`NativePlatform`) y, en Windows, de swift-crypto |
| `Sources/ModelKit/ModelDescriptor.swift`, `ModelStore.swift` (Fase 7c, paso 7) | (ADR-020) `OnnxModelFile` y `ModelDescriptor.onnxFiles`/`onnxFile(physicalMemory:)`: la separación elige T=345 por defecto y T=575 con ≥ 15 GiB visibles (16 GB nominales). `ModelCatalog.onnxReleaseBase` apunta a `models-win-v1`, sin publicar: los tests con modelo real leen `TF_MODELS_DIR` (`C:\tf-models`). `ModelStore(format:physicalMemory:)` instala `.onnx` (descarga o fichero local, SHA-256, sin compilar). `pose.onnx` aún no está en el catálogo |
| `Tests/ModelKitTests/ModelStoreOnnxTests.swift` (Fase 7c, paso 7) | (ADR-020) Instalación ONNX, elección de T según memoria |
| `Tests/ModelKitTests/ZipHelper.swift` (Fase 7c, paso 6) | (ADR-020) Crea zips de prueba (`tar.exe -a -c -f` en Windows). En Windows se saltan 2 pruebas `[windows]`: zips de `App/Resources/Models` no sincronizados y `file://` en `URLSession` |
| `Tests/ModelKitTests/` | 16 tests (`ModelOriginsTests`: orígenes y catálogo); 1 pesado con `TF_MODEL_TESTS=1` |
