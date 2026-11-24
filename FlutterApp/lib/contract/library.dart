import '../core/core_client.dart' show Json;

export 'library_detail.dart';
export 'library_storage.dart';

/// Estado de separación (`ProjectSummary.separationState`). Valor no previsto → [unknown].
enum SeparationState {
  none('none'),
  queued('queued'),
  running('running'),
  done('done'),
  failed('failed'),
  unknown('unknown');

  const SeparationState(this.raw);

  /// Valor crudo del contrato.
  final String raw;

  static SeparationState fromRaw(String raw) => values.firstWhere(
    (v) => v != SeparationState.unknown && v.raw == raw,
    orElse: () => SeparationState.unknown,
  );
}

/// Decodificadores compartidos por los ficheros `library*.dart`.
double jsonDouble(Object? v) => (v as num).toDouble();
double? jsonOptDouble(Object? v) => (v as num?)?.toDouble();
List<T> jsonList<T>(Object? raw, T Function(Json) decode) => List.unmodifiable([
  for (final e in raw as List<Object?>) decode(e as Json),
]);

/// Resumen de tema (`library.list`, `library.project` aplanado).
class ProjectSummary {
  const ProjectSummary({
    required this.id,
    required this.title,
    required this.folderName,
    required this.duration,
    required this.sampleRate,
    required this.createdAt,
    required this.updatedAt,
    required this.separationState,
    required this.stemCount,
    required this.takeCount,
    required this.rigCount,
    required this.hasAnalysis,
    required this.guitars,
    this.artist,
    this.cover,
    this.separationError,
    this.origin,
  });

  factory ProjectSummary.fromJson(Json json) => ProjectSummary(
    id: json['id'] as String,
    title: json['title'] as String,
    folderName: json['folderName'] as String,
    duration: jsonDouble(json['duration']),
    sampleRate: jsonDouble(json['sampleRate']),
    createdAt: json['createdAt'] as String,
    updatedAt: json['updatedAt'] as String,
    separationState: SeparationState.fromRaw(json['separationState'] as String),
    stemCount: json['stemCount'] as int,
    takeCount: json['takeCount'] as int,
    rigCount: json['rigCount'] as int,
    hasAnalysis: json['hasAnalysis'] as bool,
    guitars: List.unmodifiable(
      (json['guitars'] as List<Object?>).cast<String>(),
    ),
    artist: json['artist'] as String?,
    cover: json['cover'] as String?,
    separationError: json['separationError'] as String?,
    origin: json['origin'] as String?,
  );

  final String id;
  final String title;

  /// Ausente si es nulo.
  final String? artist;
  final String folderName;
  final double duration;
  final double sampleRate;

  /// Ausente si es nulo.
  final String? cover;

  /// Fechas ISO-8601 tal cual vienen del contrato (sin reformatear).
  final String createdAt;
  final String updatedAt;
  final SeparationState separationState;

  /// Siempre presente en el JSON; `null` si no hay error.
  final String? separationError;
  final int stemCount;
  final int takeCount;
  final int rigCount;
  final bool hasAnalysis;

  /// Ausente si es nulo (`youtube|spotify`).
  final String? origin;
  final List<String> guitars;

  /// [createdAt] como `DateTime`; `null` si no parsea.
  DateTime? get createdAtDate => DateTime.tryParse(createdAt);

  /// [updatedAt] como `DateTime`; `null` si no parsea.
  DateTime? get updatedAtDate => DateTime.tryParse(updatedAt);

  Json toJson() => {
    'id': id,
    'title': title,
    if (artist != null) 'artist': artist,
    'folderName': folderName,
    'duration': duration,
    'sampleRate': sampleRate,
    if (cover != null) 'cover': cover,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'separationState': separationState.raw,
    'separationError': separationError,
    'stemCount': stemCount,
    'takeCount': takeCount,
    'rigCount': rigCount,
    'hasAnalysis': hasAnalysis,
    if (origin != null) 'origin': origin,
    'guitars': guitars,
  };
}

/// Carpeta omitida en `library.list`.
class SkippedInfo {
  const SkippedInfo({required this.folderName, required this.reason});

  factory SkippedInfo.fromJson(Json json) => SkippedInfo(
    folderName: json['folderName'] as String,
    reason: json['reason'] as String,
  );

