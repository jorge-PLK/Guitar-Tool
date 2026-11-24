import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/tab.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/features/tab/tab_store.dart';

const Object _keep = Object();

/// Estado de la hoja de Songsterr: el último `SongsterrSheetState` del núcleo y el último error.
final class SongsterrStoreState {
  const SongsterrStoreState({this.sheet, this.error});

  /// `null` = nunca abierta o cerrada por este cliente. `open:false` = cerrada por el núcleo.
  final SongsterrSheetState? sheet;
  final CoreError? error;

  bool get isOpen => sheet?.open ?? false;

  /// Etapa de importación (`choosing`, `working`, `pairing`, `failed`); `choosing` si no hay hoja.
  TabSongsterrStage get stage => sheet?.stage ?? TabSongsterrStage.choosing;

  SongsterrStoreState copyWith({Object? sheet = _keep, Object? error = _keep}) => SongsterrStoreState(
        sheet: identical(sheet, _keep) ? this.sheet : sheet as SongsterrSheetState?,
        error: identical(error, _keep) ? this.error : error as CoreError?,
      );
}

final songsterrStoreProvider =
    NotifierProvider<SongsterrStore, SongsterrStoreState>(SongsterrStore.new);

const Map<String, Object?> _empty = <String, Object?>{};

class SongsterrStore extends Notifier<SongsterrStoreState> {
  /// Cuenta los eventos recibidos: una respuesta que llega después de un evento más nuevo no lo pisa
  /// (`use` responde `working` y el `pairing` llega por evento).
  int _events = 0;

  CoreClient get _core => ref.read(coreClientProvider);

  @override
  SongsterrStoreState build() {
    final sub = ref
        .watch(coreClientProvider)
        .on('tab.songsterr.state', SongsterrSheetState.fromJson)
        .listen((s) {
      _events++;
      state = state.copyWith(sheet: s);
    }, onError: (Object _) {});
    ref.onDispose(sub.cancel);
    return const SongsterrStoreState();
  }

  Future<T?> _run<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on CoreError catch (e) {
      if (ref.mounted) state = state.copyWith(error: e);
      return null;
    }
  }

  Future<SongsterrSheetState?> _call(String method, [Object? params = _empty]) async {
    final seen = _events;
    final s = await _run(
        () => _core.call('tab.songsterr.$method', params, SongsterrSheetState.fromJson));
    if (s != null && ref.mounted && seen == _events) {
      state = state.copyWith(sheet: s, error: null);
    }
    return s;
  }

  /// `accept` y `automatic` devuelven `TabState`: se pasa al store de Tablatura y la hoja se da por cerrada.
  Future<TabState?> _finish(String method) async {
    final t = await _run(
        () => _core.call('tab.songsterr.$method', _empty, TabState.fromJson));
    if (t == null || !ref.mounted) return t;
    ref.read(tabStoreProvider.notifier).adopt(t);
    state = const SongsterrStoreState();
    return t;
  }

  void clearError() => state = state.copyWith(error: null);

  Future<SongsterrSheetState?> open() => _call('open');
  Future<SongsterrSheetState?> refresh() => _call('state');
  Future<SongsterrSheetState?> close() => _call('close');
  Future<SongsterrSheetState?> search() => _call('search');
  Future<SongsterrSheetState?> retry() => _call('retry');

  Future<SongsterrSheetState?> select(int songId) =>
      _call('select', SongsterrSelectParams(songId: songId).toJson());

  Future<SongsterrSheetState?> link(String link) =>
      _call('link', SongsterrLinkParams(link: link).toJson());

  /// «Usar esta»: la respuesta es `working`; el emparejado (`pairing`) llega por evento.
  Future<SongsterrSheetState?> use() => _call('use');

  Future<SongsterrSheetState?> review() => _call('review');
  Future<SongsterrSheetState?> retryImport() => _call('retryImport');
  Future<SongsterrSheetState?> back() => _call('back');

  Future<SongsterrSheetState?> assign(SongsterrAssignParams p) => _call('assign', p.toJson());

  Future<SongsterrSheetState?> allAutomatic() => _call('allAutomatic');

  Future<TabState?> accept() => _finish('accept');
  Future<TabState?> automatic() => _finish('automatic');
}
