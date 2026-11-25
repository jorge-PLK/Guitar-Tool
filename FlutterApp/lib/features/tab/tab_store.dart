import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/tab.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/features/backing/study_store.dart';

/// Id del proyecto con estudio abierto, o `null`. Tablatura se abre y se cierra con él.
final tabStudyProjectProvider = Provider<String?>(
  (ref) => ref.watch(studyStoreProvider.select((s) => s.openProjectId)),
);

/// Duración del aviso efímero del pie (estado «Aviso efímero» de la ficha).
const Duration tabFlashDuration = Duration(seconds: 3);

const Object _keep = Object();

/// Estado inmutable de Tablatura: refleja `tab.state` y los eventos del área.
final class TabStoreState {
  const TabStoreState({
    this.projectId,
    this.opening = false,
    this.tab,
    this.progress = const {},
    this.selection,
    this.range,
    this.score,
    this.flash,
    this.error,
    this.exportName,
    this.exporting = false,
    this.dismissedNotices = const [],
  });

  /// Proyecto con tablatura abierta (o abriéndose).
  final String? projectId;
  final bool opening;

  /// Último `tab.state` (o respuesta de una llamada). `null` hasta que `tab.open` responde.
  final TabState? tab;

  /// Último `tab.progress` por id de pista. `done` y `cancelled` lo quitan; `failed` se queda con su error.
  final Map<String, TabProgressEvent> progress;

  /// `tab.selection` (null = `bar:-1`, sin selección) y `tab.range` (null = sin tramo).
  final TabSelectionEvent? selection;
  final TabRangeEvent? range;

  /// Última partitura pedida con `tab.score`.
  final TabScoreResult? score;

  /// Aviso efímero del pie; se borra solo a los 3 s.
  final String? flash;

  /// Último error de una llamada `tab.*` (traducir por `code`, caer a `message`).
  final CoreError? error;
  final String? exportName;
  final bool exporting;

  /// Avisos que el usuario cerró con la X (el núcleo no tiene método para ello).
  final List<String> dismissedNotices;

  /// Avisos del núcleo aún no cerrados.
  List<String> get notices => [
        for (final n in tab?.notices ?? const <String>[])
          if (!dismissedNotices.contains(n)) n,
      ];

  TabStoreState copyWith({
    Object? projectId = _keep,
    bool? opening,
    Object? tab = _keep,
    Map<String, TabProgressEvent>? progress,
    Object? selection = _keep,
    Object? range = _keep,
    Object? score = _keep,
    Object? flash = _keep,
    Object? error = _keep,
    Object? exportName = _keep,
    bool? exporting,
    List<String>? dismissedNotices,
  }) =>
      TabStoreState(
        projectId: identical(projectId, _keep) ? this.projectId : projectId as String?,
        opening: opening ?? this.opening,
        tab: identical(tab, _keep) ? this.tab : tab as TabState?,
        progress: progress ?? this.progress,
        selection: identical(selection, _keep) ? this.selection : selection as TabSelectionEvent?,
        range: identical(range, _keep) ? this.range : range as TabRangeEvent?,
        score: identical(score, _keep) ? this.score : score as TabScoreResult?,
        flash: identical(flash, _keep) ? this.flash : flash as String?,
        error: identical(error, _keep) ? this.error : error as CoreError?,
        exportName: identical(exportName, _keep) ? this.exportName : exportName as String?,
        exporting: exporting ?? this.exporting,
        dismissedNotices: dismissedNotices ?? this.dismissedNotices,
      );
}

final tabStoreProvider = NotifierProvider<TabStore, TabStoreState>(TabStore.new);

const Map<String, Object?> _empty = <String, Object?>{};

class TabStore extends Notifier<TabStoreState> {
  Timer? _flashTimer;
  String? _target;
  int _gen = 0;

  CoreClient get _core => ref.read(coreClientProvider);

