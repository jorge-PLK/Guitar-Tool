import '../core/core_client.dart' show Json;

/// Etapa de un trabajo (`JobInfo.stage`). Valor no previsto → [unknown].
enum JobStage {
  importStage('import'),
  separation('separation'),
  guitars('guitars'),
  analysis('analysis'),
  download('download'),
  unknown('unknown');

  const JobStage(this.raw);

  /// Valor crudo del contrato.
  final String raw;

  static JobStage fromRaw(String raw) => values.firstWhere(
        (v) => v != JobStage.unknown && v.raw == raw,
        orElse: () => JobStage.unknown,
      );
}

/// Estado de un trabajo (`JobInfo.state`). Valor no previsto → [unknown].
enum JobState {
  queued('queued'),
  running('running'),
  done('done'),
  failed('failed'),
  cancelled('cancelled'),
  unknown('unknown');

  const JobState(this.raw);

  /// Valor crudo del contrato.
  final String raw;

  static JobState fromRaw(String raw) => values.firstWhere(
        (v) => v != JobState.unknown && v.raw == raw,
        orElse: () => JobState.unknown,
      );
}

/// Trabajo vivo (`JobQueue.swift:6`, evento `jobs.progress`).
class JobInfo {
  const JobInfo({
    required this.id,
    required this.title,
    required this.stage,
    required this.state,
    required this.text,
    this.fraction,
    this.error,
  });

  factory JobInfo.fromJson(Json json) => JobInfo(
        id: json['id'] as String,
        title: json['title'] as String,
        stage: JobStage.fromRaw(json['stage'] as String),
        state: JobState.fromRaw(json['state'] as String),
        fraction: (json['fraction'] as num?)?.toDouble(),
        text: json['text'] as String,
        error: json['error'] as String?,
      );

  /// UUID del tema, `import-N`, `link-N` o `playlist-<id>`.
  final String id;
  final String title;
  final JobStage stage;
  final JobState state;

  /// Ausente si es nulo.
  final double? fraction;
  final String text;

  /// Ausente si es nulo.
  final String? error;

  bool get isLinkJob => id.startsWith('link-');
  bool get isPlaylistJob => id.startsWith('playlist-');
  bool get isImportJob => id.startsWith('import-');

  Json toJson() => {
        'id': id,
        'title': title,
        'stage': stage.raw,
        'state': state.raw,
        if (fraction != null) 'fraction': fraction,
        'text': text,
        if (error != null) 'error': error,
      };
}

/// Resultado de `jobs.list`.
class JobsListResult {
  const JobsListResult({required this.jobs});

  factory JobsListResult.fromJson(Json json) => JobsListResult(
        jobs: List.unmodifiable(
          (json['jobs'] as List<Object?>)
              .map((e) => JobInfo.fromJson(e as Json)),
        ),
      );

  final List<JobInfo> jobs;

  Json toJson() => {
        'jobs': [for (final j in jobs) j.toJson()],
      };
}

/// Resultado de `jobs.cancel`.
class CancelResult {
  const CancelResult({required this.cancelled});

  factory CancelResult.fromJson(Json json) =>
      CancelResult(cancelled: json['cancelled'] as bool);

  final bool cancelled;

  Json toJson() => {'cancelled': cancelled};
}

/// Parámetros de `import.file`.
class ImportFileParams {
  const ImportFileParams({required this.path});

  factory ImportFileParams.fromJson(Json json) =>
      ImportFileParams(path: json['path'] as String);

  final String path;

  Json toJson() => {'path': path};
}

/// Resultado de `import.file`. Un duplicado no es error.
class ImportResult {
  const ImportResult({required this.id, required this.duplicate});

  factory ImportResult.fromJson(Json json) => ImportResult(
        id: json['id'] as String,
        duplicate: json['duplicate'] as bool,
      );

  final String id;
  final bool duplicate;

  Json toJson() => {'id': id, 'duplicate': duplicate};
}

/// Parámetros de `jobs.cancel`.
class JobCancelParams {
  const JobCancelParams({required this.id});

  factory JobCancelParams.fromJson(Json json) =>
      JobCancelParams(id: json['id'] as String);

  final String id;

  Json toJson() => {'id': id};
}
