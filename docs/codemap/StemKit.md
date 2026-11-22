# Packages/StemKit

Separación de stems con BS-RoFormer SW en Core ML, `.cpuAndGPU` (ADR-004, ADR-007).

| Fichero | qué hace (ADR-007): APIs públicas |
| --- | --- |
| `Sources/StemKit/RoformerContract.swift` | Constantes del modelo y `Stem` (`fileName`). Trabaja a 44,1 kHz por dentro |
| `Sources/StemKit/SpectralTransform.swift` | STFT e iSTFT con Accelerate, compatibles con torch |
| `Sources/StemKit/ChunkPlan.swift` | Plan de trozos con solape |
| `Sources/StemKit/MaskModel.swift` | Envoltorio del modelo Core ML; la máscara FP16 llega con el último eje rellenado a 32 y se lee con vImage |
| `Sources/StemKit/ChunkProcessor.swift` | Procesa un trozo: STFT, máscara, iSTFT |
| `Sources/StemKit/AudioIO.swift` | Lectura y escritura de WAV |
| `Sources/StemKit/RoformerSeparator.swift` | `RoformerSeparator.separate(input:outputDirectory:…)`. Entrada a 48 kHz: se remuestrea y los stems salen a 48 kHz con la longitud exacta |
| `Sources/StemKit/MemoryGuard.swift` | `MemoryGuard` (`start`, `stop`, `peakBytes`, `limitExceeded`, `footprint(pid:)`): `phys_footprint` con `proc_pid_rusage`, SIGKILL por encima de `defaultLimitBytes` (10 GB) |
| `Sources/StemKit/SeparationRunner.swift` | `SeparationRunner.run(model:input:outputDirectory:)` lanza el helper, lee el progreso en JSON (`SeparationEvent`, `SeparationError`) y cancela con SIGTERM y luego SIGKILL |
| `Sources/StemKit/StemLevelMeter.swift` | `StemLevelMeter.measure(url:)` (RMS y pico en dBFS por bloques, `StemLevel`), `isEmpty` (RMS < −60 y pico < −30 dBFS; era −40 hasta el 21/11/2026) (ADR-009) |
| `Sources/StemKit/GuitarStemComposer.swift` | (ADR-014) `LeadGuitarSeparating` (protocolo del separador de solista), `GuitarStemComposer.compose(input:outputDirectory:stereo:soloSpans:…)` (pistas `guitar_rhythm`, `guitar_L`, `guitar_R`, `guitar_lead` que suman `guitar.wav`; fundidos de 100 ms), `GuitarStemTrack`, `GuitarSoloSpan.normalized` |
| `Sources/StemKit/CoreMLLeadSeparator.swift` | (ADR-014) `CoreMLLeadSeparator`: Mel-Band RoFormer lead/rhythm en Core ML FP16 sobre `MaskModelContract.leadRhythm` (num_overlap 2); la rítmica es entrada − solista |
| `Sources/StemKit/PanSplitter.swift`, `PanSoloSpan.swift` | (ADR-014) `PanSplitter` (máscaras de panorama por canal, puerta del centro por tramos), `GuitarSide`, `PanSoloSpan`. Sin uso en la app: descartado, ver ADR-014 |
| `Sources/tf-separate/` | Ejecutable `tf-separate` (producto): un proceso por tema, vigilado por `MemoryGuard` |
| `Sources/tf-memhog/` | Ejecutable `tf-memhog`, solo para tests del vigilante |
| `Sources/StemKit/` STFT, `AudioIO.swift`, `MaskModel` (Fase 7c, paso 6) | (ADR-020) STFT/iSTFT sobre `NativeDSP` (ida y vuelta 5,4e-7 a hop 512). Protocolo `MaskModel`; `SystemMaskModel.load` es un stub `[paso 7] onnx-runtime` en Windows; `MaskTensor.copy` ya no depende de Core ML. El remuestreo de `AudioIO` es stub: en Windows solo 44,1 kHz. `arc4random_buf` pasa a semilla `SystemRandomNumberGenerator` + SplitMix64 |
| `Sources/StemKit/WindowsProcess.swift` (Fase 7c, paso 6) | (ADR-020) Solo Windows: `MemoryGuard` con `K32GetProcessMemoryInfo` + `TerminateProcess` (código 137). `MemoryGuard` usa `Int32` en vez de `pid_t`. `tf-separate` y `tf-memhog` compilan en ARM64 y x64 |
| `Sources/StemKit/OnnxMaskModel.swift`, `SeparationSpectrumLayout.swift`, `HelperStop.swift` (Fase 7c, paso 7) | (ADR-020) `OnnxMaskModel`: `MaskModel` sobre `NativeONNX` (T del modelo); `SeparationSpectrumLayout`: máscara = salida / espectro (se prueba en el Mac); `HelperStop`: parada ordenada de `tf-separate` en Windows por evento con nombre (`NativePlatform/GracefulStopWindows.swift`) y `OnnxSession.terminateAll()`. El remuestreo de `AudioIO` usa `StreamResampler` (ya no solo 44,1 kHz) |
| `Sources/StemKit/SeparationTiming.swift` (Fase 7c, paso 8, F3) | (ADR-020) `SeparationTiming` (`start`, `measureModelLoad`, `printReport`; se activa con `TF_SEPARATE_TIMING=1`): desglose por etapa de `tf-separate`, solo instrumentación. Escribe con `try? write(contentsOf:)` porque el exe de Windows puede no tener handles estándar |
| `Sources/StemKit/SeparationRunner.swift` (Fase 7c, paso 8) | (ADR-020) Lanza `tf-separate` con `ChildProcess` y `terminationHandler`: en Windows, sin ventana de consola |
| `Tests/StemKitTests/SeparationTimingTests.swift` (Fase 7c, paso 8) | Tests del desglose de tiempos |
| `Tests/StemKitTests/SeparationSpectrumLayoutTests.swift` (Fase 7c, paso 7) | (ADR-020) Diseño del espectro y máscara en el Mac |
| `Tests/StemKitTests/` | 36 tests (`StemLevelMeterTests`); 3 pesados con `TF_MODEL_TESTS=1` y 1 de referencia Python con `TF_REF_DIR` |
