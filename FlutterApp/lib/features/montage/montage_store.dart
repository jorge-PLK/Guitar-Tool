import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/library.dart';
import 'package:toneforge/contract/montage.dart';
import 'package:toneforge/contract/montage_params.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/features/library/library_store.dart';

import 'montage_models.dart';

export 'montage_models.dart';

part 'montage_actions.dart';

/// Un envío de `montage.seek` cada 120 ms como máximo (WS:11 `SCRUB_INTERVAL_MS`).
const Duration kSeekInterval = Duration(milliseconds: 120);

const MontagePositionEvent _zeroPosition = MontagePositionEvent(seconds: 0, videoSeconds: 0, playing: false);

final montageStoreProvider = NotifierProvider<MontageStore, MontageState>(MontageStore.new);

/// Posición (30 Hz) aparte del snapshot (MO6): solo el cursor, el slider y el tiempo la observan.
final montagePositionProvider = NotifierProvider<MontagePositionNotifier, MontagePositionEvent>(
  MontagePositionNotifier.new,
);

/// Temas con tomas (de `libraryStoreProvider`, en el orden de `entries` como `model.entries` de MV:28) para el selector sin tema elegido.
final montageSongsProvider = Provider<List<ProjectSummary>>((ref) {
  final entries = ref.watch(libraryStoreProvider.select((s) => s.entries));
  return [for (final p in entries) if (p.takeCount > 0) p];
});

class MontagePositionNotifier extends Notifier<MontagePositionEvent> {
  @override
  MontagePositionEvent build() => _zeroPosition;

  void set(MontagePositionEvent e) => state = e;
  void reset() => state = _zeroPosition;
}

class MontageStore extends Notifier<MontageState> {
  CoreClient get _core => ref.read(coreClientProvider);

  int _openToken = 0;
  Timer? _seekTimer;
  double? _pendingSeek;

  @override
  MontageState build() {
    final subs = <StreamSubscription<Object?>>[
      _core.on('montage.state', MontageSnapshot.fromJson).listen(_onState, onError: _badEvent('montage.state')),
      _core.on('montage.position', MontagePositionEvent.fromJson).listen((e) {
        if (state.projectId != null) ref.read(montagePositionProvider.notifier).set(e);
      }, onError: _badEvent('montage.position')),
      _core.on('montage.export', MontageExportEvent.fromJson).listen((e) {
        if (state.snapshot != null) state = state.copyWith(exportLive: e);
      }, onError: _badEvent('montage.export')),
      _core.on('montage.framing', MontageFramingEvent.fromJson).listen((e) {
        if (state.snapshot != null) state = state.copyWith(framingLive: {...state.framingLive, e.takeId: e});
      }, onError: _badEvent('montage.framing')),
    ];
    ref.onDispose(() {
      _seekTimer?.cancel();
      for (final s in subs) {
        s.cancel();
      }
    });
    return const MontageState();
  }

  void Function(Object, StackTrace) _badEvent(String name) =>
      (Object e, StackTrace st) => debugPrint('Evento $name ignorado (mal formado): $e');

  CoreError _asCoreError(Object e) => e is CoreError ? e : CoreError('internal', '$e');

  void _onState(MontageSnapshot s) {
    final id = state.projectId;
    if (id == null || s.projectId != id) return;
    applySnapshot(s);
  }

  /// Sustituye el snapshot (evento o respuesta). Descarta los eventos vivos de exportación y encuadre: el snapshot manda.
  void applySnapshot(MontageSnapshot s) {
    if (!ref.mounted) return;
    state = state.copyWith(snapshot: s, loading: false, loadError: null, exportLive: null, framingLive: const {});
    if (_seekTimer == null) {
      final t = s.transport;
      ref.read(montagePositionProvider.notifier).set(
            MontagePositionEvent(seconds: t.position, videoSeconds: t.videoPosition, playing: t.playing),
          );
    }
  }

  /// Entrar con tema: `montage.open`. Un resultado de una apertura anterior se descarta.
  Future<void> open(String projectId) async {
    final token = ++_openToken;
    _resetSeek();
    state = MontageState(projectId: projectId, loading: true, snapshot: state.projectId == projectId ? state.snapshot : null);
    try {
      final s = await _core.call('montage.open', MontageOpenParams(projectId: projectId).toJson(), MontageSnapshot.fromJson);
      if (!ref.mounted || token != _openToken) return;
      applySnapshot(s);
    } catch (e) {
      if (ref.mounted && token == _openToken) state = state.copyWith(loading: false, loadError: _asCoreError(e));
    }
  }

