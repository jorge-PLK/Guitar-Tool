# Relevo al PC x64 (rama `pcx64tests`, 22/11/2026)

Estado que deja el Mac para cerrar la Fase 7c en el PC. El prompt de la sesión del PC lo trae Jorge; este fichero es el contexto.

## Ramas
- `fase-7c`: código. Último commit de código del Mac: caja de sección sin acorde entero + gancho `TF_TEST_PICK_FOLDER`.
- `pcx64tests` = `fase-7c` + herramientas de validación (`Tools/win/eval/`, `Tools/win/make-pc-bundle.sh`, este fichero).
  Jorge avanza Flutter en paralelo desde `fase-7c` y luego se juntan; se espera poco conflicto.

## Hecho en el Mac (suite Mac verde antes del commit)
- `894319e`: B1 separador de guitarras en Windows, B2 carpeta en caliente, B3 primer arranque, B4 fotos de artista, ProjectsRoot.
- `a5f9eb6`: familia «fichero abierto» (A1, A2), B6 cierre ordenado, C huella de guitarras con SHA-256, D1 `takeFrame` del Mac en
  AppCore, D2 FrameRelay determinista + mediciones R3/M2.
- Después: caja de sección sin acorde entero (`App/Sources/SectionBoxes.swift`, `WinApp/Web/backing/strip.js`; solo interfaz,
  sin verificar a la vista y no se verificará: Jorge, 22/11, queda obsoleta con Flutter) y gancho de prueba `TF_TEST_PICK_FOLDER`
  (`Bridge.requestFolder` en `Packages/AppCore/Sources/AppCore/ImportMethods.swift`; los lanzadores `b2-launch.ps1` y
  `b34-launch.ps1` lo ponen por defecto, `-NoPickHook` vuelve a UIA o al interceptor).
- VM x64: B1 pos 35/35 (skip 2), neg 12/12 (skip 1). Montaje full 21/22: FAIL `salida.preview-viva` (ningún fotograma tras
  saltar a 125 s; 4 entregados). Cancel sin ejecutar en la VM (falló `schtasks /ST`): lo cubre el pase del PC.
- `plan.md:397` (interruptor L/R) NO era hueco: Windows iguala al Mac desde `773a456` (`mixer.js:185`).
- D1: el Mac ya tenía su hoja de Encuadre (`App/Sources/MontageFramingSheet.swift`); no se añadió otra.

## Números R3/M2 (Mac, `TF_FRAME_PERF=1`, `FramePathPerfTests`)
- R3 1080p NV12 → 640 px: JPEG 1,70/1,81 ms (p50/p95); JPEG+base64+emit 2,08/2,21; 15,1 fps; CPU 4,1 %; 122 KB.
- R3 720p: JPEG 1,67/1,73; total 2,04/2,12; CPU 4,0 %.
- M2 single 30 fps: componer 13,0/14,7 ms; JPEG 1,28; 30,1 fps; CPU 23 %. Side (2 tomas): componer 17,5/20,5; CPU 33,9 %.
- Push peor (Mac): 0,0014 / 0,0005 / 0,033 ms.

## 2004 Remix (Mac, Core ML frente a VM, ONNX)
Mismo `audio/song.wav` (SHA-256 89c68d12…, 319,27 s, 44,1 kHz) y mismo modelo `bs-roformer-sw@gridshift-fp16`; medido con
copia literal de `StemLevelMeter` (sobre los stems de la VM reproduce las cifras de la VM).

| stem | Mac Core ML RMS / pico (dBFS) | VM ONNX CPU RMS / pico | `isEmpty` Mac / VM |
|---|---|---|---|
| piano | −104,1 / −73,0 | −77,3 / −31,0 | true / true |
| otros | −85,3 / −40,5 | −75,3 / −36,6 | true / true |

- Conclusión: la fuga es del camino Windows/ONNX, no del tema (piano 42 dB de diferencia en el pico; otros 3,9 dB, menos rotundo).
- Picos de la VM (ventanas de 50 ms > −50 dBFS): piano en 71,3 s y 73,7 s; otros en una cola de 317,5 a 318,3 s (último trozo). En
  el Mac, nada en piano por encima de −50 y un pico suelto de −40,5 en otros a 280,0 s.
- Sin decidir si es kernel de ONNX Runtime o troceado/relleno del último trozo en Windows (la cola final apunta a lo segundo). El
  PC lo discrimina separando el mismo `song.wav` en CPU y DirectML (material en `remix-2004.zip`, que trae Jorge).
- Mac: 19,6 s/min (Core ML `.cpuAndGPU`, 50 trozos, con la suite corriendo en paralelo).
- Estado completo en el Mac: `Temp/win/remix-coreml-state.md`; WAV de escucha `Temp/win/remix/CHECK_remix_*.wav`.

## Decisiones de Jorge (22/11)
- La 7c se cierra tras la pasada en el PC, y se cierra desde el PC (`/phase-close` en `pcx64tests`).
- «Audio y cámara reales del Mac por AppCore» se valida con Flutter; no bloquea el cierre.
- Puente bajo carga y F3 se miden en el PC. F3: Jorge decide con los números.
- «2004 Remix» (fuga de piano/otros: ¿ONNX o el tema?) se mide en el Mac con Core ML; resultado abajo, en «2004 Remix».
- CUDA: después de DirectML, en otra sesión en el PC; no va en el zip.
- Instalador, helpers en el instalador, paridad visual y deuda «Mac usa AppCore»: fuera de la 7c (Flutter → 7d → instalador).

## Para `tf-docs` en el cierre
CODEMAP: `Library.FileReleaser`/`setFileReleaser`, `JobEngine.setFileReleaser`, `StudyService.releaseFiles`, `loadTracks(excluding:)`,
`RecordController.flattenPunch`, `TakeViewService.release(takeId:)`, `RecordService.willDeleteTake`, `FileOps.removeRetrying`,
`Library.takeFolderRemover`, `Bridge.addShutdownHook`, `LinkEngine.cancelAll`, `GuitarAppliedState.inputSHA256`,
`TakePreview.frame(at:videoOffset:punchOffsets:)` (Mac), FrameRelay `after:` (interno), `Bridge.environment` (público, inyectable),
`Bridge.testPickFolderVariable` (público), `Bridge.requestFolder` (interno), `Tools/win/eval/pass.ps1`, `make-pc-bundle.sh`.
plan.md: marcar B1-B4, B6, A1 (no era hueco), M1, R3/M2 (números arriba), `:397` resuelto (no era hueco), `:398` hecho (código en
las dos; sin verificación visual por decisión de Jorge, obsoleto con Flutter), y los resultados de esta pasada (DirectML, F3, puente bajo carga, 2004 Remix, grabación y cámara reales).
