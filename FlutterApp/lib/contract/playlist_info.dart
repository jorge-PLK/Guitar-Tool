import '../core/core_client.dart' show Json;
import 'json_read.dart';
import 'link_resolve.dart' show LinkCandidateInfo, LinkTrackInfo;
import 'playlist_enums.dart';

/// Error de tema o de sesión (`PlaylistSnapshot.error`, `PlaylistItemInfo.error`).
class PlaylistErrorInfo {
  const PlaylistErrorInfo({
    required this.code,
    required this.title,
    required this.detail,
    required this.suggestsUpdate,
  });

  factory PlaylistErrorInfo.fromJson(Json json) => PlaylistErrorInfo(
    code: json['code'] as String,
    title: json['title'] as String,
    detail: json['detail'] as String,
    suggestsUpdate: json['suggestsUpdate'] as bool,
  );

  /// Mismos códigos que `SourceMessages.code`.
  final String code;
  final String title;
  final String detail;

  /// True con `extractor-broken`.
  final bool suggestsUpdate;

  Json toJson() => {
    'code': code,
    'title': title,
    'detail': detail,
    'suggestsUpdate': suggestsUpdate,
  };
}

/// Contadores de la lista (`PlaylistSnapshot.totals`).
class PlaylistTotalsInfo {
  const PlaylistTotalsInfo({
    required this.total,
    required this.selected,
    required this.imported,
    required this.skipped,
    required this.failed,
    required this.inLibrary,
    required this.remaining,
    required this.queued,
    required this.duplicates,
  });

  factory PlaylistTotalsInfo.fromJson(Json json) => PlaylistTotalsInfo(
    total: json['total'] as int,
    selected: json['selected'] as int,
    imported: json['imported'] as int,
    skipped: json['skipped'] as int,
    failed: json['failed'] as int,
    inLibrary: json['inLibrary'] as int,
    remaining: json['remaining'] as int,
    queued: json['queued'] as int,
    duplicates: json['duplicates'] as int,
  );

  final int total;
  final int selected;
  final int imported;
  final int skipped;
  final int failed;
  final int inLibrary;
  final int remaining;

  /// Marcados con candidato y sin terminar.
  final int queued;

  /// Incluidos en [imported].
  final int duplicates;

  Json toJson() => {
    'total': total,
    'selected': selected,
    'imported': imported,
    'skipped': skipped,
    'failed': failed,
    'inLibrary': inLibrary,
    'remaining': remaining,
    'queued': queued,
    'duplicates': duplicates,
  };
}

/// Resumen final de la cola (`PlaylistSnapshot.summary`).
class PlaylistSummaryInfo {
  const PlaylistSummaryInfo({
    required this.imported,
    required this.skipped,
    required this.inLibrary,
    required this.failed,
    required this.remaining,
    required this.cancelled,
  });

  factory PlaylistSummaryInfo.fromJson(Json json) => PlaylistSummaryInfo(
    imported: json['imported'] as int,
    skipped: json['skipped'] as int,
    inLibrary: json['inLibrary'] as int,
    failed: json['failed'] as int,
    remaining: json['remaining'] as int,
    cancelled: json['cancelled'] as bool,
  );

  final int imported;
  final int skipped;
  final int inLibrary;
  final int failed;
  final int remaining;
  final bool cancelled;

  Json toJson() => {
    'imported': imported,
    'skipped': skipped,
    'inLibrary': inLibrary,
    'failed': failed,
    'remaining': remaining,
    'cancelled': cancelled,
  };
}

/// Estado de la actualización de yt-dlp (`PlaylistSnapshot.update`).
class PlaylistUpdateInfo {
  const PlaylistUpdateInfo({
    required this.updating,
    required this.alreadyLatest,
    this.error,
  });

  factory PlaylistUpdateInfo.fromJson(Json json) => PlaylistUpdateInfo(
    updating: json['updating'] as bool,
    alreadyLatest: json['alreadyLatest'] as bool,
    error: json['error'] as String?,
  );

  final bool updating;
  final bool alreadyLatest;

  /// Ausente si es nulo.
  final String? error;

  Json toJson() => {
    'updating': updating,
    'alreadyLatest': alreadyLatest,
    if (error != null) 'error': error,
  };
}

/// Tema de la lista (`PlaylistSnapshot.items`).
class PlaylistItemInfo {
  const PlaylistItemInfo({
    required this.id,
    required this.title,
    required this.artist,
    required this.kind,
    required this.selected,
    required this.status,
    required this.candidates,
    this.duration,
    this.stage,
    this.progress,
    this.error,
    this.inLibrary,
    this.possible,
    this.chosen,
  });

  factory PlaylistItemInfo.fromJson(Json json) => PlaylistItemInfo(
    id: json['id'] as String,
    title: json['title'] as String,
    artist: json['artist'] as String,
    duration: jsonOptDouble(json['duration']),
    kind: PlaylistSource.fromRaw(json['kind'] as String),
    selected: json['selected'] as bool,
    status: PlaylistItemStatus.fromRaw(json['status'] as String),
    stage: json['stage'] == null
        ? null
        : PlaylistItemStage.fromRaw(json['stage'] as String),
    progress: jsonOptDouble(json['progress']),
    error: json['error'] == null
        ? null
        : PlaylistErrorInfo.fromJson(json['error'] as Json),
    inLibrary: json['inLibrary'] == null
        ? null
        : LinkTrackInfo.fromJson(json['inLibrary'] as Json),
    possible: json['possible'] == null
        ? null
        : LinkTrackInfo.fromJson(json['possible'] as Json),
    candidates: jsonList(json['candidates'], LinkCandidateInfo.fromJson),
    chosen: json['chosen'] == null
        ? null
        : LinkCandidateInfo.fromJson(json['chosen'] as Json),
  );

  final String id;
  final String title;

  /// Siempre presente; puede ser `""`.
  final String artist;

  /// Segundos. Ausente si es nulo.
  final double? duration;

  /// Origen del tema (`kind` en el JSON).
  final PlaylistSource kind;
  final bool selected;
  final PlaylistItemStatus status;

  /// Solo con `downloading`. Ausente si es nulo.
  final PlaylistItemStage? stage;

  /// 0…1. Solo con `downloading` en `download`; ausente = indeterminado.
  final double? progress;

  /// Solo con `failed`. Ausente si es nulo.
  final PlaylistErrorInfo? error;

  /// El propio tema ya está en la biblioteca.
  final LinkTrackInfo? inLibrary;

  /// «Puede que ya lo tengas» (mismo título y artista, otro id).
  final LinkTrackInfo? possible;
  final List<LinkCandidateInfo> candidates;

  /// Ausente si es nulo.
  final LinkCandidateInfo? chosen;

  Json toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    if (duration != null) 'duration': duration,
    'kind': kind.raw,
    'selected': selected,
    'status': status.raw,
    if (stage != null) 'stage': stage?.raw,
    if (progress != null) 'progress': progress,
    if (error != null) 'error': error?.toJson(),
    if (inLibrary != null) 'inLibrary': inLibrary?.toJson(),
    if (possible != null) 'possible': possible?.toJson(),
    'candidates': [for (final c in candidates) c.toJson()],
    if (chosen != null) 'chosen': chosen?.toJson(),
  };
}
