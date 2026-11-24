import '../core/core_client.dart' show Json;
import 'library.dart';

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
    start: jsonDouble(json['start']),
    end: jsonDouble(json['end']),
    videoPath: json['videoPath'] as String?,
    videoOffsetMs: jsonOptDouble(json['videoOffsetMs']),
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
    punches: jsonList(json['punches'], TakePunchInfo.fromJson),
    duration: jsonOptDouble(json['duration']),
    audio: json['audio'] as String?,
    video: json['video'] as String?,
    songStart: jsonOptDouble(json['songStart']),
    videoOffsetMs: jsonOptDouble(json['videoOffsetMs']),
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

  /// [createdAt] como `DateTime`; `null` si no parsea.
  DateTime? get createdAtDate => DateTime.tryParse(createdAt);

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
    takes: jsonList(json['takes'], TakeInfo.fromJson),
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
    stems: jsonList(json['stems'], StemInfo.fromJson),
    parts: jsonList(json['parts'], PartInfo.fromJson),
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
