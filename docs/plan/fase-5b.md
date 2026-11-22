# Fase 5b · Calidad de la transcripción de guitarra

- [x] Probar Guitab y MuScriptor small frente a Basic Pitch fuera de la app (Python, `tf-ml`, fallar rápido), con El roce como puerta. *Medido contra la tablatura de Songsterr: Guitab E25 gana (F1 0,35–0,39 frente a 0,27–0,30) pero ninguno es reconocible; MuScriptor sin probar (licencia de los pesos).*
- [x] Rítmica escrita desde los acordes de BTC (`ChordShapes`) con el ritmo de los ataques. *Gana en lo rasgueado, 0,00 en los riffs; el híbrido no generaliza. Descartada.*
- [x] Limpieza de lo que da Basic Pitch: puerta de silencio y arreglo del port, techo de registro en MIDI 86. *`SilenceGate`, `TabTrackBuilder.guitarPitchCeiling` (`parametersVersion` 3).*
- [x] Platos de ADTOF confundidos con charles. *`DrumCymbalSeries`; Jorge lo oye mejor en El roce.*
- [x] Prueba de quitar la distorsión antes de transcribir (RemFX), El roce como puerta. *Descartada: en guitar_L, F1 +0,005 (Guitab) y −0,001 (Basic Pitch); entrenado con drive suave simulado, apenas toca la saturación de ampli grabada.*
- [x] Tablatura de Songsterr como fuente por defecto: búsqueda, emparejamiento editable, alineación con el audio; automática de respaldo (mini-spec en `docs/spec.md`, «Calidad de la tablatura»). *Hecho: hoja con vista previa donde elige Jorge (sin comparación automática por la política de acceso de Songsterr), `SongsterrAlignerTests`, `SongsterrImportPlanTests`, `SongsterrConverterTests` y las puertas reales `TF_P5B_TESTS=1` (`SongsterrAlignmentRoceTests`, `SongsterrAlignmentTornadoTests`, `SongsterrAlignmentKamelasTests`, `SongsterrSoloProjectsTests`).*
- [x] Metrónomo y compases de Songsterr (fuera de la lista inicial, decisión de Jorge de oído): `SongsterrBeatGrid`, `tab/songsterr-grid.json`, `StudySession.metronomeBeats`. *`SongsterrBeatGridTests`, `SongsterrBeatGridRoceTests`.*
- [x] Adornos (fuera de la lista inicial): `TabTechniques`, dibujo y `.gp`, 0 sin representar en El roce y Tornado. *`SongsterrTechniquesTests`, `AlphaTabTechniquesTests` y `Probes/P5b-guitarra/check-techniques.js` (46/46).*
- [x] Afinación personalizada. *`TuningCustomTests`.*

Condición de paso (aprobada por Jorge el 16/11/2026): tablatura de 3 temas reconocible en la app (rítmicas, solos y batería con los platos corregidos), juzgado por Jorge; El roce primero. Cumplida el 17/11/2026: «El roce de tu cuerpo» (Platero y Tú, #50624), «Tornado Of Souls» (Megadeth, #12824) y «Aquellas Cosas Que Solíamos Hacer» (Benito Kamelas, #3470719); Jorge: «todo perfecto».

Notas de cierre (ADR-017): Guitab/MuScriptor, la rítmica desde acordes BTC y RemFX quedan descartados. Regla: probar ramas atrasadas con copia aislada (`--projects-folder`, `--support-dir`); el binario de `fase-5b`, sin la Fase 6, borró `recording`, `montage` y el vídeo de El roce.
