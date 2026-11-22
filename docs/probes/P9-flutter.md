# P9 · Viabilidad de la interfaz Flutter

**Estado: planificada (22/11/2026), sin ejecutar.** Primera parte de la Fase 7f. Decide si se mantienen las decisiones marcadas (P9) en [ADR-021](../adr/ADR-021.md). Código en `Probes/P9-flutter/` (fuera de la puerta de tests); resultados, en este fichero, debajo de cada prueba.

## Reglas

- **Fallar rápido** y por orden: una prueba que incumple su umbral se para y se devuelve a Jorge como pregunta con alternativas (el respaldo previsto es la primera). No se completa el resto de casos de esa prueba.
- Nada de `Packages/`, `App/` ni `WinApp/` cambia de comportamiento. `AppCoreFFI` se crea aquí en su forma mínima y, si P9 pasa, es la base de la ola 0.
- Hardware y oído son de Jorge: los agentes devuelven números y el comando para repetir.
- Mac primero. El PC x64 se usa dos veces: en cuanto la prueba 2 esté verde en el Mac, la primera parte de la 7 (hilos de Windows y compilación de las candidatas de WebView), porque es el riesgo mayor y puede cambiar la arquitectura; al final, el resto de la 7 con todo verde en el Mac. *Pendiente de confirmar por Jorge.*
- Aviso: la documentación consultada es de Flutter 3.47, no 3.50, y no hay ninguna medida propia todavía. Notas en `Temp/research/7f-*.md` y prueba previa en `Temp/flutter-probe/RESULT.md` (no versionados).
- Siempre `--projects-folder` y `--support-dir` a una copia.

## Pruebas

