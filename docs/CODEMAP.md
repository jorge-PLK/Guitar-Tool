# ToneForge · Mapa del código

Última actualización: 2026-11-27 · Fase 7f (ADR-021): olas 1, 2 y 3 cerradas; tras la prueba en el PC, helpers de `AppCore` junto al exe anfitrión en Windows y Songsterr oculto en el `Overlay` raíz (W-1, W-3) y caché de formatos de cámara con `identities()` barato en `VideoKit` (W-2); antes, tras la prueba a mano, canales de audio por dispositivo y salida mono (`ChannelPair.mono`, `BackingMono`), `HiddenSongsterrHost`, `CameraDevice.camera(id:)` y `Tools/flutter/pc.sh`. Ola 2, Backing y Tablatura (`features/backing`, `features/tab`) y desvíos de núcleo K2, K3, K7, K8, K12, TB10, `study.chordVocabulary`, `tab.dismissNotices`, `tab.keyMap` y `tab.score.timing`. Ola 3, Grabar, visor de toma y Ajustes · Audio/Vídeo en Flutter; en `AppCore`, `record.pollCamera`, `CoreMessage`, reproductor nativo de tomas (`TakeVideoPlayer`, canal take, fotograma en pausa y seeks coalescidos) y `TakeTrace`. Ola 1, Biblioteca y Ajustes · Biblioteca en `FlutterApp/lib/features/{library,settings}`; en `AppCore`, `library.markBest`, `ProjectSummary.separationError` y `app.info.proposedProjectsFolder`.

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
