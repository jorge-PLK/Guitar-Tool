import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/study.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/shell/selected_project.dart';

part 'study_store_sections.dart';

enum StudyLoadStatus { idle, opening, open, error }

const Json _empty = <String, Object?>{};

/// Reflejo inmutable del estudio abierto. Los DTO del núcleo se pasan tal cual; aquí no hay lógica musical.
/// La posición a ~20 Hz vive aparte (`studyPositionProvider`).
final class StudyStoreState {
  const StudyStoreState({
    this.status = StudyLoadStatus.idle,
    this.study,
    this.error,
    this.editMode = false,
    this.analysisEvent,
    this.guitarsEvent,
  });

  final StudyLoadStatus status;

  /// Último estado completo (open + snapshot + ediciones + `study.state`).
  final StudyOpenResult? study;

  /// Error del núcleo de la apertura (status `error`) o de la última llamada. `not-open` no se guarda.
  final CoreError? error;

  /// Modo edición de acordes: estado efímero de interfaz.
  final bool editMode;
  final StudyAnalysisEvent? analysisEvent;
  final StudyGuitarsEvent? guitarsEvent;

  /// No nulo mientras el estudio está abierto (lo usa el store de Tab).
  String? get openProjectId => status == StudyLoadStatus.open ? study?.projectId : null;
  StudyTransport? get transport => study?.transport;

  StudyStoreState copyWith({
    StudyOpenResult? study,
    CoreError? error,
    bool clearError = false,
    bool? editMode,
    StudyAnalysisEvent? analysisEvent,
    StudyGuitarsEvent? guitarsEvent,
  }) =>
      StudyStoreState(
        status: status,
        study: study ?? this.study,
        error: clearError ? null : (error ?? this.error),
        editMode: editMode ?? this.editMode,
        analysisEvent: analysisEvent ?? this.analysisEvent,
        guitarsEvent: guitarsEvent ?? this.guitarsEvent,
      );
}

StudyOpenResult _withTransport(StudyOpenResult o, StudyTransport t) => _rebuild(o, transport: t);

StudyOpenResult _withEdit(StudyOpenResult o, StudyEditState e) => _rebuild(
      o,
      transport: e.transport,
      analysis: e.analysis,
      chordOverrides: e.chordOverrides,
      sections: e.sections,
      unappliedSections: e.unappliedSections,
      loops: e.loops,
      guitars: e.guitars,
    );

StudyOpenResult _rebuild(
  StudyOpenResult o, {
  StudyTransport? transport,
  StudyAnalysisInfo? analysis,
  List<StudyOverrideInfo>? chordOverrides,
  List<StudySectionInfo>? sections,
  bool? unappliedSections,
  List<StudySavedLoop>? loops,
  StudyGuitarsInfo? guitars,
}) =>
    StudyOpenResult(
      projectId: o.projectId,
      title: o.title,
      artist: o.artist,
      duration: o.duration,
      sampleRate: o.sampleRate,
      loadError: o.loadError,
      audio: o.audio,
      transport: transport ?? o.transport,
      emptyStems: o.emptyStems,
      usesSeparatedGuitars: o.usesSeparatedGuitars,
      analysis: analysis ?? o.analysis,
      chordOverrides: chordOverrides ?? o.chordOverrides,
      sections: sections ?? o.sections,
      unappliedSections: unappliedSections ?? o.unappliedSections,
      loops: loops ?? o.loops,
      guitars: guitars ?? o.guitars,
    );

final studyStoreProvider = NotifierProvider<StudyStore, StudyStoreState>(StudyStore.new);

class StudyStore extends Notifier<StudyStoreState> {
  late CoreClient _core;
  String? _wanted; // proyecto elegido
  String? _applied; // último proyecto que se intentó abrir
  String? _openId; // abierto de verdad en el núcleo
  bool _syncing = false;
  bool _disposed = false;
  bool _refreshing = false;
  bool _refreshAgain = false;
  final _gain = _GainQueue();

  @override
  StudyStoreState build() {
    _core = ref.watch(coreClientProvider);
    _disposed = false;
    _applied = null;
    _openId = null;
    _wanted = ref.read(selectedProjectProvider);
    ref.listen<String?>(selectedProjectProvider, (_, next) {
      _wanted = next;
      _sync();
    });
    final subs = <StreamSubscription<Object?>>[
      _core.on('study.state', StudyTransport.fromJson).listen(_onTransport),
      _core.on('study.analysis', StudyAnalysisEvent.fromJson).listen(_onAnalysis),
      _core.on('study.guitars', StudyGuitarsEvent.fromJson).listen(_onGuitars),
    ];
    ref.onDispose(() {
      _disposed = true;
      for (final s in subs) {
        s.cancel();
      }
      if (_openId != null) unawaited(_closeCore());
    });
    if (_wanted != null) Future.microtask(_sync);
    return const StudyStoreState();
  }