  /// Elegir tema en el selector (sin tema): abre ese tema.
  Future<void> selectSong(String projectId) => open(projectId);

  /// Reintenta la apertura tras un error de carga.
  Future<void> retry() async {
    final id = state.projectId;
    if (id != null) await open(id);
  }

  /// Salir de la pantalla: `montage.close` y estado vacío (la posición se reinicia).
  Future<void> close() async {
    _openToken++;
    _resetSeek();
    state = const MontageState();
    ref.read(montagePositionProvider.notifier).reset();
    try {
      await _core.call('montage.close', const MontageEmptyParams().toJson(), MontageEmptyParams.fromJson);
    } on CoreError {
      // `not-open`: ya estaba cerrada.
    }
  }

  void clearActionError() => state = state.copyWith(actionError: null);

  /// Ejecuta un método que devuelve `MontageSnapshot` y lo aplica. `not-open` se ignora; otro error queda en `actionError`.
  Future<bool> act(String method, Object? params) async {
    try {
      final s = await _core.call(method, params, MontageSnapshot.fromJson);
      if (!ref.mounted) return false;
      applySnapshot(s);
      state = state.copyWith(actionError: null);
      return true;
    } catch (e) {
      _fail(e);
      return false;
    }
  }

  void _fail(Object e) {
    if (!ref.mounted) return;
    final err = _asCoreError(e);
    state = state.copyWith(actionError: err.code == 'not-open' ? null : err);
  }

  void _resetSeek() {
    _seekTimer?.cancel();
    _seekTimer = null;
    _pendingSeek = null;
  }

  /// Arrastre del slider o del cursor: acota a `span`, mueve la posición al instante y envía `montage.seek` como mucho
  /// cada 120 ms (el primero sale al momento). Cierra el gesto con [seekEnd].
  void seek(double seconds) {
    final span = state.span;
    if (span == null) return;
    final v = clampToSpan(seconds, span);
    final pos = ref.read(montagePositionProvider);
    ref.read(montagePositionProvider.notifier).set(
          MontagePositionEvent(seconds: v, videoSeconds: pos.videoSeconds, playing: pos.playing),
        );
    if (_seekTimer == null) {
      _sendSeek(v);
      _seekTimer = Timer(kSeekInterval, _seekTick);
    } else {
      _pendingSeek = v;
    }
  }

  void _seekTick() {
    _seekTimer = null;
    final v = _pendingSeek;
    if (v == null) return;
    _pendingSeek = null;
    _sendSeek(v);
    _seekTimer = Timer(kSeekInterval, _seekTick);
  }

  /// Fin del gesto: envía de inmediato el último valor pendiente (si lo hay).
  void seekEnd() {
    _seekTimer?.cancel();
    _seekTimer = null;
    final v = _pendingSeek;
    _pendingSeek = null;
    if (v != null) _sendSeek(v);
  }

  /// La respuesta (snapshot) no se aplica: no debe reconstruir la pantalla en cada paso del arrastre.
  void _sendSeek(double v) {
    unawaited(
      _core.call('montage.seek', MontageSeekParams(seconds: v).toJson(), MontageSnapshot.fromJson).then<void>((_) {}, onError: _fail),
    );
  }

  /// Devuelve el `cutId` del corte nuevo (para abrir su menú) o `null` si falló.
  Future<String?> addCut(double time, {String? partId, bool? exact}) async {
    try {
      final r = await _core.call(
        'montage.addCut',
        MontageAddCutParams(time: time, partId: partId, exact: exact).toJson(),
        MontageAddCutResult.fromJson,
      );
      if (!ref.mounted) return null;
      applySnapshot(r.snapshot);
      state = state.copyWith(actionError: null);
      return r.cutId;
    } catch (e) {
      _fail(e);
      return null;
    }
  }

  /// No arranca con un análisis en curso ni con otra exportación en marcha (`exportEnabled`).
  Future<bool> startExport() async =>
      state.exportEnabled ? act('montage.startExport', const MontageEmptyParams().toJson()) : false;

  /// Carpeta del tema abierto (`projectsFolder/folderName` de Biblioteca); nula si aún no se conoce.
  String? get themeFolder {
    final id = state.projectId;
    final lib = ref.read(libraryStoreProvider);
    final base = lib.projectsFolder;
    if (id == null || base == null) return null;
    for (final p in lib.entries) {
      if (p.id == id) return joinPath(base, p.folderName, windows: Platform.isWindows);
    }
    return null;
  }
}
