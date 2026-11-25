import '../core/core_client.dart' show Json;
import 'json_read.dart';

/// Estado de un modelo (`ModelEntry.state`). Valor no previsto → [unknown].
enum ModelState {
  notInstalled('notInstalled'),
  downloading('downloading'),
  verifying('verifying'),
  installing('installing'),
  installed('installed'),
  failed('failed'),
  unknown('unknown');

  const ModelState(this.raw);

  /// Valor crudo del contrato.
  final String raw;

  static ModelState fromRaw(String raw) => values.firstWhere(
    (v) => v != ModelState.unknown && v.raw == raw,
    orElse: () => ModelState.unknown,
  );
}

/// Origen de un modelo (`ModelEntry.source`). Valor no previsto → [unknown].
enum ModelSource {
  store('store'),
  folder('folder'),
  unknown('unknown');

  const ModelSource(this.raw);

  /// Valor crudo del contrato.
  final String raw;

  static ModelSource fromRaw(String raw) => values.firstWhere(
    (v) => v != ModelSource.unknown && v.raw == raw,
    orElse: () => ModelSource.unknown,
  );
}

/// Error `{code, message}` de `models.changed` y de `models.delete`.
class ModelError {
  const ModelError({required this.code, required this.message});

  factory ModelError.fromJson(Json json) => ModelError(
    code: json['code'] as String,
    message: json['message'] as String,
  );

  final String code;
  final String message;

  Json toJson() => {'code': code, 'message': message};
}

/// Un modelo de `models.list`. Los nulos salen explícitos en `toJson`.
/// `stateRaw` y `sourceRaw` guardan el valor crudo para no perder los no previstos.
class ModelEntry {
  const ModelEntry({
    required this.id,
    required this.name,
    required this.stateRaw,
    required this.archiveBytes,
    this.fraction,
    this.bytes,
    this.message,
    this.sourceRaw,
  });

  factory ModelEntry.fromJson(Json json) => ModelEntry(
    id: json['id'] as String,
    name: json['name'] as String,
    stateRaw: json['state'] as String,
    fraction: jsonOptDouble(json['fraction']),
    bytes: json['bytes'] as int?,
    archiveBytes: json['archiveBytes'] as int,
    message: json['message'] as String?,
    sourceRaw: json['source'] as String?,
  );

  final String id;
  final String name;
  final String stateRaw;
  final double? fraction;
  final int? bytes;
  final int archiveBytes;
  final String? message;
  final String? sourceRaw;

  ModelState get state => ModelState.fromRaw(stateRaw);

  ModelSource? get source {
    final raw = sourceRaw;
    return raw == null ? null : ModelSource.fromRaw(raw);
  }

  Json toJson() => {
    'archiveBytes': archiveBytes,
    'bytes': bytes,
    'fraction': fraction,
    'id': id,
    'message': message,
    'name': name,
    'source': sourceRaw,
    'state': stateRaw,
  };
}

/// Resultado de `models.list`.
class ModelsListResult {
  const ModelsListResult({required this.models, required this.modelsBytes});

  factory ModelsListResult.fromJson(Json json) => ModelsListResult(
    models: jsonList(json['models'], ModelEntry.fromJson),
    modelsBytes: json['modelsBytes'] as int,
  );

  final List<ModelEntry> models;
  final int modelsBytes;

  Json toJson() => {
    'models': [for (final m in models) m.toJson()],
    'modelsBytes': modelsBytes,
  };
}

/// Parámetros de `models.download` y `models.delete`. `id` ausente = toda la lista.
class ModelIDParams {
  const ModelIDParams({this.id});

  factory ModelIDParams.fromJson(Json json) =>
      ModelIDParams(id: json['id'] as String?);

  final String? id;

  Json toJson() => {if (id != null) 'id': id};
}

/// Resultado de `models.download`; `false` si ya había una descarga.
class ModelsDownloadResult {
  const ModelsDownloadResult({required this.started});

  factory ModelsDownloadResult.fromJson(Json json) =>
      ModelsDownloadResult(started: json['started'] as bool);

  final bool started;

  Json toJson() => {'started': started};
}

/// Evento `models.progress`, un evento por punto porcentual.
class ModelProgress {
  const ModelProgress({required this.id, required this.fraction});

  factory ModelProgress.fromJson(Json json) => ModelProgress(
    id: json['id'] as String,
    fraction: jsonDouble(json['fraction']),
  );

  final String id;
  final double fraction;

  Json toJson() => {'id': id, 'fraction': fraction};
}

/// Evento `models.changed`. `error` es `null` si no hay fallo.
class ModelsChanged {
  const ModelsChanged({required this.models, this.error});

  factory ModelsChanged.fromJson(Json json) => ModelsChanged(
    models: jsonList(json['models'], ModelEntry.fromJson),
    error: json['error'] == null
        ? null
        : ModelError.fromJson(json['error'] as Json),
  );

  final List<ModelEntry> models;
  final ModelError? error;

  Json toJson() => {
    'models': [for (final m in models) m.toJson()],
    'error': error?.toJson(),
  };
}
