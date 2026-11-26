import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/audio.dart';
import 'package:toneforge/contract/core_message.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/shell/shell_providers.dart';
import 'package:toneforge/shell/shell_route.dart';

/// Estado de Ajustes · Audio: refleja lo que publica el núcleo. Los textos del núcleo (`label`, `hint`,
/// `calibrateBlock`...) se guardan tal cual; componer texto es cosa de la pantalla (desvío N1/AJ4).
class AudioStoreState {
  const AudioStoreState({
    this.settings,
    this.devices,
    this.audioState,
    this.levels,
    this.calibration,
    this.calibrating = false,
    this.loading = false,
    this.error,
  });

  final AudioSettings? settings;
  final AudioDevices? devices;
  final AudioState? audioState;

  /// Último `audio.levels`; `null` fuera de la pestaña; `levels` vacío = sin sesión.
  final AudioLevels? levels;

  /// Único estado de calibración: lo alimentan los eventos `audio.calibration` y las respuestas.
  final AudioCalibrationState? calibration;

  /// `audio.calibrate` en vuelo (la llamada no vuelve hasta acabar).
  final bool calibrating;
  final bool loading;

  /// Último error RPC (`code`, `message`, `args`); la pantalla lo traduce por `code`.
  final CoreError? error;

  bool get calibrationRunning =>
      calibration?.phase == CalibrationPhase.running || (audioState?.calibrationRunning ?? false);

  /// Motivo por el que «Empezar» está deshabilitado (el estado vivo manda sobre el de `audio.settings`).
  String? get calibrateBlock => audioState?.calibrateBlock ?? settings?.calibrateBlock;

  /// Mismo motivo con código (`CoreMessage`), con la misma precedencia que `calibrateBlock`.
  CoreMessage? get calibrateBlockMessage =>
      audioState?.calibrateBlockMessage ?? settings?.calibrateBlockMessage;

  AudioStoreState copyWith({
    AudioSettings? settings,
    AudioDevices? devices,
    AudioState? audioState,
    AudioLevels? levels,
    bool clearLevels = false,
    AudioCalibrationState? calibration,
    bool? calibrating,
    bool? loading,
    CoreError? error,
    bool clearError = false,
  }) =>
      AudioStoreState(
        settings: settings ?? this.settings,
        devices: devices ?? this.devices,
        audioState: audioState ?? this.audioState,
        levels: clearLevels ? null : (levels ?? this.levels),
        calibration: calibration ?? this.calibration,
        calibrating: calibrating ?? this.calibrating,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}

final audioStoreProvider =
    NotifierProvider<AudioStore, AudioStoreState>(AudioStore.new);

class AudioStore extends Notifier<AudioStoreState> {
  late CoreClient _core;
  bool _active = false; // pestaña Audio de Ajustes visible
  bool _metersOn = false;
  int _calSeq = 0; // sube con cada evento `audio.calibration` o cambio de calibración

  @override
  AudioStoreState build() {
    final core = _core = ref.read(coreClientProvider);
    final subs = <StreamSubscription<Object?>>[
      core.on('audio.state', AudioState.fromJson).listen(_onAudioState, onError: _ignore),
      core.on('audio.devicesChanged', AudioDevices.fromJson).listen(_onDevices, onError: _ignore),
      core.on('audio.levels', AudioLevels.fromJson).listen(
          (l) => _set(state.copyWith(levels: l)), onError: _ignore),
      core.on('audio.calibration', AudioCalibrationState.fromJson).listen(
          _onCalibration, onError: _ignore),
    ];
    ref.listen(shellRouteProvider, (_, _) => _sync());
    ref.listen(settingsTabProvider, (_, _) => _sync());
    ref.onDispose(() {
      for (final s in subs) {
        s.cancel();
      }
      if (_metersOn) {
        _metersOn = false;
        core
            .call('audio.setMeters', const AudioSetMetersParams(visible: false).toJson(),
                AudioState.fromJson)
            .then((_) {}, onError: _ignore);
      }
    });
    Future.microtask(_sync);
    return const AudioStoreState();
  }

  static void _ignore(Object _) {}

  void _set(AudioStoreState s) {
    if (ref.mounted) state = s;
  }

  bool _visible() =>
      ref.read(shellRouteProvider) == ShellRoute.settings &&
      ref.read(settingsTabProvider) == SettingsTab.audio;

  /// Entra o sale de la pestaña: carga y medidores al entrar; medidores apagados al salir.
  Future<void> _sync() async {
    if (!ref.mounted) return;
    final v = _visible();
    if (v == _active) return;
    _active = v;
    if (v) {
      await reload();
      if (ref.mounted && _active) await _setMeters(true);
    } else {
      _set(state.copyWith(clearLevels: true));
      await _setMeters(false);
    }
  }

  Future<void> _setMeters(bool visible) async {
    if (_metersOn == visible) return;
    _metersOn = visible;
    final s = await _guard(() => _core.call(
        'audio.setMeters', AudioSetMetersParams(visible: visible).toJson(), AudioState.fromJson));
    if (s != null) _set(state.copyWith(audioState: s));
    // Si la pestaña cambió mientras volaba la llamada, se corrige.
    if (ref.mounted && _metersOn != _active) await _setMeters(_active);
  }

