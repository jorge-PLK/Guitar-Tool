import '../core/core_client.dart' show Json;

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

/// Tipo de stem (`StemInfo.kind`). Valor no previsto → [unknown].
enum StemKind {
  bass('bass'),
  drums('drums'),
  other('other'),
  vocals('vocals'),
  guitar('guitar'),
  piano('piano'),
  unknown('unknown');

  const StemKind(this.raw);

  /// Valor crudo del contrato.
  final String raw;

  static StemKind fromRaw(String raw) => values.firstWhere(
    (v) => v != StemKind.unknown && v.raw == raw,
    orElse: () => StemKind.unknown,
  );
}

/// Modo de `library.relocate`. Valor no previsto → [unknown].
enum RelocateMode {
  move('move'),
  point('point'),
  unknown('unknown');

  const RelocateMode(this.raw);

  /// Valor crudo del contrato.
  final String raw;

  static RelocateMode fromRaw(String raw) => values.firstWhere(
    (v) => v != RelocateMode.unknown && v.raw == raw,
    orElse: () => RelocateMode.unknown,
  );
}

double _double(Object? v) => (v as num).toDouble();
double? _optDouble(Object? v) => (v as num?)?.toDouble();
List<T> _list<T>(Object? raw, T Function(Json) decode) => List.unmodifiable([
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
    duration: _double(json['duration']),
    sampleRate: _double(json['sampleRate']),
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
    projects: _list(json['projects'], ProjectSummary.fromJson),
    skipped: _list(json['skipped'], SkippedInfo.fromJson),
  );

  final List<ProjectSummary> projects;
  final List<SkippedInfo> skipped;

  Json toJson() => {
    'projects': [for (final p in projects) p.toJson()],
    'skipped': [for (final s in skipped) s.toJson()],
  };
}

/// Stem de un tema (`StemInfo`).
class StemInfo {
  const StemInfo({
    required this.kind,
    required this.bytes,
    required this.isEmpty,
  });

  factory StemInfo.fromJson(Json json) => StemInfo(
    kind: StemKind.fromRaw(json['kind'] as String),
    bytes: json['bytes'] as int,
    isEmpty: json['isEmpty'] as bool,
  );

  final StemKind kind;
  final int bytes;
  final bool isEmpty;

  Json toJson() => {'kind': kind.raw, 'bytes': bytes, 'isEmpty': isEmpty};
}

/// Punch de una toma (`TakePunchInfo`).
class TakePunchInfo {
  const TakePunchInfo({
    required this.start,
    required this.end,
    this.videoPath,
    this.videoOffsetMs,
  });

  factory TakePunchInfo.fromJson(Json json) => TakePunchInfo(
    start: _double(json['start']),
    end: _double(json['end']),
    videoPath: json['videoPath'] as String?,
    videoOffsetMs: _optDouble(json['videoOffsetMs']),
  );

  final double start;
  final double end;

  /// Ausente si es nulo.
  final String? videoPath;

  /// Ausente si es nulo.
  final double? videoOffsetMs;

  Json toJson() => {
    'start': start,
    'end': end,
    if (videoPath != null) 'videoPath': videoPath,
    if (videoOffsetMs != null) 'videoOffsetMs': videoOffsetMs,
  };
}

/// Toma (`TakeInfo`). Opcionales ausentes si son nulos.
class TakeInfo {
  const TakeInfo({
    required this.id,
    required this.number,
    required this.createdAt,
    required this.discarded,
    required this.isBest,
    required this.hasVideo,
    required this.punchCount,
    required this.videoRotation,
    required this.punches,
    this.duration,
    this.audio,
    this.video,
    this.songStart,
    this.videoOffsetMs,
  });

  factory TakeInfo.fromJson(Json json) => TakeInfo(
    id: json['id'] as String,
    number: json['number'] as int,
    createdAt: json['createdAt'] as String,
    discarded: json['discarded'] as bool,
    isBest: json['isBest'] as bool,
    hasVideo: json['hasVideo'] as bool,
    punchCount: json['punchCount'] as int,
    videoRotation: json['videoRotation'] as int,
    punches: _list(json['punches'], TakePunchInfo.fromJson),
    duration: _optDouble(json['duration']),
    audio: json['audio'] as String?,
    video: json['video'] as String?,
    songStart: _optDouble(json['songStart']),
    videoOffsetMs: _optDouble(json['videoOffsetMs']),
  );

  final String id;
  final int number;
  final String createdAt;
  final bool discarded;
  final bool isBest;
  final bool hasVideo;
  final int punchCount;
  final int videoRotation;
  final List<TakePunchInfo> punches;
  final double? duration;
  final String? audio;
  final String? video;
  final double? songStart;
  final double? videoOffsetMs;

  Json toJson() => {
    'id': id,
    'number': number,
    'createdAt': createdAt,
    'discarded': discarded,
    'isBest': isBest,
    'hasVideo': hasVideo,
    'punchCount': punchCount,
    'videoRotation': videoRotation,
    'punches': [for (final p in punches) p.toJson()],
    if (duration != null) 'duration': duration,
    if (audio != null) 'audio': audio,
    if (video != null) 'video': video,
    if (songStart != null) 'songStart': songStart,
    if (videoOffsetMs != null) 'videoOffsetMs': videoOffsetMs,
  };
}

/// Parte de un tema (`PartInfo`).
class PartInfo {
  const PartInfo({
    required this.id,
    required this.name,
    required this.isLead,
    required this.takes,
  });

  factory PartInfo.fromJson(Json json) => PartInfo(
    id: json['id'] as String,
    name: json['name'] as String,
    isLead: json['isLead'] as bool,
    takes: _list(json['takes'], TakeInfo.fromJson),
  );