  final String folderName;
  final String reason;

  Json toJson() => {'folderName': folderName, 'reason': reason};
}

/// Resultado de `library.list`.
class LibraryListResult {
  const LibraryListResult({required this.projects, required this.skipped});

  factory LibraryListResult.fromJson(Json json) => LibraryListResult(
    projects: jsonList(json['projects'], ProjectSummary.fromJson),
    skipped: jsonList(json['skipped'], SkippedInfo.fromJson),
  );

  final List<ProjectSummary> projects;
  final List<SkippedInfo> skipped;

  Json toJson() => {
    'projects': [for (final p in projects) p.toJson()],
    'skipped': [for (final s in skipped) s.toJson()],
  };
}

/// Parámetros con solo `id` de tema (`ProjectIDParams`).
class ProjectIDParams {
  const ProjectIDParams({required this.id});

  factory ProjectIDParams.fromJson(Json json) =>
      ProjectIDParams(id: json['id'] as String);

  final String id;

  Json toJson() => {'id': id};
}

/// Parámetros con `id` opcional (`OptionalIDParams`). `id: null` sale explícito.
class OptionalIDParams {
  const OptionalIDParams({this.id});

  factory OptionalIDParams.fromJson(Json json) =>
      OptionalIDParams(id: json['id'] as String?);

  final String? id;

  Json toJson() => {'id': id};
}

/// Resultado de `library.reveal`.
class RevealResult {
  const RevealResult({required this.revealed});

  factory RevealResult.fromJson(Json json) =>
      RevealResult(revealed: json['revealed'] as bool);

  final bool revealed;

  Json toJson() => {'revealed': revealed};
}

/// Parámetros de `library.rename`. `artist` ausente si es nulo.
class RenameParams {
  const RenameParams({required this.id, required this.title, this.artist});

  factory RenameParams.fromJson(Json json) => RenameParams(
    id: json['id'] as String,
    title: json['title'] as String,
    artist: json['artist'] as String?,
  );

  final String id;
  final String title;
  final String? artist;

  Json toJson() => {
    'id': id,
    'title': title,
    if (artist != null) 'artist': artist,
  };
}

/// Resultado de `library.rename`. `artist` siempre presente (`null` si vacío).
class RenameResult {
  const RenameResult({required this.id, required this.title, this.artist});

  factory RenameResult.fromJson(Json json) => RenameResult(
    id: json['id'] as String,
    title: json['title'] as String,
    artist: json['artist'] as String?,
  );

  final String id;
  final String title;
  final String? artist;

  Json toJson() => {'id': id, 'title': title, 'artist': artist};
}

/// Resultado de `library.trash`, `library.delete` y `library.deleteTake`.
class RemovedResult {
  const RemovedResult({required this.removed});

  factory RemovedResult.fromJson(Json json) =>
      RemovedResult(removed: json['removed'] as bool);

  final bool removed;

  Json toJson() => {'removed': removed};
}

/// Resultado de `library.separate`.
class QueuedResult {
  const QueuedResult({required this.queued});

  factory QueuedResult.fromJson(Json json) =>
      QueuedResult(queued: json['queued'] as bool);

  final bool queued;

  Json toJson() => {'queued': queued};
}

/// Resultado de `library.markBest`.
class MarkedResult {
  const MarkedResult({required this.marked});

  factory MarkedResult.fromJson(Json json) =>
      MarkedResult(marked: json['marked'] as bool);

  final bool marked;

  Json toJson() => {'marked': marked};
}

/// Parámetros de `library.artistPhoto`.
class ArtistPhotoParams {
  const ArtistPhotoParams({required this.name});

  factory ArtistPhotoParams.fromJson(Json json) =>
      ArtistPhotoParams(name: json['name'] as String);

  final String name;

  Json toJson() => {'name': name};
}

/// Resultado de `library.artistPhoto`. `photo` sale siempre (`null` si no hay foto).
class ArtistPhotoResult {
  const ArtistPhotoResult({this.photo});

  factory ArtistPhotoResult.fromJson(Json json) =>
      ArtistPhotoResult(photo: json['photo'] as String?);

  /// URL `data:image/…;base64,…` o `null`.
  final String? photo;

  Json toJson() => {'photo': photo};
}
