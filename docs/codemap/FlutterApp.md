# FlutterApp

| Fichero | qué hace (ADR-021) |
| --- | --- |
| `FlutterApp/lib/core/` (`ffi_bindings`, `core_client`, `call_timeouts`, `host_services`, `frame_channel`, `mock_core`, `launch_options`, `core_providers`) | Puente con el núcleo: enlaces FFI, `CoreClient` (llamadas con tiempos de espera de `call_timeouts`), `HostServices` (peticiones `hostRequest`), `FrameChannel` (píxeles crudos), `MockCore`, `LaunchOptions` y los providers de Riverpod |
| `FlutterApp/lib/theme/` (`tokens`, `typography`, `fmt`, `icons`, `icons_data*`) | Tokens `TfColors`/`TfRadius`/`TfSize`, tipografía, formato (`Fmt`) e iconos `TfIcons` (trazos de Lucide en `icons_data*.dart`) |
| `FlutterApp/lib/widgets/` (`tf_*.dart`) | Kit de widgets compartidos, un fichero por componente, incluido `tf_video_surface.dart` (`TfVideoSurface`, textura de vídeo; recibe `frameSize` por parámetro) |
| `FlutterApp/lib/shell/` (`shell_route`, `shell_providers`, `shell_screen`, `snapshot`) | Carcasa con barra lateral y seis rutas, estado de la carcasa y `--snapshot` |
| `FlutterApp/lib/features/<área>/` | Pantallas provisionales por área (`backing`, `library`, `montage`, `record`, `settings`, `tab`); Ajustes con 3 pestañas |
| `FlutterApp/lib/features/library/` (`library_store`, `library_actions`, `library_logic`, `library_prefs`, `project_detail_store`, `import_store`, `link_import_store`/`_logic`/`_actions`, `playlist_store`/`_logic`) (ola 1, ADR-021) | Stores de Riverpod de Biblioteca, detalle, importación por fichero y enlace, y listas; `link_import_actions.dart` agrupa las acciones de la hoja de enlace; `library_prefs` guarda Temas/Artistas con `shared_preferences` |
| `FlutterApp/lib/features/library/` (`library_screen`, `project_detail_page`, `widgets/`, `dialogs/`, `sheets/`) | Pantalla de lista y artistas, detalle con grabaciones, diálogos (`trash`, `clean`, `delete_take`, `duplicate`) y hojas de importación, lista, `song_info_sheet` y `first_run_sheet` |
| `FlutterApp/lib/features/library/library_format.dart`, `library_errors.dart`, `source_messages.dart`, `library_metrics.dart` | `resolveCoverPath` (portada de fila a ruta de fichero) y `displayPath` (abrevia HOME a `~`), meses literales es/en; `showCoreErrorAlert`/`coreErrorText`; textos de `SourceError`/`SpotifySearchError` por `args` o regex (desvío L14); medidas propias de la pantalla |
| `FlutterApp/lib/features/library/library_alerts_host.dart` | `LibraryAlertsHost({child})`: cola FIFO de alertas de biblioteca, una visible; montado en la carcasa |
| `FlutterApp/lib/features/settings/settings_library_tab.dart`, `settings_library_store.dart`, `settings_models_store.dart`, `settings_tools_store.dart` (ola 1) | Pestaña Ajustes · Biblioteca (carpeta con `library.relocate`, uso de disco, modelos, herramientas) e Idioma |
| `FlutterApp/lib/l10n/` | ARB es/en con un bloque ancla por área (`<área>Anchor`); el código generado está versionado |
| `FlutterApp/test/support/harness.dart`, `shell_harness.dart` | Arneses de test para widgets y para la carcasa |
| `FlutterApp/test/theme/no_literals_test.dart` | Prohíbe literales de texto de cara al usuario en `lib/`; exención con `// tf-literal-ok: <motivo>` |
| `FlutterApp/test/**/goldens/` | Goldens; se regeneran con `TF_UPDATE_GOLDENS=1` |

Ejecución: `Tools/test.sh FlutterApp <ruta|nombre>` filtra los tests por ruta o por nombre.
