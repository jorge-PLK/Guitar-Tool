import 'dart:async';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../contract/takeview.dart';
import '../../core/core_client.dart';
import '../../core/core_providers.dart';
import '../../core/frame_channel.dart';
import '../../core/frame_providers.dart';

enum TakeViewerPhase { closed, loading, open }

/// Vídeo de la toma: `none` = solo audio; `converting` y `error` vienen de `takeview.video`.
enum TakeVideoState { none, converting, ready, error }

@immutable
class TakeViewerState {
  const TakeViewerState({
    this.phase = TakeViewerPhase.closed,
    this.isOffset = false,
    this.projectId,
    this.takeId,
    this.duration = 0,
    this.songStart = 0,
    this.hasBacking = false,
    this.backingOn = false,
    this.playing = false,
    this.position = 0,
    this.rate = 0,
    this.at = 0,
    this.epoch = 0,
    this.outputName = '',
    this.audioError,
    this.video = TakeVideoState.none,
    this.videoProgress,
    this.videoMessage,
    this.videoWidth,
    this.videoHeight,
    this.videoRotation = 0,
    this.textureId,
    this.error,
  });

  final TakeViewerPhase phase;
  /// Abierto con `takeview.openOffset` (hoja «Ajustar desfase»): sin backing.
  final bool isOffset;
  final String? projectId;
  final String? takeId;
  final double duration;
  final double songStart;
  final bool hasBacking;
  final bool backingOn;
  final bool playing;
  /// Segundos de la toma en [at] (último evento o snapshot).
  final double position;
  final double rate;
  /// Reloj de host del núcleo (s) al que corresponde [position].
  final double at;
  final int epoch;
  final String outputName;
  final String? audioError;
  final TakeVideoState video;
  /// Fracción 0…1 de la conversión a H.264; nula si no se conoce.
  final double? videoProgress;
  final String? videoMessage;
  final int? videoWidth;
  final int? videoHeight;
  final int videoRotation;
  /// Textura del canal `take`; nula sin vídeo o sin texturas.
  final int? textureId;
  /// Último error del núcleo (traducir por `code`, caer a `message`).
  final CoreError? error;

  bool get isOpen => phase == TakeViewerPhase.open;
  bool get isLoading => phase == TakeViewerPhase.loading;
  bool get hasVideo => video == TakeVideoState.ready;

  /// «Backing» se puede pulsar: toma abierta con stems y no es la hoja de desfase.
  bool get canToggleBacking => isOpen && hasBacking && !isOffset;

  /// Tamaño del fotograma para `TfVideoSurface.frameSize`.
  Size? get frameSize {
    final w = videoWidth, h = videoHeight;
    return (w == null || h == null || w <= 0 || h <= 0) ? null : Size(w.toDouble(), h.toDouble());
  }

  /// Posición extrapolada a [now] (reloj de host del núcleo, mismas unidades que [at]):
  /// `position + rate * (now - at)` mientras suena, recortada a `0...duration`.
  double positionAt(double now) {
    if (!playing || rate <= 0) return position;
    final t = position + rate * (now - at);
    return t < 0 ? 0 : (t > duration ? duration : t);
  }

  TakeViewerState copyWith({
    TakeViewerPhase? phase,
    bool? isOffset,
    String? projectId,
    String? takeId,
    double? duration,
    double? songStart,
    bool? hasBacking,
    bool? backingOn,
    bool? playing,
    double? position,
    double? rate,
    double? at,
    int? epoch,
    String? outputName,
    String? audioError,
    bool clearAudioError = false,
    TakeVideoState? video,
    double? videoProgress,
    String? videoMessage,
    bool clearVideoStatus = false,
    int? videoWidth,
    int? videoHeight,
    int? videoRotation,
    int? textureId,
    bool clearTexture = false,
    CoreError? error,
    bool clearError = false,
  }) =>
      TakeViewerState(
        phase: phase ?? this.phase,
        isOffset: isOffset ?? this.isOffset,
        projectId: projectId ?? this.projectId,
        takeId: takeId ?? this.takeId,
        duration: duration ?? this.duration,
        songStart: songStart ?? this.songStart,
        hasBacking: hasBacking ?? this.hasBacking,
        backingOn: backingOn ?? this.backingOn,
        playing: playing ?? this.playing,
        position: position ?? this.position,
        rate: rate ?? this.rate,
        at: at ?? this.at,
        epoch: epoch ?? this.epoch,
        outputName: outputName ?? this.outputName,
        audioError: clearAudioError ? null : (audioError ?? this.audioError),
        video: video ?? this.video,
        videoProgress: clearVideoStatus ? null : (videoProgress ?? this.videoProgress),
        videoMessage: clearVideoStatus ? null : (videoMessage ?? this.videoMessage),
        videoWidth: videoWidth ?? this.videoWidth,
        videoHeight: videoHeight ?? this.videoHeight,
        videoRotation: videoRotation ?? this.videoRotation,
        textureId: clearTexture ? null : (textureId ?? this.textureId),
        error: clearError ? null : (error ?? this.error),
      );
}

