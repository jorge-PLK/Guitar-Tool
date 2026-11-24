part of 'library_store.dart';

/// Contenido que enseña el diálogo de eliminar tema.
class TrashContent {
  const TrashContent({required this.stems, required this.takes, required this.videos});

  final int stems;
  final int takes;
  final int videos;
}

/// Acciones sobre un tema. Devuelven el error del núcleo, o null si fue bien.
extension LibraryStoreActions on LibraryStore {
  Future<CoreError?> _run(Future<Object?> Function() action) async {
    try {
      await action();
      return null;
    } on CoreError catch (e) {
      return e;
    }
  }

  Future<CoreError?> reveal(String id) => _run(
    () => _core.call('library.reveal', ProjectIDParams(id: id).toJson(), RevealResult.fromJson),
  );

  /// `artist` vacío o en blanco se envía ausente. Si falla no cambia nada.
  Future<CoreError?> rename(String id, String title, String? artist) async {
    final a = artist?.trim();
    final params = RenameParams(id: id, title: title, artist: (a == null || a.isEmpty) ? null : a);
    final err = await _run(() => _core.call('library.rename', params.toJson(), RenameResult.fromJson));
    if (err == null) await refresh();
    return err;
  }

  Future<CoreError?> separate(String id) => _run(
    () => _core.call('library.separate', ProjectIDParams(id: id).toJson(), QueuedResult.fromJson),
  );

  /// `jobs.cancel` con el id del tema.
  Future<CoreError?> cancelSeparation(String id) => _run(
    () => _core.call('jobs.cancel', JobCancelParams(id: id).toJson(), CancelResult.fromJson),
  );

  /// Bytes que liberaría «Limpiar…» (de un tema, o de toda la biblioteca sin [id]).
  Future<int> cleanupInfo({String? id}) async {
    final r = await _core.call(
      'library.cleanupInfo',
      OptionalIDParams(id: id).toJson(),
      CleanupInfoResult.fromJson,
    );
    return r.bytes;
  }

  Future<CleanupResult> cleanup({String? id}) => _core.call(
    'library.cleanup',
    OptionalIDParams(id: id).toJson(),
    CleanupResult.fromJson,
  );

  /// Contenido del diálogo de eliminar: stems y tomas de la lista, vídeos de `library.project`.
  Future<TrashContent> trashContent(String id) async {
    final e = _current.entries.where((p) => p.id == id).firstOrNull;
    var videos = 0;
    var stems = e?.stemCount ?? 0;
    var takes = e?.takeCount ?? 0;
    try {
      final d = await _core.call(
        'library.project',
        ProjectIDParams(id: id).toJson(),
        ProjectDetailResult.fromJson,
      );
      videos = d.videoCount;
      if (e == null) {
        stems = d.summary.stemCount;
        takes = d.summary.takeCount;
      }
    } on CoreError {
      // el recuento de vídeos sale con 0 mientras no llegue (desvío 4)
    }
    return TrashContent(stems: stems, takes: takes, videos: videos);
  }

  /// Mover a la Papelera.
  Future<CoreError?> trash(String id) => _remove('library.trash', id);

  /// Eliminar del disco.
  Future<CoreError?> delete(String id) => _remove('library.delete', id);

  Future<CoreError?> _remove(String method, String id) async {
    final err = await _run(
      () => _core.call(method, ProjectIDParams(id: id).toJson(), RemovedResult.fromJson),
    );
    if (err == null) {
      clearSelectionIf(id);
      await refresh();
    }
    return err;
  }
}
