import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/library.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';

const Object _keep = Object();

/// Detalle de un tema (`library.project`). Inmutable.
class ProjectDetailState {
  const ProjectDetailState({this.detail, this.loaded = false, this.error, this.takeError});

  final ProjectDetailResult? detail;

  /// `true` tras la primera respuesta (con éxito o error).
  final bool loaded;

  /// Error de `library.project` (por ejemplo `not-found`).
  final CoreError? error;

  /// Fallo local de una toma (línea roja bajo la lista); se limpia al siguiente intento.
  final CoreError? takeError;

  /// Hay alguna toma en alguna parte.
  bool get hasTakes => detail?.parts.any((p) => p.takes.isNotEmpty) ?? false;

  ProjectDetailState copyWith({
    Object? detail = _keep,
    bool? loaded,
    Object? error = _keep,
    Object? takeError = _keep,
  }) => ProjectDetailState(
    detail: identical(detail, _keep) ? this.detail : detail as ProjectDetailResult?,
    loaded: loaded ?? this.loaded,
    error: identical(error, _keep) ? this.error : error as CoreError?,
    takeError: identical(takeError, _keep) ? this.takeError : takeError as CoreError?,
  );
}

/// Un store por id de tema.
final projectDetailStoreProvider =
    NotifierProvider.family<ProjectDetailStore, ProjectDetailState, String>(ProjectDetailStore.new);

class ProjectDetailStore extends Notifier<ProjectDetailState> {
  ProjectDetailStore(this.id);

  final String id;

  CoreClient get _core => ref.read(coreClientProvider);

  @override
  ProjectDetailState build() {
    final sub = _core.on<Json>('library.changed', (j) => j).listen((_) => reload());
    ref.onDispose(sub.cancel);
    Future.microtask(reload);
    return const ProjectDetailState();
  }

  Future<void> reload() async {
    try {
      final d = await _core.call(
        'library.project',
        ProjectIDParams(id: id).toJson(),
        ProjectDetailResult.fromJson,
      );
      if (!ref.mounted) return;
      state = state.copyWith(detail: d, loaded: true, error: null);
    } on CoreError catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(loaded: true, error: e);
    }
  }

  void clearTakeError() => state = state.copyWith(takeError: null);

  Future<bool> deleteTake(String takeId) => _takeAction(
    () => _core.call(
      'library.deleteTake',
      DeleteTakeParams(id: id, takeId: takeId).toJson(),
      RemovedResult.fromJson,
    ),
  );

  Future<bool> markBest(String takeId) => _takeAction(
    () => _core.call(
      'library.markBest',
      MarkBestParams(id: id, takeId: takeId).toJson(),
      MarkedResult.fromJson,
    ),
  );

  /// Ejecuta la acción y recarga el detalle; en error deja `takeError` y no recarga.
  Future<bool> _takeAction(Future<Object?> Function() action) async {
    state = state.copyWith(takeError: null);
    try {
      await action();
    } on CoreError catch (e) {
      if (ref.mounted) state = state.copyWith(takeError: e);
      return false;
    }
    await reload();
    return true;
  }
}
