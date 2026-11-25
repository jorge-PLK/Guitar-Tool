# FlutterApp

| Fichero | qué hace (ADR-021) |
| --- | --- |
| `FlutterApp/lib/core/` (`ffi_bindings`, `core_client`, `call_timeouts`, `host_services`, `frame_channel`, `mock_core`, `launch_options`, `core_providers`) | Puente con el núcleo: enlaces FFI, `CoreClient` (llamadas con tiempos de espera de `call_timeouts`), `HostServices` (peticiones `hostRequest`), `FrameChannel` (píxeles crudos), `MockCore`, `LaunchOptions` y los providers de Riverpod |
| `FlutterApp/lib/theme/` (`tokens`, `typography`, `fmt`, `icons`, `icons_data*`) | Tokens `TfColors`/`TfRadius`/`TfSize`, tipografía, formato (`Fmt`) e iconos `TfIcons` (trazos de Lucide en `icons_data*.dart`) |
| `FlutterApp/lib/widgets/` (`tf_*.dart`) | Kit de widgets compartidos, un fichero por componente, incluido `tf_video_surface.dart` (`TfVideoSurface`, textura de vídeo; recibe `frameSize` por parámetro) |
| `FlutterApp/lib/shell/` (`shell_route`, `shell_providers`, `shell_screen`, `snapshot`) | Carcasa con barra lateral y seis rutas, estado de la carcasa y `--snapshot` |
| `FlutterApp/lib/features/<área>/` | Pantallas provisionales por área (`backing`, `library`, `montage`, `record`, `settings`, `tab`); Ajustes con 3 pestañas |
| `FlutterApp/lib/features/record/record_screen.dart`, `record_store.dart`, `mixer_store.dart`, `take_viewer_store.dart`, `record_offset_actions.dart`, `record_camera_poll.dart` (ola 3) | Grabar: `RecordScreen`; `recordStoreProvider`/`RecordStore` (snapshot, eventos y acciones); `mixerStoreProvider`/`MixerStore` (mezclador compacto y expandido); `takeViewerStoreProvider`/`TakeViewerStore` (visor de toma); `RecordOffsetActions` (hoja «Ajustar desfase», cola de cambios); `CameraPoller` (`record.pollCamera` cada 2 s en reposo, GR10) |
| `FlutterApp/lib/features/record/widgets/` (`record_body`, `record_header`, `record_bar`, `record_preview`, `record_mixer`, `compact_mixer`, `expanded_mixer`, `parts_panel`, `part_box`, `punch_timeline`, `take_button`, `viewer_controls`, …) | Piezas de Grabar: cabecera, cuerpo, barra de toma, vista previa de cámara, mezclador, partes, línea de punch-in, medidores (`vertical_level_painter`, `horizontal_level_painter`) y controles del visor |
| `FlutterApp/lib/features/record/sheets/` (`add_part_sheet`, `offset_sheet`, `take_viewer_sheet`) | Hojas de Grabar: `AddPartSheet`, `OffsetSheet` (desfase) y `TakeViewerSheet` (visor de toma) |
| `FlutterApp/lib/features/settings/settings_audio_tab.dart`, `settings_video_tab.dart`, `audio_store.dart`, `video_store.dart` (ola 3) | Ajustes: `SettingsAudioTab` y `SettingsVideoTab`; `audioStoreProvider`/`AudioStore` (`audio.*`, medidor y calibración) y `videoStoreProvider`/`VideoStore` (`video.*`, cámaras, vista previa) |
| `FlutterApp/lib/features/settings/sheets/calibration_sheet.dart` (ola 3) | `CalibrationSheet`: pasos, medida en marcha, éxito y fallo; cerrarla en marcha envía `audio.cancelCalibration` (AJ3) |
| `FlutterApp/lib/shell/device_card.dart` (ola 3) | `DeviceCard` de la barra lateral y `deviceStatusProvider` (deducido de `audio.settings` y `audio.devices`, AJ8) |
| `FlutterApp/lib/contract/` (`record`, `record_state`, `audio`, `audio_settings`, `audio_calibration`, `video`, `video_settings`, `takeview`, `core_message`) (ola 3) | DTO de Dart del contrato: `RecordSnapshot` y parámetros de `record.*`; `AudioState`, `AudioSettings`, `AudioCalibrationState`; `VideoSettings`, `CameraInfo`; `TakeViewSnapshot` (con `videoWidth`/`videoHeight`/`videoRotation`, FC1) y `TakeViewVideoEvent`; `CoreMessage {code, message, args}` |
| `FlutterApp/lib/l10n/` | ARB es/en con un bloque ancla por área (`<área>Anchor`); el código generado está versionado |
| `FlutterApp/test/support/harness.dart`, `shell_harness.dart` | Arneses de test para widgets y para la carcasa |
| `FlutterApp/test/theme/no_literals_test.dart` | Prohíbe literales de texto de cara al usuario en `lib/`; exención con `// tf-literal-ok: <motivo>` |
| `FlutterApp/test/**/goldens/` | Goldens; se regeneran con `TF_UPDATE_GOLDENS=1` |

Ejecución: `Tools/test.sh FlutterApp <ruta|nombre>` filtra los tests por ruta o por nombre.