| # | Prueba | Qué se hace | Umbral de paso | Respaldo si falla |
| --- | --- | --- | --- | --- |
| 1 | Entorno | FVM + Flutter 3.50.1 en el Mac; `flutter create` de escritorio (macOS, Windows) en `Probes/P9-flutter/app`; paso de argumentos de línea de comandos a `main(args)` en las dos plataformas; fuentes Inter y Space Grotesk cargadas. | Arranca con `open -g` sin robar foco y lee `--screen x`. | — |
| 2 | FFI e hilos (Mac) | `AppCoreFFI` mínimo (`tf_core_start/send/free/shutdown`, callback de mensajes). Dart llama a `library.list`, `settings.get`, `audio.devices` (pasa por `@MainActor`) y recibe eventos emitidos desde hilos de fondo (`jobs.progress` de una importación por fichero). Además: `NativeCallable.listener` contra puerto nativo (`Dart_PostCObject_DL` con `kExternalTypedData`), latencia mediana y p99 a 60 Hz con el isolate ocupado; µs por mensaje de JSON de 300 bytes, `jsonDecode(utf8.decode)` contra `utf8.decoder.fuse(json.decoder)`. | 1000 llamadas seguidas sin error ni fuga apreciable; ida y vuelta mediana < 5 ms; ningún bloqueo del hilo de UI > 16 ms; cierre limpio (sin procesos hijos vivos). Nativo→Dart: gana el de menor p99 de latencia y jitter; si ninguno baja de 1 ms por mensaje o hay fotogramas perdidos, se evalúa isolate auxiliar o canal binario. | Proceso núcleo aparte. |
| 3 | Fotogramas | Cámara simulada (`--camera simulated`), textura externa (`CVPixelBuffer` en Mac) contra copia BGRA por FFI + `decodeImageFromPixels`, a 720p30 y 1080p30, 60 s cada una. Medir CPU del proceso, ms por fotograma en el hilo de UI y en el de raster, fotogramas descartados, memoria y número de copias. | 0 descartes a 720p30 y a 1080p30 con textura y memoria estable; entre las que pasan, gana la de menor CPU. | Copia BGRA + `decodeImageFromPixels`. |
| 4 | WebView (Mac) | Las dos candidatas de Mac (`webview_all`, `webview_flutter`) con los criterios de la prueba del 21/11 (base en `Temp/flutter-probe/`): `tab.html` + `tf-bridge.js` + alphaTab desde recursos locales (Bravura y SoundFont resueltos), mensajes JS↔Dart en las dos direcciones, teclado dentro de la partitura con el foco yendo y volviendo a un campo de texto de Flutter, redimensionado. Además: overlay de Flutter encima del WebView, WebView oculto de Songsterr con UA de Safari que devuelve su HTML, y comportamiento con la ventana tapada. | Todo funciona; ninguna tecla de edición se pierde ni llega duplicada. Entre las que pasan, la de mejor mantenimiento y menor coste (decide Jorge si empatan). | `flutter_inappwebview`. |
| 5 | Vídeo (Mac) | `fvp` con `onSync` contra reproductor nativo (`AVPlayer` esclavo del reloj de audio → `CVPixelBuffer` → textura), con una toma real (MOV HEVC 1080p30 y MP4 H.264, una con rotación 90°) y un reloj con la forma de `takeview.position` a 30 Hz. Medir el error A/V por fotograma a 50, 70 y 100 % de velocidad, tras un salto y en bucle, y el tiempo al primer fotograma correcto tras un salto con HEVC 1080p30. | Error ≤ medio fotograma en régimen; recuperación tras salto < 300 ms; rotación correcta. Gana el de menor error medido; si es el nativo, se anota el coste de Media Foundation en Windows. | La otra candidata. |
| 6 | Captura y tests | `--snapshot <png>` con `RepaintBoundary.toImage`; un golden con `matchesGoldenFile` y las fuentes reales, generado en el Mac; `flutter analyze` y `flutter test` desde `Tools/test.sh FlutterApp` con salida resumida. | PNG correcto sin ventana en primer plano; golden estable en dos ejecuciones. | Captura de ventana con la herramienta de la 7c. |
| 7 | PC x64 | `Tools/flutter/pc.sh`: pasa la rama por ssh, compila `AppCoreFFI.dll` y la app, copia junto al `.exe` las DLL del runtime de Swift, ONNX Runtime y DirectML, arranca y trae capturas. **Primero** hilos (vía 1: ventana y motor en hilo propio STA con el principal en `dispatchMain()`; vía 2: `tf_core_pump` con `MsgWaitForMultipleObjects` y `_dispatch_main_queue_callback_4CF`) y compilación de cada candidata de WebView con el Visual Studio del PC. Luego: textura con Impeller (`GpuSurfaceTexture`, respaldo `PixelBufferTexture`; vigilar «Could not create external texture»); WebView (fps y latencia de la captura a 100 y 150 % de DPI, teclas perdidas o duplicadas, foco con un `TextField`, repintado tras redimensionar con y sin el bucle rAF de la prueba previa); vídeo (HEVC y H.264, rotación). Repite 2 y comprueba que el hilo de UI sigue en STA tras iniciar Media Foundation. | Mismos umbrales que en el Mac. Una candidata de WebView que no compile con el VS del PC no pasa salvo parche pequeño y aislado. | Hilos: vía 2 y, si falla, proceso núcleo aparte (pregunta a Jorge). Textura: `PixelBufferTexture`, luego copia BGRA. WebView y vídeo: por prueba, las de arriba. |

## Reparto

Orquestador (Opus): escribe la mini-spec de cada prueba a partir de esta tabla y de `docs/flutter/contrato.md` («Hilos», «Servicios de anfitrión»), integra y decide si se sigue. `tf-implementer` (Sonnet): `AppCoreFFI` mínimo, entrega de fotogramas a la textura y, si gana, el reproductor nativo (pruebas 2, 3 y 5, lado Swift). `tf-flutter` (Sonnet): app de prueba y lado Dart de 2 a 6. `tf-implementer`: `Tools/flutter/pc.sh` (prueba 7). `web-researcher` solo si una prueba falla y hay que elegir respaldo. `tf-docs`: resultados en este fichero. Commit al cerrar P9.

## Qué fija P9 al terminar

ABI de `AppCoreFFI` congelada; mecanismo nativo→Dart (`listener` o puerto nativo); vía de hilos en Windows (1, 2 o proceso aparte) y, con ello, si existe `tf_core_pump`; textura externa o copia BGRA, y resolución y fps por canal; paquete de WebView por plataforma; motor de vídeo (`fvp` o nativo) y su umbral de error A/V; versiones exactas de los plugins en `pubspec.yaml`. Se anotan aquí y en `docs/flutter/arquitectura.md`.

## Resultados

*(vacío hasta ejecutar)*