  /// `audio.settings`, `audio.devices` y `audio.state`.
  Future<void> reload() async {
    _set(state.copyWith(loading: true, clearError: true));
    final r = await Future.wait<Object?>([
      _guard(() => _core.call('audio.settings', const {}, AudioSettings.fromJson)),
      _guard(() => _core.call('audio.devices', const {}, AudioDevices.fromJson)),
      _guard(() => _core.call('audio.state', const {}, AudioState.fromJson)),
    ]);
    _set(state.copyWith(
      loading: false,
      settings: r[0] as AudioSettings?,
      devices: r[1] as AudioDevices?,
      audioState: r[2] as AudioState?,
    ));
  }

  /// Ejecuta una llamada; un error del núcleo queda en [AudioStoreState.error] y devuelve `null`.
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

  void clearError() => _set(state.copyWith(clearError: true));

  void _onAudioState(AudioState s) {
    _set(state.copyWith(audioState: s));
    if (_active) unawaited(_reloadSettings());
  }

  void _onDevices(AudioDevices d) {
    _set(state.copyWith(devices: d));
    if (_active) unawaited(_reloadSettings());
  }

  Future<void> _reloadSettings() async {
    final s = await _guard(() => _core.call('audio.settings', const {}, AudioSettings.fromJson));
    if (s != null) _set(state.copyWith(settings: s));
  }

  void _onCalibration(AudioCalibrationState c) {
    _calSeq++;
    _set(state.copyWith(calibration: c));
  }

  // --- selectores (cada uno envía solo lo que cambia) ---

  /// `null` = «Salida del sistema».
  Future<void> setOutput(String? uid) => _setSettings(AudioSetSettingsParams(
      outputDeviceUID: uid == null ? const Patch.nullValue() : Patch.of(uid)));

  /// `null` = «Ninguna».
  Future<void> setInput(String? uid) => _setSettings(AudioSetSettingsParams(
      inputDeviceUID: uid == null ? const Patch.nullValue() : Patch.of(uid)));

  /// `null` = «Sin asignar».
  Future<void> setGuitarIn(List<int>? channels) => _setSettings(AudioSetSettingsParams(
      guitarIn: channels == null ? const Patch.nullValue() : Patch.of(channels)));

  Future<void> setBackingOut(int left, int right) =>
      _setSettings(AudioSetSettingsParams(backingOut: AudioBacking(left: left, right: right)));

  Future<void> setWorkingSampleRate(int rate) =>
      _setSettings(AudioSetSettingsParams(workingSampleRate: rate));

  /// «Usar … como frecuencia de trabajo»: solo si `rateMismatch.canUseDeviceRate`.
  Future<void> useDeviceRate() {
    final m = state.settings?.rateMismatch;
    if (m == null || !m.canUseDeviceRate) return Future.value();
    return setWorkingSampleRate(m.deviceRate.round());
  }

  Future<void> _setSettings(AudioSetSettingsParams p) async {
    _set(state.copyWith(clearError: true));
    final s = await _guard(
        () => _core.call('audio.setSettings', p.toJson(), AudioSettings.fromJson));
    if (s != null) _set(state.copyWith(settings: s));
  }

  // --- calibración ---

  /// «Empezar». La respuesta llega al terminar; el estado ya lo fueron dejando los eventos, así que
  /// solo se aplica si no llegó ninguno (no se duplica ni se pisa uno más reciente).
  Future<void> calibrate() async {
    if (state.calibrating) return;
    final seq = _calSeq;
    _set(state.copyWith(calibrating: true, clearError: true));
    final r = await _guard(
        () => _core.call('audio.calibrate', const {}, AudioCalibrationState.fromJson));
    if (!ref.mounted) return;
    final apply = r != null && _calSeq == seq;
    if (apply) _calSeq++;
    _set(state.copyWith(calibrating: false, calibration: apply ? r : null));
  }

  /// «Repetir» y «Cerrar» tras un resultado: `audio.dismissCalibration`.
  Future<void> dismissCalibration() => _calCall('audio.dismissCalibration');

  /// Solo si la hoja se destruye con la medida en marcha: `audio.cancelCalibration`.
  Future<void> cancelCalibration() => _calCall('audio.cancelCalibration');

  /// Cierre de la hoja al destruirse: como [closeCalibration] pero solo si el notifier sigue vivo.
  Future<void> closeCalibrationIfMounted() async {
    if (ref.mounted) await closeCalibration();
  }

  /// Cierre de la hoja: cancela si mide, si no descarta el resultado.
  Future<void> closeCalibration() =>
      state.calibrationRunning ? cancelCalibration() : dismissCalibration();

  Future<void> _calCall(String method) async {
    final r = await _guard(() => _core.call(method, const {}, AudioCalibrationState.fromJson));
    if (r != null) {
      _calSeq++;
      _set(state.copyWith(calibration: r));
    }
  }
}
