# Fase 7f · Interfaz única en Flutter (rama `fase-7f` desde `fase-7c`)

Planificada el 22/11/2026 (ADR-021, 25 decisiones de Jorge). Sustituye SwiftUI (`App/Sources`) y la página de WebView2 (`WinApp/Web`) por una app Flutter en `FlutterApp/` que habla solo con `AppCore`. Port 1:1 con SwiftUI como base visual; únicas funciones nuevas: inglés y selector de idioma. La 7c se da por cerrada en funcionalidad: los desvíos de núcleo se tratan aquí (`docs/flutter/desvios.md`). Sin estimación.

Documentación de la fase, por piezas: `docs/flutter/README.md` (índice). El orquestador empieza por `docs/flutter/orquestador.md`.

- [x] **P9 · Viabilidad** (`docs/probes/P9-flutter.md`): entorno FVM, FFI e hilos, píxeles crudos, WebView, vídeo, captura y tests en el Mac; después todo en el PC x64. Fallar rápido; un umbral incumplido es una pregunta a Jorge. Commit al cerrar. Cerrada 24/11/2026.
- [x] **Ola 0 · Cimientos:** actualizar las reglas de `CLAUDE.md` (UIs viejas congeladas, paridad sobre Flutter, agentes nuevos); `AppCoreFFI` completo (ABI congelada, canal de píxeles, servicios de anfitrión por `hostRequest`); test que vuelca `Contract/fixtures/`; forma `{code, message, args}` de los errores del núcleo; `FlutterApp/` con `core/` (`CoreClient`, `FrameChannel`, `HostServices`, `MockCore`, `LaunchOptions`), `theme/`, kit de `widgets/`, ARB es/en, carcasa con barra lateral y `--snapshot`; `Tools/flutter/*.sh` y paso `FlutterApp` en `Tools/test.sh`; capturas de referencia de SwiftUI en `docs/flutter/ref/`.

Cerrada 24/11/2026 con visto bueno de Jorge (suite 20:51, Flutter 328 tests); la parte de Windows (AppCoreFFI, runner, sumideros D3D) queda para la pasada del PC al final.
- [x] **Ola 1 · Biblioteca:** Biblioteca, detalle de tema, grabaciones del tema, importación por fichero y por enlace, listas y álbumes, cola de trabajos, primer arranque, Ajustes · Biblioteca y selector de idioma (`pantallas/biblioteca.md`, `pantallas/ajustes.md`).

Cerrada 25/11/2026 con visto bueno de Jorge tras su prueba a mano. Pendiente de Windows en «Pendiente de Windows»; desvíos L14-L16 abiertos para la ola 5 (`docs/flutter/desvios.md`).
- [x] **Ola 2 · Estudio:** Backing (mezclador, rejilla de acordes, secciones, bucle, metrónomo) y Tablatura (WebView de alphaTab, edición, Songsterr, exportar `.gp`) (`pantallas/backing.md`, `pantallas/tablatura.md`).
- [x] **Ola 3 · Grabación:** Grabar, Ver toma, Ajustar desfase, Ajustes · Audio (calibración) y Ajustes · Cámara y vídeo (`pantallas/grabar.md`, `pantallas/ajustes.md`).

Cerrada 26/11/2026 con visto bueno de Jorge; su prueba a mano contra el núcleo real, con las olas 1, 2 y 3 juntas, queda para una sesión aparte. Desvíos GR11-GR19 en `docs/flutter/desvios.md` (GR15 resuelto: Flutter gira el fotograma, validado por Jorge).
- [x] **Ola 4 · Montaje:** Montaje y hoja «Encuadre» (`pantallas/montaje.md`).

Cerrada 27/11/2026 con visto bueno de Jorge (suite 22:10: AppCore 369, Flutter 1678). MO10 y MO11 resueltos en 8cc6eb1 (consultas de solo lectura `montage.snapCut` y `montage.framingBox`); MO12 aceptado; MO13 aceptado. Para Jorge, en su prueba a mano contra el núcleo real: sincronía audio-vídeo ±1 fotograma, exportación real a −14 LUFS, arrastre con ratón y trackpad (ajuste al pulso en vivo), encuadre con vídeo real (caja en vivo en «seguir») y la «→» del popover «Transiciones».
- [ ] **Ola 5 · Cierre:** empaquetado de Mac y de Windows (recursos, DLL), mensajes del núcleo por código en todas las áreas que falten, pasada única en el PC x64 al final (tras validar todas las olas en el Mac), borrado de `App/`, `WinApp/Web`, `Tools/webdev` y `FrameRelay` en JPEG, CODEMAP y `CLAUDE.md`.

