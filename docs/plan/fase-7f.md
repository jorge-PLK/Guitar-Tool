# Fase 7f · Interfaz única en Flutter (rama `fase-7f` desde `fase-7c`)

Planificada el 22/11/2026 (ADR-021, 25 decisiones de Jorge). Sustituye SwiftUI (`App/Sources`) y la página de WebView2 (`WinApp/Web`) por una app Flutter en `FlutterApp/` que habla solo con `AppCore`. Port 1:1 con SwiftUI como base visual; únicas funciones nuevas: inglés y selector de idioma. La 7c se da por cerrada en funcionalidad: los desvíos de núcleo se tratan aquí (`docs/flutter/desvios.md`). Sin estimación.

Documentación de la fase, por piezas: `docs/flutter/README.md` (índice). El orquestador empieza por `docs/flutter/orquestador.md`.

- [x] **P9 · Viabilidad** (`docs/probes/P9-flutter.md`): entorno FVM, FFI e hilos, píxeles crudos, WebView, vídeo, captura y tests en el Mac; después todo en el PC x64. Fallar rápido; un umbral incumplido es una pregunta a Jorge. Commit al cerrar. Cerrada 24/11/2026.
- [ ] **Ola 0 · Cimientos:** actualizar las reglas de `CLAUDE.md` (UIs viejas congeladas, paridad sobre Flutter, agentes nuevos); `AppCoreFFI` completo (ABI congelada, canal de píxeles, servicios de anfitrión por `hostRequest`); test que vuelca `Contract/fixtures/`; forma `{code, message, args}` de los errores del núcleo; `FlutterApp/` con `core/` (`CoreClient`, `FrameChannel`, `HostServices`, `MockCore`, `LaunchOptions`), `theme/`, kit de `widgets/`, ARB es/en, carcasa con barra lateral y `--snapshot`; `Tools/flutter/*.sh` y paso `FlutterApp` en `Tools/test.sh`; capturas de referencia de SwiftUI en `docs/flutter/ref/`.
- [ ] **Ola 1 · Biblioteca:** Biblioteca, detalle de tema, grabaciones del tema, importación por fichero y por enlace, listas y álbumes, cola de trabajos, primer arranque, Ajustes · Biblioteca y selector de idioma (`pantallas/biblioteca.md`, `pantallas/ajustes.md`).
- [ ] **Ola 2 · Estudio:** Backing (mezclador, rejilla de acordes, secciones, bucle, metrónomo) y Tablatura (WebView de alphaTab, edición, Songsterr, exportar `.gp`) (`pantallas/backing.md`, `pantallas/tablatura.md`).
- [ ] **Ola 3 · Grabación:** Grabar, Ver toma, Ajustar desfase, Ajustes · Audio (calibración) y Ajustes · Cámara y vídeo (`pantallas/grabar.md`, `pantallas/ajustes.md`).
- [ ] **Ola 4 · Montaje:** Montaje y hoja «Encuadre» (`pantallas/montaje.md`).
- [ ] **Ola 5 · Cierre:** empaquetado de Mac y de Windows (recursos, DLL), mensajes del núcleo por código en todas las áreas que falten, pasada única en el PC x64 al final (tras validar todas las olas en el Mac), borrado de `App/`, `WinApp/Web`, `Tools/webdev` y `FrameRelay` en JPEG, CODEMAP y `CLAUDE.md`.

Cada ola: contrato del área (fixtures → DTO) antes que la pantalla; partes en paralelo si no se pisan; validación con la lista de `orquestador.md`; `tf-qa` una vez; todo se valida primero en el Mac (el PC x64 solo cuando todo esté validado: pasada única al final, con lo pendiente de Windows acumulado en una lista); visto bueno de Jorge sobre las parejas referencia/Flutter.

Orden acordado (24/11/2026): Ola 0 sola → olas 1, 2 y 3 en paralelo (una sesión y un worktree por ola) → ola 4 → ola 5 → pasada del PC. Commits pequeños y frecuentes con push a `fase-7f`, sin preguntar, uno por parte integrada.

Condición de paso (Jorge, 22/11/2026): en el Mac y en el PC x64, con la app Flutter: importar un tema por enlace, separarlo, Backing en bucle al 70 %, tablatura con edición y exportación a `.gp`, grabar una toma con cámara y verla, montar y exportar un vídeo, y Ajustes completos; todas las pantallas y hojas comparadas con su captura de referencia y aceptadas por Jorge; puerta de tests verde; sin SwiftUI ni WebView2 en el repo.

Después de la 7f: Fase 7d (actualizador), instalador de Windows y la fase de cambios de UX que sustituye a la 7b.
