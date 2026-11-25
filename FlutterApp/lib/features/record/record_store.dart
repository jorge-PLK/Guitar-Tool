import 'dart:async';
import 'dart:ui' show Size;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/audio.dart';
import 'package:toneforge/contract/core_message.dart';
import 'package:toneforge/contract/record.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';

const Object _keep = Object();

/// Estado de Grabar: refleja `record.state` y `audio.state`. Inmutable; no compone textos.
class RecordState {
  const RecordState({
    this.snapshot,
    this.opened = false,
    this.position = 0,
    this.calibrationValid,
    this.guitarIn = const <int>[],
    this.error,
  });

  /// Canales de entrada de la guitarra (1-based) de `audio.settings`; vacío hasta conocerlos.
  final List<int> guitarIn;

  /// Último `RecordSnapshot` (respuesta de un método o evento `record.state`).
  final RecordSnapshot? snapshot;

  /// `true` tras `record.open` y hasta `record.close`.
  final bool opened;

  /// Segundos de `record.position` (30 Hz).
  final num position;

  /// `calibrationValid` de `audio.state` (G3); nulo = aún desconocido.
  final bool? calibrationValid;

  /// Último error de una acción (no `not-open`); se limpia con la siguiente acción correcta.
  final CoreError? error;

  RecordPhase get phase => snapshot?.phase ?? RecordPhase.idle;

  /// Tiempo de la cuenta atrás (`countBeat`) en `counting`.
  int? get countBeat => phase == RecordPhase.counting ? snapshot?.countBeat : null;

  /// «Ocupado» = fase distinta de reposo (RC:510).
  bool get isBusy => phase != RecordPhase.idle;

  /// Motivo de bloqueo tal como lo emite el núcleo (hoy texto en español, no código: ver informe).
  String? get blockReason => snapshot?.blockReason;

  /// Mismo motivo con código (`CoreMessage`), lectura directa del snapshot.
  CoreMessage? get block => snapshot?.block;

  /// El botón envía `record.start`: reposo y sin bloqueo.
  bool get canStartTake => snapshot != null && phase == RecordPhase.idle && blockReason == null;

  /// El botón envía `record.stop`: en cuenta atrás o grabando.
  bool get canStopTake => phase == RecordPhase.counting || phase == RecordPhase.recording;

  bool get canPressRecord => canStartTake || canStopTake;

  RecordPart? get activePart {
    final s = snapshot;
    if (s == null) return null;
    for (final p in s.parts) {
      if (p.id == s.activePartId) return p;
    }
    return null;
  }

  RecordTake? get selectedTake {
    final id = snapshot?.selectedTakeId;
    final part = activePart;
    if (id == null || part == null) return null;
    for (final t in part.takes) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// La casilla de punch se habilita solo si la parte activa tiene tomas (y en reposo).
  bool get canArmPunch => phase == RecordPhase.idle && (activePart?.takes.isNotEmpty ?? false);

  /// Punch listo: activado, con toma elegida y las dos marcas.
  bool get punchReady {
    final p = snapshot?.punch;
    return p != null &&
        p.enabled &&
        snapshot?.selectedTakeId != null &&
        p.inSeconds != null &&
        p.outSeconds != null;
  }

  /// Aviso «Sin calibrar» (RV:172): sin calibrar, sin otro bloqueo y en reposo.
  bool get showUncalibrated =>
      calibrationValid == false && blockReason == null && phase == RecordPhase.idle;

  /// Tamaño del fotograma de cámara (FC1) para `TfVideoSurface.frameSize`; nulo sin `width`/`height`.
  Size? get cameraFrameSize {
    final c = snapshot?.camera;
    if (c?.width == null || c?.height == null) return null;
    return Size(c!.width!.toDouble(), c.height!.toDouble());
  }

  /// Giro de la cámara (0/90/180/270) para `TfVideoSurface.rotation`.
  int get cameraRotation => snapshot?.camera.rotation ?? 0;

  RecordState copyWith({
    Object? snapshot = _keep,
    bool? opened,
    num? position,
    Object? calibrationValid = _keep,
    List<int>? guitarIn,
    Object? error = _keep,
  }) =>
      RecordState(
        snapshot: identical(snapshot, _keep) ? this.snapshot : snapshot as RecordSnapshot?,
        opened: opened ?? this.opened,
        position: position ?? this.position,
        guitarIn: guitarIn ?? this.guitarIn,
        calibrationValid: identical(calibrationValid, _keep) ? this.calibrationValid : calibrationValid as bool?,
        error: identical(error, _keep) ? this.error : error as CoreError?,
      );
}

final recordStoreProvider = NotifierProvider<RecordStore, RecordState>(RecordStore.new);

class RecordStore extends Notifier<RecordState> {
  CoreClient get _core => ref.read(coreClientProvider);

