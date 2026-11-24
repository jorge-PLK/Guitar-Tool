# ToneForge · Mapa del código

Última actualización: 2026-11-24 · Fase 7c cerrada (ADR-022): `VideoConversion` HEVC→H.264 y evento `takeview.video`, ONNX de BS y guitarras con GLU→Slice (T575 desactivado), ADTOF en CPU, `validCalibration`, `captureDiscontinuity` con `TakeRecorder.filledGaps` y `CoreLog`/`AudioKitLog`.

Una sección por paquete (nombres de `docs/plan.md`, «Forma de trabajo»), más la app, las pruebas y las herramientas. Fila por fichero: `| Fichero | qué hace (ADR-NNN): APIs públicas |`. Cada paquete tiene su ficha en `docs/codemap/`; se lee solo la del paquete que se toca.

Tests del Mac (`tf-qa`, 22/11/2026; entre paréntesis, omitidos): AnalysisKit 1, AppCore 227, AudioKit 251 (3; 256 ejecutados tras el arreglo de `endTime`), HeadRushKit 1, MatchKit 1, ModelKit 20 (4), NativeKit 56 (1), SourceKit 116, StemKit 81 (13), Store 205, StudyKit 46 (4), TabKit 233 (22), Tone3000Kit 1, VideoKit 84 (1); 0 fallos y build de la app OK.

- [Packages/AudioKit](codemap/AudioKit.md)
- [Packages/ModelKit](codemap/ModelKit.md)
- [Packages/StemKit](codemap/StemKit.md)
- [Packages/StudyKit](codemap/StudyKit.md)
- [Packages/SourceKit](codemap/SourceKit.md)
- [Packages/AnalysisKit](codemap/AnalysisKit.md)
- [Packages/MatchKit](codemap/MatchKit.md)
- [Packages/HeadRushKit](codemap/HeadRushKit.md)
- [Packages/Tone3000Kit](codemap/Tone3000Kit.md)
- [Packages/TabKit](codemap/TabKit.md)
- [Packages/VideoKit](codemap/VideoKit.md)
- [Packages/Store](codemap/Store.md)
- [Packages/NativeKit](codemap/NativeKit.md)
- [Packages/AppCore](codemap/AppCore.md)
- [WinApp](codemap/WinApp.md)
- [FlutterApp](codemap/FlutterApp.md)
- [App](codemap/App.md)
- [Probes](codemap/Probes.md)
- [Tools](codemap/Tools.md)