  final String id;
  final String name;
  final bool isLead;
  final List<TakeInfo> takes;

  Json toJson() => {
    'id': id,
    'name': name,
    'isLead': isLead,
    'takes': [for (final t in takes) t.toJson()],
  };
}

/// Resultado de `library.project`: el resumen aplanado más stems, partes y vídeos.
class ProjectDetailResult {
  const ProjectDetailResult({
    required this.summary,
    required this.stems,
    required this.parts,
    required this.videoCount,
  });

  factory ProjectDetailResult.fromJson(Json json) => ProjectDetailResult(
    summary: ProjectSummary.fromJson(json),
    stems: _list(json['stems'], StemInfo.fromJson),
    parts: _list(json['parts'], PartInfo.fromJson),
    videoCount: json['videoCount'] as int,
  );

  final ProjectSummary summary;
  final List<StemInfo> stems;
  final List<PartInfo> parts;
  final int videoCount;

  Json toJson() => {
    ...summary.toJson(),
    'stems': [for (final s in stems) s.toJson()],
    'parts': [for (final p in parts) p.toJson()],
    'videoCount': videoCount,
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

/// Parámetros de `library.deleteTake`.
class DeleteTakeParams {
  const DeleteTakeParams({required this.id, required this.takeId});

  factory DeleteTakeParams.fromJson(Json json) => DeleteTakeParams(
    id: json['id'] as String,
    takeId: json['takeId'] as String,
  );

  final String id;
  final String takeId;

  Json toJson() => {'id': id, 'takeId': takeId};
}

/// Parámetros de `library.markBest`.
class MarkBestParams {
  const MarkBestParams({required this.id, required this.takeId});

  factory MarkBestParams.fromJson(Json json) => MarkBestParams(
    id: json['id'] as String,
    takeId: json['takeId'] as String,
  );

  final String id;
  final String takeId;

  Json toJson() => {'id': id, 'takeId': takeId};
}

/// Resultado de `library.markBest`.
class MarkedResult {
  const MarkedResult({required this.marked});

  factory MarkedResult.fromJson(Json json) =>
      MarkedResult(marked: json['marked'] as bool);

  final bool marked;

  Json toJson() => {'marked': marked};
}

/// Resultado de `library.cleanupInfo`.
class CleanupInfoResult {
  const CleanupInfoResult({required this.bytes});

  factory CleanupInfoResult.fromJson(Json json) =>
      CleanupInfoResult(bytes: json['bytes'] as int);

  final int bytes;

  Json toJson() => {'bytes': bytes};
}

/// Resultado de `library.cleanup`.
class CleanupResult {
  const CleanupResult({required this.cleaned, required this.bytes});

  factory CleanupResult.fromJson(Json json) => CleanupResult(
    cleaned: json['cleaned'] as bool,
    bytes: json['bytes'] as int,
  );

  final bool cleaned;
  final int bytes;

  Json toJson() => {'cleaned': cleaned, 'bytes': bytes};
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

/// Uso de disco de un tema (`library.usage.projects[]`).
class ProjectUsage {
  const ProjectUsage({
    required this.id,
    required this.folderName,
    required this.bytes,
    required this.regenerableBytes,
  });

  factory ProjectUsage.fromJson(Json json) => ProjectUsage(
    id: json['id'] as String,
    folderName: json['folderName'] as String,
    bytes: json['bytes'] as int,
    regenerableBytes: json['regenerableBytes'] as int,
  );

  final String id;
  final String folderName;
  final int bytes;
  final int regenerableBytes;

  Json toJson() => {
    'id': id,
    'folderName': folderName,
    'bytes': bytes,
    'regenerableBytes': regenerableBytes,
  };
}

/// Resultado de `library.usage`.
class UsageResult {
  const UsageResult({
    required this.totalBytes,
    required this.regenerableBytes,
    required this.projects,
  });

  factory UsageResult.fromJson(Json json) => UsageResult(
    totalBytes: json['totalBytes'] as int,
    regenerableBytes: json['regenerableBytes'] as int,
    projects: _list(json['projects'], ProjectUsage.fromJson),
  );

  final int totalBytes;
  final int regenerableBytes;
  final List<ProjectUsage> projects;

  Json toJson() => {
    'totalBytes': totalBytes,
    'regenerableBytes': regenerableBytes,
    'projects': [for (final p in projects) p.toJson()],
  };
}

/// Parámetros de `library.relocate`.
class RelocateParams {
  const RelocateParams({required this.path, required this.mode});

  factory RelocateParams.fromJson(Json json) => RelocateParams(
    path: json['path'] as String,
    mode: RelocateMode.fromRaw(json['mode'] as String),
  );

  final String path;
  final RelocateMode mode;

  Json toJson() => {'path': path, 'mode': mode.raw};
}

/// Resultado de `library.relocate` y evento `library.relocated`.
class RelocateResult {
  const RelocateResult({required this.path, required this.mediaRemapped});

  factory RelocateResult.fromJson(Json json) => RelocateResult(
    path: json['path'] as String,
    mediaRemapped: json['mediaRemapped'] as bool,
  );

  final String path;
  final bool mediaRemapped;

  Json toJson() => {'path': path, 'mediaRemapped': mediaRemapped};
}

/// Evento `library.relocateProgress`.
class RelocateProgress {
  const RelocateProgress({required this.fraction});

  factory RelocateProgress.fromJson(Json json) =>
      RelocateProgress(fraction: _double(json['fraction']));

  final double fraction;

  Json toJson() => {'fraction': fraction};
}
