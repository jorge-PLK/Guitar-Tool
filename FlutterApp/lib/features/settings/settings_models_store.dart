import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/models.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';

const Object _keep = Object();

/// Estado de la sección Modelos de Ajustes. Inmutable.
///
/// «Verificando…» e «Instalando…» salen de `ModelEntry.state`; el avance de
/// `models.progress` ya está volcado en `fraction` de la entrada.
class SettingsModelsState {
  const SettingsModelsState({
    this.models = const [],
    this.modelsBytes = 0,
    this.loaded = false,
    this.failure,
    this.error,
  });

  final List<ModelEntry> models;
  final int modelsBytes;
  final bool loaded;

  /// Último `models.changed.error` (`model-failed`); el mensaje de la fila va en `ModelEntry.message`.
  final ModelError? failure;

  /// Error de una llamada (`models.list`, `download`, `delete`: `busy`, `not-found`, `internal`).
  final CoreError? error;

  ModelEntry? entry(String id) {
    for (final m in models) {
      if (m.id == id) return m;
    }
    return null;
  }

  SettingsModelsState copyWith({
    List<ModelEntry>? models,
    int? modelsBytes,
    bool? loaded,
    Object? failure = _keep,
    Object? error = _keep,
  }) => SettingsModelsState(
    models: models ?? this.models,
    modelsBytes: modelsBytes ?? this.modelsBytes,
    loaded: loaded ?? this.loaded,
    failure: identical(failure, _keep) ? this.failure : failure as ModelError?,
    error: identical(error, _keep) ? this.error : error as CoreError?,
  );
}

final settingsModelsStoreProvider =
    NotifierProvider<SettingsModelsStore, SettingsModelsState>(SettingsModelsStore.new);

class SettingsModelsStore extends Notifier<SettingsModelsState> {
  CoreClient get _core => ref.read(coreClientProvider);

  @override
  SettingsModelsState build() {
    final subs = [
      _core.on<ModelProgress>('models.progress', ModelProgress.fromJson).listen(_onProgress),
      _core.on<ModelsChanged>('models.changed', ModelsChanged.fromJson).listen(_onChanged),
    ];
    ref.onDispose(() {
      for (final s in subs) {
        s.cancel();
      }
    });
    Future.microtask(refresh);
    return const SettingsModelsState();
  }

  Future<void> refresh() async {
    try {
      final r = await _core.call('models.list', const <String, Object?>{}, ModelsListResult.fromJson);
      if (ref.mounted) _apply(r);
    } on CoreError catch (e) {
      if (ref.mounted) state = state.copyWith(error: e, loaded: true);
    }
  }

  void _apply(ModelsListResult r) =>
      state = state.copyWith(models: r.models, modelsBytes: r.modelsBytes, loaded: true, error: null);

  void _onProgress(ModelProgress p) {
    if (!ref.mounted) return;
    state = state.copyWith(
      models: [
        for (final m in state.models)
          if (m.id != p.id)
            m
          else
            ModelEntry(
              id: m.id,
              name: m.name,
              // Un avance que llega antes que el `models.changed` ya implica descarga.
              stateRaw: m.state == ModelState.notInstalled || m.state == ModelState.failed
                  ? ModelState.downloading.raw
                  : m.stateRaw,
              archiveBytes: m.archiveBytes,
              fraction: p.fraction,
              bytes: m.bytes,
              sourceRaw: m.sourceRaw,
            ),
      ],
    );
  }

  void _onChanged(ModelsChanged c) {
    if (!ref.mounted) return;
    state = state.copyWith(models: c.models, loaded: true, failure: c.error, error: null);
  }

  /// «Descargar». Devuelve `started` (false si ya había una descarga) o null si falló (queda en `error`).
  Future<bool?> download(String id) async {
    try {
      final r = await _core.call(
        'models.download',
        ModelIDParams(id: id).toJson(),
        ModelsDownloadResult.fromJson,
      );
      if (!ref.mounted) return r.started;
      state = state.copyWith(failure: null, error: null);
      await refresh();
      return r.started;
    } on CoreError catch (e) {
      if (ref.mounted) state = state.copyWith(error: e);
      return null;
    }
  }

  /// «Borrar» (ya confirmado). Devuelve null si fue bien.
  Future<CoreError?> delete(String id) async {
    try {
      final r = await _core.call(
        'models.delete',
        ModelIDParams(id: id).toJson(),
        ModelsListResult.fromJson,
      );
      if (ref.mounted) _apply(r);
      return null;
    } on CoreError catch (e) {
      if (ref.mounted) state = state.copyWith(error: e);
      return e;
    }
  }

  void dismissError() => state = state.copyWith(error: null, failure: null);
}
