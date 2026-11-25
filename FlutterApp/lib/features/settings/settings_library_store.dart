import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/host_folders.dart';
import 'package:toneforge/contract/library_storage.dart';
import 'package:toneforge/contract/settings.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';

const Object _keep = Object();

/// Estado de la pestaña Biblioteca de Ajustes (carpeta y espacio usado). Inmutable.
///
/// Sin textos: números, enums y códigos. La limpieza de toda la biblioteca vive en
/// `libraryStoreProvider` (`cleanupInfo()` / `cleanup()` sin id).
class SettingsLibraryState {
  const SettingsLibraryState({
    this.projectsFolder,
    this.usage,
    this.loaded = false,
    this.relocating = false,
    this.relocateMode,
    this.relocateFraction = 0,
    this.error,
  });

  /// Carpeta de proyectos (null → «—»).
  final String? projectsFolder;

  /// Espacio usado (null → «—» hasta tenerlo).
  final UsageResult? usage;
  final bool loaded;

  /// Hay un `library.relocate` en curso: «Cambiar carpeta» deshabilitado.
  final bool relocating;
  final RelocateMode? relocateMode;

  /// 0…1 de `library.relocateProgress`.
  final double relocateFraction;

  /// Último error (`work-in-progress` → aviso propio; resto → mensaje genérico).
  final CoreError? error;

  /// Barra y «Moviendo N %»: solo con «Mover»; «Solo apuntar» no emite progreso útil.
  bool get showRelocateProgress => relocating && relocateMode == RelocateMode.move;

  /// El núcleo rechazó el cambio por haber cola de trabajo o grabación.
  bool get workInProgress => error?.code == 'work-in-progress';

  SettingsLibraryState copyWith({
    Object? projectsFolder = _keep,
    Object? usage = _keep,
    bool? loaded,
    bool? relocating,
    Object? relocateMode = _keep,
    double? relocateFraction,
    Object? error = _keep,
  }) => SettingsLibraryState(
    projectsFolder: identical(projectsFolder, _keep) ? this.projectsFolder : projectsFolder as String?,
    usage: identical(usage, _keep) ? this.usage : usage as UsageResult?,
    loaded: loaded ?? this.loaded,
    relocating: relocating ?? this.relocating,
    relocateMode: identical(relocateMode, _keep) ? this.relocateMode : relocateMode as RelocateMode?,
    relocateFraction: relocateFraction ?? this.relocateFraction,
    error: identical(error, _keep) ? this.error : error as CoreError?,
  );
}

final settingsLibraryStoreProvider =
    NotifierProvider<SettingsLibraryStore, SettingsLibraryState>(SettingsLibraryStore.new);

class SettingsLibraryStore extends Notifier<SettingsLibraryState> {
  CoreClient get _core => ref.read(coreClientProvider);

  @override
  SettingsLibraryState build() {
    final subs = [
      _core.on<Json>('library.changed', (j) => j).listen((_) => unawaited(_loadUsage())),
      _core
          .on<RelocateProgress>('library.relocateProgress', RelocateProgress.fromJson)
          .listen(_onProgress),
      _core
          .on<RelocateResult>('library.relocated', RelocateResult.fromJson)
          .listen((_) => unawaited(refresh())),
    ];
    ref.onDispose(() {
      for (final s in subs) {
        s.cancel();
      }
    });
    Future.microtask(refresh);
    return const SettingsLibraryState();
  }

  /// Recarga carpeta (`settings.get`) y espacio (`library.usage`).
  Future<void> refresh() async {
    await Future.wait([_loadFolder(), _loadUsage()]);
    if (ref.mounted) state = state.copyWith(loaded: true);
  }

  Future<void> _loadFolder() async {
    try {
      final r = await _core.call('settings.get', const <String, Object?>{}, SettingsGetResult.fromJson);
      if (ref.mounted) state = state.copyWith(projectsFolder: r.projectsFolder);
    } on CoreError catch (e) {
      if (ref.mounted) state = state.copyWith(error: e);
    }
  }

  Future<void> _loadUsage() async {
    try {
      final r = await _core.call('library.usage', const <String, Object?>{}, UsageResult.fromJson);
      if (ref.mounted) state = state.copyWith(usage: r);
    } on CoreError catch (e) {
      if (ref.mounted) state = state.copyWith(error: e);
    }
  }

  void _onProgress(RelocateProgress p) {
    if (!ref.mounted || !state.relocating) return;
    state = state.copyWith(relocateFraction: p.fraction.clamp(0.0, 1.0));
  }

  /// Abre el selector de carpeta del anfitrión (`host.chooseFolder`, NO `pickProjectsFolder`).
  /// Devuelve la ruta, o null si se canceló (o falló: queda en `error`).
  Future<String?> chooseFolder() async {
    try {
      final r = await _core.call('host.chooseFolder', const <String, Object?>{}, ChosenFolderResult.fromJson);
      return r.path;
    } on CoreError catch (e) {
      if (ref.mounted) state = state.copyWith(error: e);
      return null;
    }
  }

  /// Aplica la carpeta elegida: [RelocateMode.move] mueve los temas, [RelocateMode.point] solo apunta.
  /// Devuelve null si fue bien. Tras acabar recarga carpeta y espacio.
  Future<CoreError?> relocate(String path, RelocateMode mode) async {
    if (state.relocating) return null;
    state = state.copyWith(relocating: true, relocateMode: mode, relocateFraction: 0, error: null);
    CoreError? failure;
    try {
      await _core.call(
        'library.relocate',
        RelocateParams(path: path, mode: mode).toJson(),
        RelocateResult.fromJson,
      );
    } on CoreError catch (e) {
      failure = e;
    }
    if (!ref.mounted) return failure;
    state = state.copyWith(relocating: false, relocateMode: null, error: failure);
    await refresh();
    return failure;
  }

  void dismissError() => state = state.copyWith(error: null);
}
