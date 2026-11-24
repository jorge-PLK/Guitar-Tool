import '../core/core_client.dart' show Json;
import 'library.dart';

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
    projects: jsonList(json['projects'], ProjectUsage.fromJson),
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
      RelocateProgress(fraction: jsonDouble(json['fraction']));

  final double fraction;

  Json toJson() => {'fraction': fraction};
}