  @override
  RecordState build() {
    final subs = <StreamSubscription<Object?>>[
      _core.on('record.state', RecordSnapshot.fromJson).listen(applySnapshot),
      _core.on('record.position', RecordPositionEvent.fromJson).listen((e) {
        if (state.opened) state = state.copyWith(position: e.seconds);
      }),
      _core.on('audio.state', AudioState.fromJson).listen((a) {
        if (state.opened) state = state.copyWith(calibrationValid: a.calibrationValid);
      }),
    ];
    ref.onDispose(() {
      for (final s in subs) {
        s.cancel();
      }
    });
    return const RecordState();
  }

  /// Aplica un snapshot (evento o respuesta). Lo usa también `MixerStore`. Ignorado si Grabar no está abierta.
  void applySnapshot(RecordSnapshot s) {
    if (!state.opened || !ref.mounted) return;
    state = state.copyWith(snapshot: s);
  }

  /// Entrar (§5.1): `study.open`, `record.open` y, en paralelo, `audio.settings` y `audio.setMeters {visible:true}`.
  Future<void> open(String projectId) async {
    try {
      // TODO(ola2): StudyOpenParams
      await _core.call('study.open', {'projectId': projectId}, (j) => j);
    } on CoreError {
      // Se ignora el resultado: Grabar decide con `record.open`.
    }
    if (!ref.mounted) return;
    try {
      final s = await _core.call('record.open', RecordOpenParams(projectId: projectId).toJson(), RecordSnapshot.fromJson);
      if (!ref.mounted) return;
      state = RecordState(snapshot: s, opened: true, position: s.position, calibrationValid: state.calibrationValid, guitarIn: state.guitarIn);
    } on CoreError catch (e) {
      if (ref.mounted) state = state.copyWith(error: e);
      return;
    }
    Future<void> settings() async {
      try {
        final a = await _core.call('audio.settings', const <String, Object?>{}, AudioSettings.fromJson);
        if (ref.mounted && state.opened) state = state.copyWith(guitarIn: a.guitarIn);
      } on CoreError {
        // Sin `guitarIn` el nivel de «Tu guitarra» queda a cero.
      }
    }

    Future<void> meters() async {
      try {
        final a = await _core.call('audio.setMeters', const AudioSetMetersParams(visible: true).toJson(), AudioState.fromJson);
        if (ref.mounted) state = state.copyWith(calibrationValid: a.calibrationValid);
      } on CoreError {
        // Sin medidores no hay aviso de calibración; Grabar sigue funcionando.
      }
    }

    await Future.wait([settings(), meters()]);
  }

  /// Salir: `audio.setMeters {visible:false}`, `record.close` y `study.close` salvo rumbo a Montaje.
  Future<void> close({bool toMontage = false}) async {
    state = state.copyWith(opened: false);
    try {
      await _core.call('audio.setMeters', const AudioSetMetersParams(visible: false).toJson(), AudioState.fromJson);
    } on CoreError {
      // Se sale igualmente.
    }
    try {
      await _core.call('record.close', const RecordEmptyParams().toJson(), RecordEmptyParams.fromJson);
    } on CoreError {
      // `not-open`: ya estaba cerrada.
    }
    if (!toMontage) {
      try {
        // TODO(ola2): StudyOpenParams
        await _core.call('study.close', const <String, Object?>{}, (j) => j);
      } on CoreError {
        // Se sale igualmente.
      }
    }
    if (ref.mounted) state = const RecordState();
  }

