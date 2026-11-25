import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/host_folders.dart';
import 'package:toneforge/contract/jobs.dart';
import 'package:toneforge/contract/library.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/shell/selected_project.dart';

import 'library_logic.dart';
import 'library_prefs.dart';

part 'library_actions.dart';

const Object _keep = Object();

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
    this.proposedFolder,
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

  /// Carpeta que propone el núcleo en el primer arranque (`app.info.proposedProjectsFolder`); null si no llega.
  final String? proposedFolder;

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
    Object? proposedFolder = _keep,
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
    proposedFolder: identical(proposedFolder, _keep) ? this.proposedFolder : proposedFolder as String?,
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
      _core.on<Json>('library.changed', (j) => j).listen((_) {
        unawaited(_loadInfo(onlyFolder: true));
        unawaited(refresh());
      }),
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

  /// [onlyFolder]: tras `library.changed` solo se refresca la carpeta (puede haber cambiado por `library.relocate`).
  Future<void> _loadInfo({bool onlyFolder = false}) async {
    try {
      final info = await _core.call<Json>('app.info', const <String, Object?>{}, (j) => j);
      if (!ref.mounted) return;
      state = onlyFolder
          ? state.copyWith(projectsFolder: info['projectsFolder'] as String?)
          : state.copyWith(
              projectsFolder: info['projectsFolder'] as String?,
              proposedFolder: indicatorText(info['proposedProjectsFolder']),
            );
    } on CoreError {
      // la carpeta la decide library.list
    }
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

  /// Foto `data:` del artista; caché por nombre plegado (también guarda los `null`).
  Future<String?> artistPhoto(String name) {
    final key = foldText(name.trim());
    if (key.isEmpty) return Future.value(null);
    if (_photos.containsKey(key)) return Future.value(_photos[key]);
    return _photoPending[key] ??= _fetchPhoto(name.trim(), key);
  }

  /// Estado actual para las acciones de `library_actions.dart` (`state` es protegido
  /// fuera de la clase y el provider no puede leerse a sí mismo).
  LibraryState get _current => state;

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
