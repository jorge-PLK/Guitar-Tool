# Cierre de la 7c en Windows (mini-spec de la Fase 7c)

Lo aprendido al validar el núcleo en el PC x64 (rama `pcx64tests`, 23-24/11/2026; ADR-022). Complementa la mini-spec del port de `docs/plan/fase-7c.md` y `docs/spec/fase-7.md`.

## Vídeo

- **HEVC → H.264.** En Windows el vídeo de las tomas se convierte a H.264 bajo demanda (`VideoConversion`), a ~4,4 s por minuto de vídeo con nvenc. El reproductor nativo de Flutter (Media Foundation) no abre HEVC sin HEVC Video Extensions, así que `VideoConversion` es la única vía y el visor la dispara también (`TakeViewMethods.requestVideo`).
- **Marcas de tiempo.** `-fps_mode passthrough` redondeaba a una rejilla de 29,97 fps (error máximo 16,7 ms); con `-enc_time_base demux` quedan en 0 ticks y `verify` comprueba también el último fotograma.
- **GOP.** `-g` = fps redondeados (~1 s) y `-bf 0`. Con GOP de 1 s, 5 de 6 saltos se recuperan en 45-90 ms con Media Foundation nativo (el sexto, en 344 ms, lo causa el decodificador); con GOP de 250 fallan 4 de 6.
- **Desfase de Media Foundation.** Medido y aplicado en `WindowsMontage.swift`. Vale con `-bf 0`; con fotogramas B habría que remedirlo.
- **Cámara.** La C925e graba a velocidad variable: media de 24 y 19,3 fps con 30 pedidos (poca luz).

## Modelos

- **ADTOF en CPU.** En DirectML desborda la pila dentro de `DirectML.dll` con T ≥ 8000; el predictor de batería se crea siempre en CPU (`OnnxPredictors.swift`).
- **GLU Split → 2 Slice** en los ONNX de BS y guitarras, con SHA nuevos en el catálogo. DML queda a 116-123 dB de CPU; las guitarras con DML tardan 11 s por minuto frente a ~120 s con CPU. T575 conserva el `Split` y no se usa en Windows (T345 forzado).
- **Proveedor.** DML por defecto y CPU de respaldo, con la arena de ONNX Runtime apagada. El error de modelo nombra el modelo y el log registra `onnx| <modelo> -> <proveedor>`.

## Audio

- **Periodo 480 frente a 512.** WASAPI concede un periodo de 480 muestras; la validez de la calibración (`validCalibration`) ya no lo compara con los 512 del perfil.
- **Discontinuidades de captura WASAPI.** `DuplexClockSync.captureDiscontinuity()` conserva el desfase, lo corrige con la marca QPC del primer paquete y reajusta la recta en segundo plano (`realigns`); `TakeRecorder` solo rellena con ceros el hueco real (`filledGaps`). Cada toma deja la línea `audio.take|` en el log.
- **Caso C.** Si el primer paquete tras la discontinuidad no trae marca QPC válida, la comprobación queda pendiente hasta el siguiente paquete con marca válida. Una posición que mienta hacia delante en un paquete sin marca rellena con ceros y pierde audio real hasta alcanzarla (riesgo aceptado).
