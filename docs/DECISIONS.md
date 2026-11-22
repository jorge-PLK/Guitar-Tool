# Decisiones

Una línea por ADR; el texto está en `docs/adr/ADR-NNN.md`. Nuevo ADR = fichero nuevo + su línea aquí.

- [ADR-001](adr/ADR-001.md) · 2026-11-14 · Base: app nativa SwiftUI solo para Mac, modelos en Core ML con ONNX de respaldo, todo en local, el rig no cambia solo al grabar
- [ADR-002](adr/ADR-002.md) · 2026-11-15 · `docs/spec.md` y `docs/plan.md` son la fuente de verdad; el doc de Claude Docs queda como histórico
- [ADR-003](adr/ADR-003.md) · 2026-11-15 · Trabajo con Claude Code: un agente por trabajo, verificación resumida y puerta de tests en el commit
- [ADR-004](adr/ADR-004.md) · 2026-11-15 · Separador: BS-RoFormer SW en Core ML (gridshift) con CPU+GPU y sin Neural Engine; respaldo BSRoformer.cpp; HTDemucs descartado
- [ADR-005](adr/ADR-005.md) · 2026-11-15 · Motor de tempo: `AVAudioUnitTimePitch` con overlap 8; Rubber Band no hace falta
- [ADR-006](adr/ADR-006.md) · 2026-11-15 · Modelos de estudio (BTC, Beat This!, ADTOF) y cierre de la Fase 0 · Etapa 1
- [ADR-007](adr/ADR-007.md) · 2026-11-15 · Base y biblioteca: frecuencia de trabajo elegible, separación en proceso aparte con `MemoryGuard` y paquete ModelKit (Fase 1)
- [ADR-008](adr/ADR-008.md) · 2026-11-15 · Importar temas desde un enlace de YouTube o Spotify: audio de YouTube con yt-dlp, Opus a WAV, helpers embebidos; fase 2b (P7)
- [ADR-009](adr/ADR-009.md) · 2026-11-15 · Herramienta de estudio: reproductor con Varispeed, análisis de pulso, acordes y tonalidad en la app, y stems vacíos (Fase 2)
- [ADR-010](adr/ADR-010.md) · 2026-11-15 · El DI guiado sale de la Fase 5 y pasa a la Fase 8a; la Fase 5 pasa a ser «Tablatura»
- [ADR-011](adr/ADR-011.md) · 2026-11-15 · Cierre de la Fase 2b: SourceKit, helpers embebidos (yt-dlp, Deno, ffmpeg propio), listas y álbumes, repetidos, y eliminar, editar y re-encolar en la biblioteca
- [ADR-012](adr/ADR-012.md) · 2026-11-15 · Fase 3 genérica (sin Flex Prime cableada) y el DI y el reamp salen de la Etapa 1
- [ADR-013](adr/ADR-013.md) · 2026-11-15 · Cierre de la Fase 3: audio con el dispositivo
- [ADR-014](adr/ADR-014.md) · 2026-11-16 · Cierre de la Fase 4: guitarras y secciones (modelo lead/rhythm, tres opciones de guitarra, solo como sección)
- [ADR-015](adr/ADR-015.md) · 2026-11-16 · Cierre de la Fase 6: grabación con vídeo, reloj de host, desfase manual y multitoma
- [ADR-016](adr/ADR-016.md) · 2026-11-16 · Cierre de la Fase 5: tablatura (alphaTab embebido, ADTOF para batería, Guitar Pro 8 comprobado; guitarra insuficiente, pasa a la Fase 5b)
- [ADR-017](adr/ADR-017.md) · 2026-11-17 · Cierre de la Fase 5b: tablatura de Songsterr como fuente por defecto (elige Jorge con vista previa, metrónomo de Songsterr, adornos; la interfaz pasa a la Fase 5c)
- [ADR-018](adr/ADR-018.md) · 2026-11-18 · Cierre de la Fase 7: montaje (encuadre, layouts, compositor, exportación normalizada, plano único con cortes, rotación)
- [ADR-019](adr/ADR-019.md) · 2026-11-18 · Cierre de la Fase 5c: interfaz de la tablatura (voces como pista `vocal` ligada al stem, adornos con teclado, ligadura, mute/solo, bucle por selección; sin prueba manual de Jorge)
- [ADR-020](adr/ADR-020.md) · 2026-11-18 · Port a Windows con WebView2 y alcance completo (aceptado: UI web con núcleo Swift, todo de una, validación en hardware real cuando haya PC; enmienda 21/11/2026: solo x64, AAC sin compensar, T=345/575 por memoria; enmienda 22/11/2026: audio de «Ver toma» en el núcleo, fotogramas por JPEG, H.264 único en Windows, hilo de UI en STA, fin de toma por muestras, instalador fuera de la 7c e interfaz a Flutter tras la 7c)
- [ADR-021](adr/ADR-021.md) · 2026-11-22 · Interfaz única en Flutter (Fase 7f): port 1:1 con SwiftUI como base visual y `AppCore` como único núcleo, FFI en proceso, WebView para la tablatura, píxeles crudos por FFI, vídeo con decodificadores del sistema, DTO a mano con fixtures, Riverpod, español e inglés, Windows en el PC x64; 7b descartada