  @override
  TabStoreState build() {
    final core = ref.watch(coreClientProvider);
    final subs = <StreamSubscription<Object?>>[
      core.on('tab.state', TabState.fromJson).listen(_onState, onError: _ignore),
      core.on('tab.progress', TabProgressEvent.fromJson).listen(_onProgress, onError: _ignore),
      core.on('tab.selection', TabSelectionEvent.fromJson).listen(_onSelection, onError: _ignore),
      core.on('tab.range', TabRangeEvent.fromJson).listen(_onRange, onError: _ignore),
    ];
    ref.onDispose(() {
      for (final s in subs) {
        s.cancel();
      }
      _flashTimer?.cancel();
    });
    ref.listen<String?>(tabStudyProjectProvider, (_, next) => _sync(next));
    Future.microtask(() {
      if (ref.mounted) _sync(ref.read(tabStudyProjectProvider));
    });
    return const TabStoreState();
  }

  static void _ignore(Object _) {}

  // ---- Apertura según el estudio ----

  Future<void> _sync(String? id) async {
    if (id == _target) return;
    final previous = _target;
    _target = id;
    final gen = ++_gen;
    if (previous != null) {
      _flashTimer?.cancel();
      state = const TabStoreState();
      await _run(() => _core.call('tab.close', _empty, (_) {}));
      if (gen != _gen || !ref.mounted) return;
      state = state.copyWith(error: null);
    }
    if (id != null) await _open(id, gen);
  }

  Future<void> _open(String id, int gen) async {
    state = state.copyWith(projectId: id, opening: true, error: null);
    final t = await _run(
        () => _core.call('tab.open', TabOpenParams(projectId: id).toJson(), TabState.fromJson));
    if (gen != _gen || !ref.mounted) return;
    state = state.copyWith(opening: false);
    if (t != null) _apply(t);
  }

  /// `tab.open` otra vez (al llegar el análisis con la fase `waitingAnalysis`).
  Future<void> reopen() async {
    final id = _target;
    if (id != null) await _open(id, _gen);
  }

  // ---- Eventos ----

  void _onState(TabState t) => _apply(t);

  void _onProgress(TabProgressEvent e) {
    final next = {...state.progress};
    switch (e.state) {
      case TabProgressState.done || TabProgressState.cancelled:
        next.remove(e.track);
      default:
        next[e.track] = e;
    }
    state = state.copyWith(progress: next);
  }

  void _onSelection(TabSelectionEvent e) {
    if (state.projectId == null) return;
    state = state.copyWith(selection: e.bar < 0 ? null : e);
  }

  void _onRange(TabRangeEvent e) {
    if (state.projectId == null) return;
    state = state.copyWith(range: e.startBar < 0 && e.endBar < 0 ? null : e);
  }

  void _apply(TabState t) {
    if (!ref.mounted || state.projectId == null || t.projectId != state.projectId) return;
    state = state.copyWith(tab: t);
    final f = t.flash;
    if (f != null && f.isNotEmpty) showFlash(f);
  }

  /// Aviso efímero de 3 s (el de `tab.state.flash` y los de la interfaz, p. ej. fallo al exportar).
  void showFlash(String text) {
    _flashTimer?.cancel();
    state = state.copyWith(flash: text);
    _flashTimer = Timer(tabFlashDuration, () {
      if (ref.mounted) state = state.copyWith(flash: null);
    });
  }

  /// Cierra el cuadro de avisos (la X). Solo oculta; el núcleo no ofrece método.
  void dismissNotices() {
    final n = state.tab?.notices ?? const <String>[];
    state = state.copyWith(dismissedNotices: [...state.dismissedNotices, ...n]);
  }

  void clearError() => state = state.copyWith(error: null);

  // ---- Intenciones (`tab.*`) ----

