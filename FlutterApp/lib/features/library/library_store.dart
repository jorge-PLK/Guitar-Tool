import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/jobs.dart';
import 'package:toneforge/contract/library.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/shell/selected_project.dart';

import 'library_logic.dart';
import 'library_prefs.dart';

const Object _keep = Object();

/// Contenido que enseña el diálogo de eliminar tema.
class TrashContent {
  const TrashContent({required this.stems, required this.takes, required this.videos});

  final int stems;
  final int takes;
  final int videos;
}

/// Estado de la lista de Biblioteca. Inmutable.
class LibraryState {
  const LibraryState({
    this.entries = const [],
    this.skipped = const [],
    this.loaded = false,
    this.needsFolder = false,
    this.query = '',
    this.grouping = LibraryGrouping.songs,
    this.openArtist,
    this.projectsFolder,
    this.playlistIndicator,
    this.error,
  });

  final List<ProjectSummary> entries;
  final List<SkippedInfo> skipped;

  /// `false` hasta el primer `library.list`: no se muestra «vacía» antes.
  final bool loaded;

  /// `library.list` falló con `no-projects-folder`.
  final bool needsFolder;

  /// Texto del buscador tal cual se escribe (no se persiste).
  final String query;
  final LibraryGrouping grouping;

  /// Nombre del artista abierto en la vista Artistas (vacío = «Sin artista»); no se persiste.
  final String? openArtist;
  final String? projectsFolder;

  /// Texto del indicador de lista; `null` si no hay texto.
  final String? playlistIndicator;

  /// Último error de `library.list` distinto de `no-projects-folder`.
  final CoreError? error;

  /// Vista Temas: filtradas y ordenadas por título plegado.
  List<ProjectSummary> get songs => sortByTitle(filterEntries(entries, query));

  /// Vista Artistas: filtradas y agrupadas.
  List<ArtistGroup> get groups => groupByArtist(filterEntries(entries, query));

  /// Temas del artista abierto (tabla sin columna de artista); vacío si no hay artista abierto.
  List<ProjectSummary> get openArtistTracks {
    final open = openArtist;
    if (open == null) return const [];
    final key = foldText(open);
    return [
      for (final g in groups)
        if (foldText(g.name) == key) ...g.tracks,
    ];
  }

  /// Búsqueda activa sin resultados (entradas sí hay).
  bool get noMatches => query.trim().isNotEmpty && entries.isNotEmpty && songs.isEmpty;

  LibraryState copyWith({
    List<ProjectSummary>? entries,
    List<SkippedInfo>? skipped,
    bool? loaded,
    bool? needsFolder,
    String? query,
    LibraryGrouping? grouping,
    Object? openArtist = _keep,
    Object? projectsFolder = _keep,
    Object? playlistIndicator = _keep,
    Object? error = _keep,
  }) => LibraryState(
    entries: entries ?? this.entries,
    skipped: skipped ?? this.skipped,
    loaded: loaded ?? this.loaded,
    needsFolder: needsFolder ?? this.needsFolder,
    query: query ?? this.query,
    grouping: grouping ?? this.grouping,
    openArtist: identical(openArtist, _keep) ? this.openArtist : openArtist as String?,
    projectsFolder: identical(projectsFolder, _keep) ? this.projectsFolder : projectsFolder as String?,
    playlistIndicator: identical(playlistIndicator, _keep)
        ? this.playlistIndicator
        : playlistIndicator as String?,
    error: identical(error, _keep) ? this.error : error as CoreError?,
  );
}

/// Texto del indicador: `null` si falta o está en blanco.
String? indicatorText(Object? raw) {
  if (raw is! String) return null;
  return raw.trim().isEmpty ? null : raw;
}

final libraryStoreProvider = NotifierProvider<LibraryStore, LibraryState>(LibraryStore.new);

class LibraryStore extends Notifier<LibraryState> {
  final _photos = <String, String?>{};
  final _photoPending = <String, Future<String?>>{};
  bool _refreshing = false;
  bool _again = false;
  bool _groupingTouched = false;

  CoreClient get _core => ref.read(coreClientProvider);

  @override
  LibraryState build() {
    final subs = [
      _core.on<Json>('library.changed', (j) => j).listen((_) => refresh()),
      _core
          .on<Json>('playlist.changed', (j) => j)
          .listen((j) => _setIndicator(indicatorText(j['indicator']))),
    ];
    ref.onDispose(() {
      for (final s in subs) {
        s.cancel();
      }
    });
    Future.microtask(_start);
    return const LibraryState();
  }