Cada ola: contrato del área (fixtures → DTO) antes que la pantalla; partes en paralelo si no se pisan; validación con la lista de `orquestador.md`; `tf-qa` una vez; todo se valida primero en el Mac (el PC x64 solo cuando todo esté validado: pasada única al final, con lo pendiente de Windows acumulado en una lista); visto bueno de Jorge sobre las parejas referencia/Flutter.

Pendiente de Windows para la pasada del PC (se acumula aquí):

- *Ola 1:* `models.list.archiveBytes` del fixture es el de macOS.
- *Ola 1 (L2):* comprobar que borrar un tema abierto en Backing no falla por bloqueo NTFS.
- *Ola 1:* `URL.path` devuelve `/` en `proposedProjectsFolder` (Known Folder Music\ToneForge); comprobar la ruta que ve Dart.
- *Ola 1:* `displayPath` no abrevia HOME en Windows.
- *Ola 4 (MO2):* compilar la rama `#if os(Windows)` de `Bridge.revealItem` y comprobar que `montage.reveal` tras exportar abre el Explorador con el fichero seleccionado.
- [x] *Prueba a mano 26/11, W-1:* los helpers (yt-dlp, Deno, ffmpeg) salían «no disponible». Hecho en 2b624b1 (se buscan junto al exe anfitrión; test `ExternalSourcesHelpersTests`); validado por Jorge en el PC el 27/11/2026.
- [x] *Prueba a mano 26/11, W-2:* la webcam se veía en Ajustes pero Grabar no la reconocía y tardaba en conectar. Hecho en c562ec5 (`FormatCache` e `identities()` en `MediaFoundationCamera.swift`; tests `testCameraOpenTimingAndIdsDiagnostic` y `testSystemCameraOpensInRecordDiagnostic`; `record.open`→live de 2,2-4,1 s a 0,09-0,68 s con la C925e); validado por Jorge en el PC el 27/11/2026.
- [x] *Prueba a mano 26/11, W-3:* Songsterr `load` en Windows respondía `unsupported`. Hecho en e0997b2 (`TfWebView` invisible en el `Overlay` raíz; desvío W3); validado por Jorge en el PC el 27/11/2026.
- *Prueba a mano 26/11, GR5:* sin vídeo de toma en Windows (ola 5).
- [x] *Prueba a mano 26/11:* fixtures T1/Platero ausentes en el PC (8 saltos en `pc.sh models`). Hecho 27/11/2026: `pc.sh models` sube los fixtures de audio (49 ficheros, ~2 GB la primera vez) y ahora hay 0 saltos en CPU y DML. En CPU, T1 10,48 s, T2 12,76 s y T3 14,58 s por canción (límite `maxSecondsPerSong` de `BeatHeavyModelTests`: 20 s en Windows con `TF_ONNX_PROVIDER=cpu`, 10 s en el resto, decisión de Jorge); precisión T1/T2 100 %, T3 99,81 % de pulsos y 99,27 % de downbeats. DML todo verde: Platero compositor 12,1 s frente a 79,9 s en CPU, golpes de Drum T1 iguales a PyTorch, `DirectMLParity` lead_rhythm 123,5 dB y bs_roformer 116,5 dB.
- *Prueba a mano 26/11:* tests de AppCore en Windows: falta repetir dos pasadas completas en el PC tras cc137db (tolerancias de reloj de `RecordTests` y `TakeViewTests`).

Orden acordado (24/11/2026): Ola 0 sola → olas 1, 2 y 3 en paralelo (una sesión y un worktree por ola) → ola 4 → ola 5 → pasada del PC. Commits pequeños y frecuentes con push a `fase-7f`, sin preguntar, uno por parte integrada.

Condición de paso (Jorge, 22/11/2026): en el Mac y en el PC x64, con la app Flutter: importar un tema por enlace, separarlo, Backing en bucle al 70 %, tablatura con edición y exportación a `.gp`, grabar una toma con cámara y verla, montar y exportar un vídeo, y Ajustes completos; todas las pantallas y hojas comparadas con su captura de referencia y aceptadas por Jorge; puerta de tests verde; sin SwiftUI ni WebView2 en el repo.

Después de la 7f: Fase 7d (actualizador), instalador de Windows y la fase de cambios de UX que sustituye a la 7b.
