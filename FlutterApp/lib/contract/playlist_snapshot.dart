import '../core/core_client.dart' show Json;
import 'json_read.dart';
import 'playlist_enums.dart';
import 'playlist_info.dart';

/// Instantánea de la sesión de lista (`playlist.state`, `playlist.changed`, `AppInfo.playlist`,
/// `LinkResolveResult.playlist`).
class PlaylistSnapshot {
  const PlaylistSnapshot({
    required this.step,
    required this.name,
    required this.source,
    required this.kind,
    required this.mayBeTruncated,
    required this.isLive,
    required this.totals,
    required this.summary,
    required this.progress,
    required this.update,
    required this.warnings,
    required this.items,
    this.searchDone,
    this.searchTotal,
    this.error,
    this.indicator,
  });

  factory PlaylistSnapshot.fromJson(Json json) => PlaylistSnapshot(
    step: PlaylistStep.fromRaw(json['step'] as String),
    searchDone: json['searchDone'] as int?,
    searchTotal: json['searchTotal'] as int?,
    error: json['error'] == null
        ? null
        : PlaylistErrorInfo.fromJson(json['error'] as Json),
    name: json['name'] as String,
    source: PlaylistSource.fromRaw(json['source'] as String),
    kind: PlaylistKind.fromRaw(json['kind'] as String),
    mayBeTruncated: json['mayBeTruncated'] as bool,
    isLive: json['isLive'] as bool,
    indicator: json['indicator'] as String?,
    totals: PlaylistTotalsInfo.fromJson(json['totals'] as Json),
    summary: PlaylistSummaryInfo.fromJson(json['summary'] as Json),
    progress: jsonDouble(json['progress']),
    update: PlaylistUpdateInfo.fromJson(json['update'] as Json),
    warnings: List<String>.unmodifiable([
      for (final w in json['warnings'] as List<Object?>) w as String,
    ]),
    items: jsonList(json['items'], PlaylistItemInfo.fromJson),
  );

  final PlaylistStep step;

  /// Solo con `searching`. Ausente si es nulo.
  final int? searchDone;

  /// Solo con `searching`. Ausente si es nulo.
  final int? searchTotal;

  /// Solo con `stopped` y error. Ausente si es nulo.
  final PlaylistErrorInfo? error;
  final String name;
  final PlaylistSource source;
  final PlaylistKind kind;

  /// La lista puede estar cortada.
  final bool mayBeTruncated;

  /// Hay trabajo en marcha o parado.
  final bool isLive;

  /// Texto del indicador de Biblioteca. Ausente si es nulo.
  final String? indicator;
  final PlaylistTotalsInfo totals;
  final PlaylistSummaryInfo summary;

  /// 0…1 de la cola.
  final double progress;
  final PlaylistUpdateInfo update;

  /// Avisos no fatales.
  final List<String> warnings;
  final List<PlaylistItemInfo> items;

  Json toJson() => {
    'step': step.raw,
    if (searchDone != null) 'searchDone': searchDone,
    if (searchTotal != null) 'searchTotal': searchTotal,
    if (error != null) 'error': error?.toJson(),
    'name': name,
    'source': source.raw,
    'kind': kind.raw,
    'mayBeTruncated': mayBeTruncated,
    'isLive': isLive,
    if (indicator != null) 'indicator': indicator,
    'totals': totals.toJson(),
    'summary': summary.toJson(),
    'progress': progress,
    'update': update.toJson(),
    'warnings': [...warnings],
    'items': [for (final i in items) i.toJson()],
  };
}
