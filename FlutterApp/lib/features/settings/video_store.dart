import 'dart:async';
import 'dart:ui' show Size;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/patch.dart';
import 'package:toneforge/contract/video.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/features/record/record_store.dart';
import 'package:toneforge/shell/shell_providers.dart';
import 'package:toneforge/shell/shell_route.dart';

/// Estado de Ajustes · Cámara y vídeo: refleja lo que publica el núcleo.
class VideoStoreState {
  const VideoStoreState({
    this.cameras,
    this.settings,
    this.preview,
    this.loading = false,
    this.error,
  });

  final VideoCameras? cameras;
  final VideoSettings? settings;

  /// Último `CameraPreviewResult` (`start` o `stop`).
  final CameraPreviewResult? preview;
  final bool loading;

  /// Último error RPC (`code`, `message`, `args`); la pantalla lo traduce por `code`.
  final CoreError? error;

  /// Tamaño del fotograma para `TfVideoSurface.frameSize`; solo con la previa en vivo y con medidas.
  Size? get frameSize {
    final p = preview;
    final w = p?.width, h = p?.height;
    if (p == null || p.state != PreviewState.live || w == null || h == null) return null;
    return Size(w.toDouble(), h.toDouble());
  }

  VideoStoreState copyWith({
    VideoCameras? cameras,
    VideoSettings? settings,
    CameraPreviewResult? preview,
    bool? loading,
    CoreError? error,
    bool clearError = false,
  }) =>
      VideoStoreState(
        cameras: cameras ?? this.cameras,
        settings: settings ?? this.settings,
        preview: preview ?? this.preview,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}

final videoStoreProvider =
    NotifierProvider<VideoStore, VideoStoreState>(VideoStore.new);

class VideoStore extends Notifier<VideoStoreState> {
  late CoreClient _core;
  bool _active = false; // pestaña Cámara y vídeo visible
  bool _previewOn = false;

  /// `video.preview.start` devolvió `fromRecord`: Grabar tenía la cámara y no se abrió captura propia.
  bool _waitingRecord = false;

  @override
  VideoStoreState build() {
    final core = _core = ref.read(coreClientProvider);
    final sub = core
        .on('video.camerasChanged', (j) => j)
        .listen((_) => _onCamerasChanged(), onError: _ignore);
    ref.listen(shellRouteProvider, (_, _) => _sync());
    ref.listen(settingsTabProvider, (_, _) => _sync());
    // Grabar libera la cámara al terminar `record.close` (después de desmontarse la pantalla): si la
    // previa arrancó antes, quedó atada a esa sesión y se congela; se rehace al cerrarse Grabar.
    ref.listen(recordStoreProvider, (_, next) {
      if (_waitingRecord && next.snapshot == null && !next.opened) _restartAfterRecord();
    });
    ref.onDispose(() {
      sub.cancel();
      if (_previewOn) {
        _previewOn = false;
        core.call('video.preview.stop', const {}, CameraPreviewResult.fromJson)
            .then((_) {}, onError: _ignore);
      }
    });
    Future.microtask(_sync);
    return const VideoStoreState();
  }

  static void _ignore(Object _) {}

  void _set(VideoStoreState s) {
    if (ref.mounted) state = s;
  }

  bool _visible() =>
      ref.read(shellRouteProvider) == ShellRoute.settings &&
      ref.read(settingsTabProvider) == SettingsTab.video;

  /// Entra: carga y arranca la previa. Sale: para la previa.
  Future<void> _sync() async {
    if (!ref.mounted) return;
    final v = _visible();
    if (v == _active) return;
    _active = v;
    if (v) {
      await reload();
      if (ref.mounted && _active) await _startPreview();
    } else {
      await _stopPreview();
    }
  }

  Future<T?> _guard<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on CoreError catch (e) {
      _set(state.copyWith(error: e));
    } on Object catch (e) {
      _set(state.copyWith(error: CoreError('internal', '$e')));
    }
    return null;
  }

  /// `video.cameras` y `video.settings`.
  Future<void> reload() async {
    _set(state.copyWith(loading: true, clearError: true));
    final r = await Future.wait<Object?>([
      _guard(() => _core.call('video.cameras', const {}, VideoCameras.fromJson)),
      _guard(() => _core.call('video.settings', const {}, VideoSettings.fromJson)),
    ]);
    _set(state.copyWith(
        loading: false, cameras: r[0] as VideoCameras?, settings: r[1] as VideoSettings?));
  }

  void clearError() => _set(state.copyWith(clearError: true));

  Future<void> _onCamerasChanged() async {
    if (!_active) return;
    await reload();
    if (ref.mounted && _active) await _startPreview();
  }

  Future<void> _restartAfterRecord() async {
    _waitingRecord = false;
    if (ref.mounted && _active) await _startPreview();
  }

  // El núcleo para la captura anterior al arrancar de nuevo, así que rehacer la previa es otro `start`.
  Future<void> _startPreview() async {
    _previewOn = true;
    final p = await _guard(
        () => _core.call('video.preview.start', const {}, CameraPreviewResult.fromJson));
    if (p != null) _set(state.copyWith(preview: p));
    _waitingRecord = p?.fromRecord ?? false;
    if (ref.mounted && !_active) await _stopPreview();
  }

  Future<void> _stopPreview() async {
    if (!_previewOn) return;
    _previewOn = false;
    final p = await _guard(
        () => _core.call('video.preview.stop', const {}, CameraPreviewResult.fromJson));
    if (p != null) _set(state.copyWith(preview: p));
  }

  /// «Abrir Ajustes del Sistema» (permiso denegado).
  Future<void> openCameraPrivacy() => _guard(() => _core.call(
      'video.openCameraPrivacy', const {}, VideoOpenCameraPrivacyResult.fromJson));

  // --- selectores (cada uno envía solo lo que cambia) ---

  /// `null` = «Por defecto del sistema» (`cameraUID: null` explícito). Rehace la previa.
  Future<void> setCamera(String? uid) => _setSettings(
      VideoSetSettingsParams(cameraUID: uid == null ? const Patch.nullValue() : Patch.of(uid)),
      restartPreview: true);

  Future<void> setResolution(int width, int height) => _setSettings(
      VideoSetSettingsParams(resolution: VideoResolution(width: width, height: height)),
      restartPreview: true);

  Future<void> setFps(double fps) =>
      _setSettings(VideoSetSettingsParams(fps: fps), restartPreview: true);

  /// Sin [cameraId] se aplica a la cámara efectiva; el núcleo redondea y limita a ±500.
  Future<void> setOffset(double ms, {String? cameraId}) => _setSettings(
      VideoSetSettingsParams(offset: VideoOffsetParams(ms: ms, cameraId: cameraId)));

  Future<void> setRotation(int degrees, {String? cameraId}) => _setSettings(
      VideoSetSettingsParams(rotation: VideoRotationParams(degrees: degrees, cameraId: cameraId)));

  Future<void> setExport(VideoExportParams export) =>
      _setSettings(VideoSetSettingsParams(export: export));

  Future<void> _setSettings(VideoSetSettingsParams p, {bool restartPreview = false}) async {
    _set(state.copyWith(clearError: true));
    final s = await _guard(
        () => _core.call('video.setSettings', p.toJson(), VideoSettings.fromJson));
    if (s == null) return;
    _set(state.copyWith(settings: s));
    if (restartPreview && _active && ref.mounted) await _startPreview();
  }
}
