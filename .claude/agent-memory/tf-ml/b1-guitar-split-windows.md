---
name: b1-guitar-split-windows
description: B1 «Generar L y R» en Windows frente al Mac: qué ejercita de verdad, por qué no se espera bit a bit con tramos de solo, y cómo probarlo por el camino de la app desde un test temporal de AppCore
metadata:
  type: project
---

- **L/R sin tramos de solo es una copia de canales, sin modelo** (GuitarStemComposer). El modelo lead_rhythm solo actúa en la ventana [tramo ± 1,1 s] y entonces L/R = guitar − solista. Antes de comparar L/R, mira `guitarApplied.options.soloSpans` en project.json (`inputFingerprint` = tamaño-mtime de guitar.wav). En evalB, solo Platero tiene tramo (158,3-183,52).
- Los guitar.wav de evalB son de 48 kHz. El separador remuestrea a 44,1 y vuelve: AVAudioConverter Mastering en el Mac, r8brain en Windows. Con Core ML FP16 frente a ORT y además el remuestreador, lo esperable en la ventana del modelo es un SNR de unos 55 dB (23/11/2026: 55,5 en la solista) y un desfase de 0. DML frente a CPU da unos 127 dB.
- Camino fiel desde un test: `JobServices.production(supportDir:environment:).guitarSplitter!.split(...)`, con `TF_MODELS_DIR`, en AppCoreTests. `#if canImport(NativeONNX)` + `OnnxModelLoader.setLogHandler` compila en AppCoreTests aunque no esté declarado, y registra el proveedor elegido (`onnx| model-<bytes> -> directML`). Los WAV se leen con un lector propio en el test (AudioIO de StemKit es internal). Plantilla: `Temp/win/lr-check/ZZLRCheckTests.swift.txt` + `run.ps1` + `wait.ps1` (espera con tope de 165 s a "rc=" en la salida en segundo plano).

**Why:** el encargo partía de que L/R siempre pasaba por el modelo. Descubrir que era una copia y que la entrada es de 48 kHz cambia qué cifra cabe esperar.
**How to apply:** en cualquier comparación Mac/Windows de pistas de guitarra, separa la parte copiada (que debe salir bit a bit) de la ventana del modelo (unos 55 dB). Ver [[lead-rhythm-contract]], [[ort-directml]].
