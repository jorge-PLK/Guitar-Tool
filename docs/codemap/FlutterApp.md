# FlutterApp

| Fichero | qué hace (ADR-021) |
| --- | --- |
| `FlutterApp/lib/core/` (`ffi_bindings`, `core_client`, `call_timeouts`, `host_services`, `frame_channel`, `mock_core`, `launch_options`, `core_providers`) | Puente con el núcleo: enlaces FFI, `CoreClient` (llamadas con tiempos de espera de `call_timeouts`), `HostServices` (peticiones `hostRequest`), `FrameChannel` (píxeles crudos), `MockCore`, `LaunchOptions` y los providers de Riverpod |
| `FlutterApp/lib/theme/` (`tokens`, `typography`, `fmt`, `icons`, `icons_data*`) | Tokens `TfColors`/`TfRadius`/`TfSize`, tipografía, formato (`Fmt`) e iconos `TfIcons` (trazos de Lucide en `icons_data*.dart`) |
| `FlutterApp/lib/widgets/` (`tf_*.dart`) | Kit de widgets compartidos, un fichero por componente, incluido `tf_video_surface.dart` (`TfVideoSurface`, textura de vídeo; recibe `frameSize` por parámetro) |
| `FlutterApp/lib/shell/` (`shell_route`, `shell_providers`, `shell_screen`, `snapshot`) | Carcasa con barra lateral y seis rutas, estado de la carcasa y `--snapshot` |
| `FlutterApp/lib/features/<área>/` | Pantallas provisionales por área (`backing`, `library`, `montage`, `record`, `settings`, `tab`); Ajustes con 3 pestañas |
| `FlutterApp/lib/l10n/` | ARB es/en con un bloque ancla por área (`<área>Anchor`); el código generado está versionado |
| `FlutterApp/test/support/harness.dart`, `shell_harness.dart` | Arneses de test para widgets y para la carcasa |
| `FlutterApp/test/theme/no_literals_test.dart` | Prohíbe literales de texto de cara al usuario en `lib/`; exención con `// tf-literal-ok: <motivo>` |
| `FlutterApp/test/**/goldens/` | Goldens; se regeneran con `TF_UPDATE_GOLDENS=1` |

Ejecución: `Tools/test.sh FlutterApp <ruta|nombre>` filtra los tests por ruta o por nombre.