  Future<T?> _run<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on CoreError catch (e) {
      if (ref.mounted) state = state.copyWith(error: e);
      return null;
    }
  }

  /// Llama [method] y aplica el `TabState` devuelto. `null` si falló (el error queda en el estado).
  Future<TabState?> _call(String method, [Object? params = _empty]) async {
    final t = await _run(() => _core.call(method, params, TabState.fromJson));
    if (t != null) _apply(t);
    return t;
  }

  /// `tab.close`: guarda lo editado y deja la pantalla sin tablatura.
  Future<void> close() async {
    _target = null;
    _gen++;
    _flashTimer?.cancel();
    state = const TabStoreState();
    await _run(() => _core.call('tab.close', _empty, (_) {}));
  }

  Future<TabState?> refresh() => _call('tab.state');

  Future<TabState?> setSource(TabSource source) =>
      _call('tab.setSource', TabSourceParams(source: source).toJson());

  /// `tab.score`; guarda la partitura en el estado y la devuelve.
  Future<TabScoreResult?> score({String? track}) async {
    final r = await _run(() =>
        _core.call('tab.score', TabTrackParams(track: track).toJson(), TabScoreResult.fromJson));
    if (r != null && ref.mounted) state = state.copyWith(score: r);
    return r;
  }

  Future<TabState?> selectTrack(String track) =>
      _call('tab.selectTrack', TabTrackParams(track: track).toJson());

  Future<TabQueuedResult?> transcribe({String? track}) => _run(() => _core.call(
      'tab.transcribe', TabTrackParams(track: track).toJson(), TabQueuedResult.fromJson));

  Future<bool> cancel() async =>
      (await _run(() => _core.call('tab.cancel', _empty, TabCancelResult.fromJson)))?.cancelled ??
      false;

  Future<TabState?> beatClick(TabClickParams p) => _call('tab.beatClick', p.toJson());
  Future<TabState?> beatDrag(TabClickParams p) => _call('tab.beatDrag', p.toJson());
  Future<TabState?> noteClick(TabClickParams p) => _call('tab.noteClick', p.toJson());
  Future<TabState?> select(TabSelectParams p) => _call('tab.select', p.toJson());

  Future<TabState?> span(TabSpanAction action) =>
      _call('tab.span', TabSpanParams(action: action).toJson());

  Future<TabState?> toggleMute(String track) =>
      _call('tab.toggleMute', TabTrackParams(track: track).toJson());

  Future<TabState?> toggleSolo(String track) =>
      _call('tab.toggleSolo', TabTrackParams(track: track).toJson());

  Future<TabState?> setListening(String track, {required bool on}) =>
      _call('tab.setListening', TabListeningParams(track: track, on: on).toJson());

  Future<TabState?> setAllListening({required bool on}) =>
      _call('tab.setAllListening', TabListeningParams(on: on).toJson());

  /// `tab.edit {op,...}`; con `op:"key"` el `handled` de la respuesta dice si el núcleo usó la tecla.
  Future<TabState?> edit(TabEditParams p) => _call('tab.edit', p.toJson());

  /// `tab.edit {op:key}`: `true` si el núcleo usó la tecla (`TabState.handled`). Falla = `false`.
  Future<bool> key(String key, {bool shift = false, bool ctrl = false, bool alt = false}) async {
    final t = await edit(TabEditParams.key(key: key, shift: shift, ctrl: ctrl, alt: alt));
    return t?.handled ?? false;
  }

  /// `tab.edit {op:redo}` directo (Ctrl+Y en Windows).
  Future<TabState?> redo() => edit(TabEditParams.redo());

  Future<TabState?> setEditMode({required bool on}) => edit(TabEditParams.editMode(on: on));

  /// `tab.exportName`: nombre sugerido del `.gp`; queda en el estado.
  Future<String?> loadExportName() async {
    final r = await _run(() => _core.call('tab.exportName', _empty, TabExportNameResult.fromJson));
    if (r != null && ref.mounted) state = state.copyWith(exportName: r.fileName);
    return r?.fileName;
  }

  /// `tab.export` con la ruta ya elegida en el diálogo de la interfaz y el `.gp` en base64.
  Future<TabExportResult?> export({required String data, required String path}) async {
    state = state.copyWith(exporting: true, error: null);
    final r = await _run(() => _core.call(
        'tab.export', TabExportParams(data: data, path: path).toJson(), TabExportResult.fromJson));
    if (ref.mounted) state = state.copyWith(exporting: false);
    return r;
  }

  /// Estado de `tab.songsterr.accept` / `automatic`, que devuelven `TabState`.
  void adopt(TabState t) => _apply(t);
}