final takeViewerStoreProvider =
    NotifierProvider<TakeViewerStore, TakeViewerState>(TakeViewerStore.new);

/// Visor «Ver toma» y hoja «Ajustar desfase». El reloj y el audio son del núcleo; el vídeo (canal `take`)
/// lo mueve el núcleo con ese reloj. Aquí solo se refleja el estado y se envían intenciones.
class TakeViewerStore extends Notifier<TakeViewerState> {
  late final CoreClient _core = ref.read(coreClientProvider);
  FrameChannel? _channel;
  int _generation = 0;
  /// Hay (o puede haber) una toma abierta en el núcleo que cerrar al soltar el store.
  bool _live = false;

  @override
  TakeViewerState build() {
    final subs = <StreamSubscription<Object?>>[
      // Un evento mal formado se registra y se ignora: no mata el stream.
      _core.on('takeview.position', TakeViewPositionEvent.fromJson).listen(_onPosition, onError: _badEvent('takeview.position')),
      _core.on('takeview.video', TakeViewVideoEvent.fromJson).listen(_onVideo, onError: _badEvent('takeview.video')),
    ];
    ref.onDispose(() {
      for (final s in subs) {
        s.cancel();
      }
      _channel?.dispose();
      _channel = null;
      if (_live) {
        unawaited(_core.call('takeview.close', const <String, Object?>{}, (_) {}).catchError((Object _) {}));
      }
    });
    return const TakeViewerState();
  }

  static const _empty = <String, Object?>{};

  void Function(Object, StackTrace) _badEvent(String name) =>
      (Object e, StackTrace st) => debugPrint('Evento $name ignorado (mal formado): $e');

  /// Fallo de decodificación (no `CoreError`) como error del núcleo `internal`.
  CoreError _asCoreError(Object e) => e is CoreError ? e : CoreError('internal', '$e');

  /// `takeview.open`: cierra lo anterior y abre la toma.
  Future<void> open(String projectId, String takeId) => _open(
        () => _core.call('takeview.open', TakeViewOpenParams(projectId: projectId, takeId: takeId).toJson(),
            TakeViewSnapshot.fromJson),
        isOffset: false,
      );

  /// `takeview.openOffset`: toma de la hoja de desfase de Grabar (solo audio de la toma, sin backing).
  Future<void> openOffset() => _open(
        () => _core.call('takeview.openOffset', _empty, TakeViewSnapshot.fromJson),
        isOffset: true,
      );

  Future<void> _open(Future<TakeViewSnapshot> Function() call, {required bool isOffset}) async {
    final gen = ++_generation;
    _releaseChannel();
    _live = true;
    state = TakeViewerState(phase: TakeViewerPhase.loading, isOffset: isOffset);
    try {
      final s = await call();
      if (gen != _generation) return;
      state = state.copyWith(phase: TakeViewerPhase.open);
      _applySnapshot(s);
      final hasVideo = s.videoWidth != null && s.videoHeight != null;
      state = state.copyWith(video: hasVideo ? TakeVideoState.ready : TakeVideoState.none);
      if (hasVideo) _attachChannel();
    } catch (e) {
      if (gen != _generation) return;
      _live = false;
      state = TakeViewerState(isOffset: isOffset, error: _asCoreError(e));
    }
  }