  Future<void> _start() async {
    await Future.wait([_loadGrouping(), _loadInfo(), refresh()]);
  }

  Future<void> _loadGrouping() async {
    try {
      final raw = await ref.read(libraryPrefsProvider).get(libraryGroupingKey);
      if (!ref.mounted || _groupingTouched) return;
      state = state.copyWith(grouping: LibraryGrouping.fromRaw(raw));
    } catch (_) {
      // sin preferencia legible: se queda Temas
    }
  }

  Future<void> _loadInfo() async {
    try {
      final info = await _core.call<Json>('app.info', const <String, Object?>{}, (j) => j);
      if (!ref.mounted) return;
      final playlist = info['playlist'];
      state = state.copyWith(
        projectsFolder: info['projectsFolder'] as String?,
        playlistIndicator: playlist is Map ? indicatorText(playlist['indicator']) : null,
      );
    } on CoreError {
      // la carpeta la decide library.list
    }
  }

  void _setIndicator(String? text) {
    if (ref.mounted) state = state.copyWith(playlistIndicator: text);
  }

  /// Vuelve a pedir `library.list`. Las peticiones solapadas se funden en una repetición.
  Future<void> refresh() async {
    if (_refreshing) {
      _again = true;
      return;
    }
    _refreshing = true;
    try {
      do {
        _again = false;
        await _loadList();
      } while (_again && ref.mounted);
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _loadList() async {
    try {
      final r = await _core.call('library.list', const <String, Object?>{}, LibraryListResult.fromJson);
      if (!ref.mounted) return;
      _apply(r);
    } on CoreError catch (e) {
      if (!ref.mounted) return;
      state = e.code == 'no-projects-folder'
          ? state.copyWith(loaded: true, needsFolder: true, entries: const [], skipped: const [], error: null)
          : state.copyWith(error: e);
    }
  }

  void _apply(LibraryListResult r) {
    final open = state.openArtist;
    final stillThere = open != null &&
        r.projects.any((p) => foldText((p.artist ?? '').trim()) == foldText(open.trim()));
    state = state.copyWith(
      entries: r.projects,
      skipped: r.skipped,
      loaded: true,
      needsFolder: false,
      error: null,
      openArtist: stillThere ? open : null,
    );
    syncSelection({for (final p in r.projects) p.id});
  }

  /// Limpia la selección compartida si su id ya no está en la lista.
  void syncSelection(Set<String> ids) {
    final sel = ref.read(selectedProjectProvider);
    if (sel != null && !ids.contains(sel)) {
      ref.read(selectedProjectProvider.notifier).select(null);
    }
  }

  /// Limpia la selección compartida si es [id].
  void clearSelectionIf(String id) {
    if (ref.read(selectedProjectProvider) == id) {
      ref.read(selectedProjectProvider.notifier).select(null);
    }
  }

  // --- Búsqueda y vista ---

  void setQuery(String query) => state = state.copyWith(query: query);

  Future<void> setGrouping(LibraryGrouping grouping) async {
    _groupingTouched = true;
    state = state.copyWith(grouping: grouping, openArtist: null);
    try {
      await ref.read(libraryPrefsProvider).set(libraryGroupingKey, grouping.raw);
    } catch (_) {
      // no poder guardar la vista no es un error de usuario
    }
  }

  void openArtistGroup(String name) => state = state.copyWith(openArtist: name);

  void closeArtist() => state = state.copyWith(openArtist: null);

  // --- Acciones sobre un tema. Devuelven el error del núcleo, o null si fue bien. ---

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
    final e = state.entries.where((p) => p.id == id).firstOrNull;
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

  /// Foto `data:` del artista; caché por nombre plegado (también guarda los `null`).
  Future<String?> artistPhoto(String name) {
    final key = foldText(name.trim());
    if (key.isEmpty) return Future.value(null);
    if (_photos.containsKey(key)) return Future.value(_photos[key]);
    return _photoPending[key] ??= _fetchPhoto(name.trim(), key);
  }

  Future<String?> _fetchPhoto(String name, String key) async {
    try {
      final r = await _core.call(
        'library.artistPhoto',
        ArtistPhotoParams(name: name).toJson(),
        ArtistPhotoResult.fromJson,
      );
      _photos[key] = r.photo;
      return r.photo;
    } on CoreError {
      return null; // un fallo no se recuerda: se reintenta la próxima vez
    } finally {
      unawaited(_photoPending.remove(key));
    }
  }
}