  /// Ejecuta una acción que devuelve `RecordSnapshot`. `not-open` se ignora; otro error queda en `error`.
  Future<bool> act(String method, Object? params) async {
    try {
      final s = await _core.call(method, params, RecordSnapshot.fromJson);
      if (!ref.mounted) return false;
      state = state.copyWith(snapshot: s, error: null);
      return true;
    } on CoreError catch (e) {
      if (ref.mounted) state = state.copyWith(error: e.code == 'not-open' ? null : e);
      return false;
    }
  }

  /// `record.prepareViewTake` -> `{allowed}` (RV:253): `false` (o error) = no abrir la hoja «Ver toma».
  Future<bool> prepareViewTake() async {
    try {
      return (await _core.call('record.prepareViewTake', const RecordEmptyParams().toJson(), RecordAllowedResult.fromJson)).allowed;
    } on CoreError {
      return false;
    }
  }

  void clearError() => state = state.copyWith(error: null);

  Future<void> startTake() async {
    if (state.canStartTake) await act('record.start', const RecordEmptyParams().toJson());
  }

  Future<void> stopTake() async {
    if (state.canStopTake) await act('record.stop', const RecordEmptyParams().toJson());
  }

  /// El botón grande: `startTake` en reposo, `stopTake` en cuenta atrás o grabando.
  Future<void> toggleTake() => state.canStopTake ? stopTake() : startTake();

  Future<void> selectPart(String partId) => act('record.selectPart', RecordPartParams(partId: partId).toJson());

  Future<void> addPart(String name, {String? replaces}) =>
      act('record.addPart', RecordAddPartParams(name: name, replaces: replaces).toJson());

  /// `takeId` nulo deselecciona.
  Future<void> selectTake(String? takeId) => act('record.selectTake', RecordTakeParams(takeId: takeId).toJson());

  Future<void> markBest(String takeId) => act('record.markBest', RecordTakeParams(takeId: takeId).toJson());

  Future<void> deleteTake(String takeId) => act('record.deleteTake', RecordTakeParams(takeId: takeId).toJson());

  /// Solo en reposo (el núcleo lo gira +90 mod 360 y devuelve el nuevo `camera.rotation`).
  Future<void> rotateCamera() async {
    if (state.phase == RecordPhase.idle) await act('record.rotate', const RecordEmptyParams().toJson());
  }

  // Opciones: solo se envía lo que cambia respecto al último snapshot.

  Future<void> setCountIn(bool on) async {
    if (state.snapshot?.countIn == on) return;
    await act('record.setCountIn', RecordOnParams(on: on).toJson());
  }

  Future<void> setPreRoll(int bars) async {
    final b = bars.clamp(0, 2);
    if (state.snapshot?.preRollBars == b) return;
    await act('record.setPreRoll', RecordBarsParams(bars: b).toJson());
  }

  /// `sectionId` nulo = «Desde el principio» (parámetro ausente).
  Future<void> setStartSection(String? sectionId) async {
    if (state.snapshot?.startSectionId == sectionId) return;
    await act('record.setStartSection', RecordSectionParams(sectionId: sectionId).toJson());
  }

  // Punch (solo en reposo). G1: no se replica en Dart que activarlo elija la mejor toma.

  Future<void> setPunchEnabled(bool on) async {
    if (state.snapshot?.punch.enabled == on) return;
    if (on && !state.canArmPunch) return;
    await act('record.setPunch', RecordPunchParams(enabled: on).toJson());
  }

  /// Mueve la entrada o la salida (`free`: sin ajustar a secciones) o las borra.
  Future<void> setPunchPoints({num? entry, num? exit, bool clearIn = false, bool clearOut = false, bool? free}) async {
    if (state.phase != RecordPhase.idle) return;
    await act(
      'record.setPunch',
      RecordPunchParams(
        entry: entry,
        exit: exit,
        clearIn: clearIn ? true : null,
        clearOut: clearOut ? true : null,
        free: free,
      ).toJson(),
    );
  }

  /// «Punch-in» del menú de toma; tras la respuesta la fase pasa a cuenta atrás o grabando.
  Future<void> startPunch(String takeId) async {
    if (state.phase != RecordPhase.idle) return;
    await act('record.startPunch', RecordTakeParams(takeId: takeId).toJson());
  }
}