  /// `takeview.close`: para, suelta el canal de vídeo y deja el visor en `closed`.
  Future<void> close() async {
    if (state.phase == TakeViewerPhase.closed && _channel == null) return;
    _generation++;
    _live = false;
    _releaseChannel();
    state = const TakeViewerState();
    try {
      await _core.call('takeview.close', _empty, (_) {});
    } on CoreError catch (e) {
      state = state.copyWith(error: e);
    }
  }

  Future<void> play() => _transport('takeview.play', _empty);
  Future<void> pause() => _transport('takeview.pause', _empty);
  Future<void> togglePlay() => state.playing ? pause() : play();

  /// Salta a [seconds] (el núcleo recorta a `0...duration`).
  Future<void> seek(double seconds) => _transport('takeview.seek', TakeViewSeekParams(seconds: seconds).toJson());

  /// Enciende o apaga el backing. Sin stems, o en la hoja de desfase, no hace nada.
  Future<void> setBacking(bool on) async {
    if (!state.canToggleBacking) return;
    await _transport('takeview.setBacking', TakeViewBackingParams(on: on).toJson());
  }

  Future<void> _transport(String method, Object params) async {
    if (!state.isOpen) return;
    final gen = _generation;
    try {
      final s = await _core.call(method, params, TakeViewSnapshot.fromJson);
      if (gen != _generation || !state.isOpen) return;
      state = state.copyWith(clearError: true);
      _applySnapshot(s);
    } catch (err) {
      final e = _asCoreError(err);
      if (gen != _generation) return;
      state = state.copyWith(error: e);
      if (e.code == 'not-open') state = state.copyWith(phase: TakeViewerPhase.closed, playing: false);
    }
  }

  void _applySnapshot(TakeViewSnapshot s) {
    state = state.copyWith(
      projectId: s.projectId,
      takeId: s.takeId,
      duration: s.duration,
      songStart: s.songStart,
      hasBacking: s.hasBacking,
      backingOn: s.backingOn,
      playing: s.playing,
      position: s.position,
      epoch: s.epoch,
      outputName: s.outputName,
      audioError: s.audioError,
      clearAudioError: s.audioError == null,
      videoWidth: s.videoWidth,
      videoHeight: s.videoHeight,
      videoRotation: s.videoRotation ?? 0,
    );
  }

  void _onPosition(TakeViewPositionEvent e) {
    if (!state.isOpen || e.epoch < state.epoch) return;
    state = state.copyWith(position: e.seconds, playing: e.playing, rate: e.rate, at: e.at, epoch: e.epoch);
  }

  void _onVideo(TakeViewVideoEvent e) {
    if (!state.isOpen || e.takeId != state.takeId) return;
    final v = e.video;
    if (v == null) {
      state = state.copyWith(video: TakeVideoState.ready, clearVideoStatus: true);
      unawaited(_refreshVideo());
    } else if (v.code == 'video-failed') {
      state = state.copyWith(
          video: TakeVideoState.error, videoMessage: v.message, clearVideoStatus: false, clearTexture: true);
      _releaseChannel();
    } else {
      state = state.copyWith(
          video: TakeVideoState.converting, videoProgress: v.progress, videoMessage: v.message);
    }
  }

  /// Vídeo listo tras convertir: pide el tamaño y la rotación y crea el canal.
  Future<void> _refreshVideo() async {
    final gen = _generation;
    try {
      final s = await _core.call('takeview.snapshot', _empty, TakeViewSnapshot.fromJson);
      if (gen != _generation || !state.isOpen) return;
      state = state.copyWith(
          videoWidth: s.videoWidth, videoHeight: s.videoHeight, videoRotation: s.videoRotation ?? 0);
      _attachChannel();
    } catch (e) {
      if (gen == _generation) state = state.copyWith(error: _asCoreError(e));
    }
  }

  void _attachChannel() {
    final ch = ref.read(frameChannelProvider(FrameChannelId.take));
    if (ch == null) return;
    final id = ch.create();
    _channel = ch;
    state = id >= 0 ? state.copyWith(textureId: id) : state.copyWith(clearTexture: true);
  }

  void _releaseChannel() {
    _channel?.dispose();
    _channel = null;
  }
}