  // Apertura y cierre

  /// Reabre el proyecto elegido tras un error de apertura.
  Future<void> retryOpen() {
    if (state.status != StudyLoadStatus.error) return Future.value();
    _applied = null;
    return _sync();
  }

  Future<void> _closeCore() async {
    _openId = null;
    try {
      await _core.call('study.close', _empty, (j) => j);
    } catch (_) {
      // Los errores de study.close solo se registran (ficha §5).
    }
  }

  Future<void> _sync() async {
    if (_syncing) return;
    _syncing = true;
    try {
      while (!_disposed && _applied != _wanted) {
        final target = _wanted;
        _applied = target;
        if (_openId != null) await _closeCore();
        if (_disposed) return;
        if (target == null) {
          state = const StudyStoreState();
          continue;
        }
        state = const StudyStoreState(status: StudyLoadStatus.opening);
        try {
          final r = await _core.call(
              'study.open', StudyOpenParams(projectId: target).toJson(), StudyOpenResult.fromJson);
          _openId = r.projectId;
          if (_disposed) return;
          if (_applied == target) state = StudyStoreState(status: StudyLoadStatus.open, study: r);
        } on CoreError catch (e) {
          if (!_disposed && _applied == target) state = StudyStoreState(status: StudyLoadStatus.error, error: e);
        } catch (e) {
          if (!_disposed && _applied == target) {
            state = StudyStoreState(status: StudyLoadStatus.error, error: CoreError('internal', '$e'));
          }
        }
      }
    } finally {
      _syncing = false;
    }
  }

  // Eventos

  bool get _isOpen => !_disposed && state.status == StudyLoadStatus.open;

  void _onTransport(StudyTransport t) {
    if (!_isOpen) return;
    state = state.copyWith(study: _withTransport(state.study!, _overlayGain(t)));
    if (state.study!.guitars.process == StudyGuitarProcess.processing) refresh();
  }

  void _onAnalysis(StudyAnalysisEvent e) {
    if (!_isOpen) return;
    final a = e.analysis;
    if (a != null) {
      // Acordes recalculados por el núcleo (transpose/capo/key): sin snapshot.
      state = state.copyWith(analysisEvent: e, study: _rebuild(state.study!, analysis: a));
      return;
    }
    state = state.copyWith(analysisEvent: e);
    if (e.state == StudyAnalysisState.ready) refresh();
  }

  void _onGuitars(StudyGuitarsEvent e) {
    if (!_isOpen) return;
    state = state.copyWith(guitarsEvent: e);
    refresh();
  }

  /// `study.snapshot`: relee el estado completo sin reabrir. Una sola llamada en vuelo.
  Future<void> refresh() async {
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    try {
      do {
        _refreshAgain = false;
        final id = _openId;
        final r = await _call('study.snapshot', _empty, StudyOpenResult.fromJson);
        if (r != null && _isOpen && _openId == id) state = state.copyWith(study: r, clearError: true);
      } while (_refreshAgain);
    } finally {
      _refreshing = false;
    }
  }

  // Llamadas

  Future<R?> _call<R>(String method, Object? params, R Function(Json) decode) async {
    if (!_isOpen) return null;
    final id = _openId;
    try {
      final r = await _core.call(method, params, decode);
      return _isOpen && _openId == id ? r : null;
    } on CoreError catch (e) {
      _fail(e);
    } catch (e) {
      _fail(CoreError('internal', '$e'));
    }
    return null;
  }

  void _fail(CoreError e) {
    if (_disposed || e.code == 'not-open') return;
    state = state.copyWith(error: e);
  }

  Future<void> _transportCall(String method, Object? params) async {
    final t = await _call(method, params, StudyTransport.fromJson);
    if (t != null) state = state.copyWith(study: _withTransport(state.study!, _overlayGain(t)), clearError: true);
  }

  Future<StudyEditState?> _edit(String method, Object? params) async {
    final e = await _call(method, params, StudyEditState.fromJson);
    if (e != null) state = state.copyWith(study: _withEdit(state.study!, e), clearError: true);
    return e;
  }

  void setEditMode(bool on) => state = state.copyWith(editMode: on);

  void clearError() => state = state.copyWith(clearError: true);
}
