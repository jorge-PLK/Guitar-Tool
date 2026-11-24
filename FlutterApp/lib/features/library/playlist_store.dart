import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/playlist.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';

import 'library_store.dart' show indicatorText;
import 'playlist_logic.dart';

export 'playlist_logic.dart';

const Object _keep = Object();

/// Resultado de `close`: el error (null = llamada bien) y la respuesta `{closed, live}`.
typedef PlaylistCloseOutcome = ({CoreError? error, PlaylistCloseResult? result});

/// Estado de la sesión de lista o álbum. Inmutable; la verdad es el snapshot del núcleo.
class PlaylistState {
  const PlaylistState({this.snapshot, this.busy = false, this.error, this.sheetOpen = false});

  final PlaylistSnapshot? snapshot;

  /// Hay una llamada al núcleo en curso.
  final bool busy;

  /// Error de la última acción (`in-library`, `not-found`, `no-playlist`…).
  final CoreError? error;

  /// La hoja de lista está visible (el indicador de la cabecera la reabre).
  final bool sheetOpen;

  bool get hasPlaylist => snapshot != null;

  PlaylistStep? get step => snapshot?.step;

  /// Hay trabajo en marcha o parado: cerrar la hoja no cierra la lista.
  bool get isLive => snapshot?.isLive ?? false;

  /// Texto del indicador de cabecera tal como llega; null si falta o está en blanco.
  String? get indicator => indicatorText(snapshot?.indicator);

  TracksCounts? get tracks => snapshot == null ? null : tracksCounts(snapshot!);
  ReviewCounts? get review => snapshot == null ? null : reviewCounts(snapshot!);
  SearchProgress? get search => snapshot == null ? null : searchProgress(snapshot!);
  QueueCounts? get queue => snapshot == null ? null : queueCounts(snapshot!);
  SummaryCounts? get summary => snapshot == null ? null : summaryCounts(snapshot!);

  /// Botones del paso actual (todo oculto sin lista).
  PlaylistButtons get buttons => snapshot == null ? const PlaylistButtons() : buttonsFor(snapshot!);

  List<PlaylistItemInfo> get reviewRows => snapshot == null ? const [] : reviewItems(snapshot!);
  List<PlaylistItemInfo> get queueRows => snapshot == null ? const [] : queueItems(snapshot!);
  List<PlaylistItemInfo> get failedRows => snapshot == null ? const [] : failedItems(snapshot!);

  PlaylistState copyWith({
    Object? snapshot = _keep,
    bool? busy,
    Object? error = _keep,
    bool? sheetOpen,
  }) => PlaylistState(
    snapshot: identical(snapshot, _keep) ? this.snapshot : snapshot as PlaylistSnapshot?,
    busy: busy ?? this.busy,
    error: identical(error, _keep) ? this.error : error as CoreError?,
    sheetOpen: sheetOpen ?? this.sheetOpen,
  );
}

/// No es autoDispose: la lista vive aunque se cierre la hoja.
final playlistStoreProvider = NotifierProvider<PlaylistStore, PlaylistState>(PlaylistStore.new);

class PlaylistStore extends Notifier<PlaylistState> {
  int _inflight = 0;
  bool _fresh = false; // ya llegó un snapshot por evento o `adopt`: `app.info` no lo pisa

  CoreClient get _core => ref.read(coreClientProvider);

  @override
  PlaylistState build() {
    final sub = _core
        .on('playlist.changed', PlaylistSnapshot.fromJson)
        .listen(_setSnapshot);
    ref.onDispose(sub.cancel);
    Future.microtask(_loadInfo);
    return const PlaylistState();
  }

  Future<void> _loadInfo() async {
    try {
      final info = await _core.call<Json>('app.info', const <String, Object?>{}, (j) => j);
      if (!ref.mounted || _fresh) return;
      final p = info['playlist'];
      if (p is Map) {
        state = state.copyWith(snapshot: PlaylistSnapshot.fromJson(p.cast<String, Object?>()));
      }
    } on CoreError {
      // sin información: se queda sin lista
    }
  }

  void _setSnapshot(PlaylistSnapshot s) {
    if (!ref.mounted) return;
    _fresh = true;
    state = state.copyWith(snapshot: s);
  }

  /// La lista que trae `link.resolve`: pone el snapshot y abre la hoja.
  void adopt(PlaylistSnapshot s) {
    _fresh = true;
    state = state.copyWith(snapshot: s, error: null, sheetOpen: true);
  }

  void openSheet() => state = state.copyWith(sheetOpen: true);

  void closeSheet() => state = state.copyWith(sheetOpen: false);

  // --- Acciones del puente ---

  Future<CoreError?> select(String id, bool selected) =>
      _act('playlist.select', PlaylistSelectParams(id: id, selected: selected).toJson());

  Future<CoreError?> selectAll() => _act('playlist.selectAll');

  Future<CoreError?> selectNone() => _act('playlist.selectNone');

  /// `in-library` si el candidato ya está en la biblioteca; `not-found` si no es de ese tema.
  Future<CoreError?> choose(String id, String candidateId) =>
      _act('playlist.choose', PlaylistChooseParams(id: id, candidateId: candidateId).toJson());

  Future<CoreError?> skip(String id) => _act('playlist.skip', PlaylistItemParams(id: id).toJson());

  /// `playlist.continue` (paso Elegir temas → Buscar o Cola).
  Future<CoreError?> continue_() => _act('playlist.continue');

  Future<CoreError?> search() => _act('playlist.search');

  Future<CoreError?> start() => _act('playlist.start');

  Future<CoreError?> cancel() => _act('playlist.cancel');

  Future<CoreError?> resume() => _act('playlist.resume');

  Future<CoreError?> updateAndRetry() => _act('playlist.updateAndRetry');

  Future<CoreError?> retryFailed() => _act('playlist.retryFailed');

  /// Con trabajo vivo y sin [force] el núcleo no cierra y devuelve `live: true`: la hoja pregunta
  /// y vuelve a llamar con `force: true` (cancela la cola). Sin sesión (`closed:false, live:false`)
  /// también se limpia lo local.
  Future<PlaylistCloseOutcome> close({bool force = false}) async {
    _begin();
    try {
      final r = await _core.call(
        'playlist.close',
        PlaylistCloseParams(force: force).toJson(),
        PlaylistCloseResult.fromJson,
      );
      if (!ref.mounted) return (error: null, result: r);
      if (r.closed || !r.live) {
        state = state.copyWith(snapshot: null, sheetOpen: false, error: null);
      }
      return (error: null, result: r);
    } on CoreError catch (e) {
      if (ref.mounted) state = state.copyWith(error: e);
      return (error: e, result: null);
    } finally {
      _end();
    }
  }

  Future<CoreError?> _act(String method, [Object? params]) async {
    _begin();
    try {
      final s = await _core.call(method, params ?? const <String, Object?>{}, PlaylistSnapshot.fromJson);
      if (!ref.mounted) return null;
      _fresh = true;
      state = state.copyWith(snapshot: s, error: null);
      return null;
    } on CoreError catch (e) {
      if (!ref.mounted) return e;
      // Sin lista en el núcleo: la local ya no vale.
      state = e.code == 'no-playlist'
          ? state.copyWith(snapshot: null, sheetOpen: false, error: e)
          : state.copyWith(error: e);
      return e;
    } finally {
      _end();
    }
  }

  void _begin() {
    _inflight++;
    state = state.copyWith(busy: true);
  }

  void _end() {
    _inflight--;
    if (ref.mounted && _inflight == 0) state = state.copyWith(busy: false);
  }
}
