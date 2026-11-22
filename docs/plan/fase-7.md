# Fase 7 · Montaje (RF9)

- [x] Encuadre automático de la guitarra con Vision y ajuste manual — *`GuitarFramerTests`; hoja «Encuadre» probada por Jorge*
- [x] Layouts landscape y portrait, y plano único para una rítmica y una solista — cinco layouts, con cortes libres y regla de cobertura (ADR-018) — *`MontageSingleCoverageTests`, `MontageTimelineTests`*
- [x] Aparición de la solista solo en los solos, a partir de las secciones — *`MontageTimelineTests`, `MontageCompositionCoverageTests`*
- [x] Compositor propio con las transiciones y vista previa en tiempo real — incluido el fundido a negro de la toma que acaba antes — *`MontageCompositionCoverageTests`, `MontageRendererTests`, `MontageAudioFadeTests`, `MontageFrameGridTests`*
- [x] Exportación: vídeo (MOV o MP4, audio AAC), mezcla a -14 LUFS con techo de -1,3 dBTP, rótulo y WAV por pista — *`MontageGateTests`, `MontageOptionsTests`; AudioKit: `LoudnessMeterTests`, `MontageMixerTests`, `MontageMixerOrderTests`, `MontageLimiterSinglePassTests`, `MontageLimiterTruePeakTests`, `TakeResamplingTests`*
- [x] Pantalla de montaje — columna de exportación compacta con (i), orden de carriles arrastrable
- [x] Botón «Rotar» (0°, 90°, 180°, 270°) por cámara y por toma, aplicado al leer sin recodificar (Grabar, Ajustes de vídeo y ficha de toma en Montaje) — *`VideoRotationTests` (VideoKit y Store); el iPhone con Continuidad en vertical sigue sin probar*

Condición de paso: vídeo final exportado en portrait y en landscape.

Cumplida el 18/11/2026 (ADR-018): Jorge probó a mano la app («todo correcto») con el vídeo exportado en portrait y en landscape, y `MontageGateTests` cubre la puerta sin hardware.
