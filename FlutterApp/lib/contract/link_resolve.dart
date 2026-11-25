import '../core/core_client.dart' show Json;
import 'json_read.dart';
import 'playlist_snapshot.dart';

/// Clase de URL (`LinkClassifyResult.kind`). Valor no previsto → [unknown].
enum LinkKind {
  playlist('playlist'),
  track('track'),
  unsupported('unsupported'),
  unknown('unknown');

  const LinkKind(this.raw);

  /// Valor crudo del contrato.
  final String raw;

  static LinkKind fromRaw(String raw) => values.firstWhere(
    (v) => v != LinkKind.unknown && v.raw == raw,
    orElse: () => LinkKind.unknown,
  );
}

/// Origen de la URL (`LinkClassifyResult.source`). Valor no previsto → [unknown].
enum LinkSource {
  youtube('youtube'),
  spotify('spotify'),
  unknown('unknown');

  const LinkSource(this.raw);

  /// Valor crudo del contrato.
  final String raw;

  static LinkSource fromRaw(String raw) => values.firstWhere(
    (v) => v != LinkSource.unknown && v.raw == raw,
    orElse: () => LinkSource.unknown,
  );
}

/// Tipo de resolución (`LinkResolveResult.link`). Valor no previsto → [unknown].
enum LinkResolveKind {
  youtube('youtube'),
  spotify('spotify'),
  playlist('playlist'),
  unknown('unknown');

  const LinkResolveKind(this.raw);

  /// Valor crudo del contrato.
  final String raw;

  static LinkResolveKind fromRaw(String raw) => values.firstWhere(
    (v) => v != LinkResolveKind.unknown && v.raw == raw,
    orElse: () => LinkResolveKind.unknown,
  );
}

/// Parámetros de `link.classify` y `link.resolve`.
class LinkURLParams {
  const LinkURLParams({required this.url});

  factory LinkURLParams.fromJson(Json json) =>
      LinkURLParams(url: json['url'] as String);

  final String url;

  Json toJson() => {'url': url};
}

/// Resultado de `link.classify`. `source` ausente si [LinkKind.unsupported].
class LinkClassifyResult {
  const LinkClassifyResult({required this.kind, this.source});

  factory LinkClassifyResult.fromJson(Json json) => LinkClassifyResult(
    kind: LinkKind.fromRaw(json['kind'] as String),
    source: json['source'] == null
        ? null
        : LinkSource.fromRaw(json['source'] as String),
  );

  final LinkKind kind;

  /// Ausente si es nulo.
  final LinkSource? source;

  Json toJson() => {
    'kind': kind.raw,
    if (source != null) 'source': source?.raw,
  };
}

/// Tema de biblioteca ya existente (`LinkResolveResult.existing`, `possibleDuplicate`, `inLibrary`).
class LinkTrackInfo {
  const LinkTrackInfo({required this.id, required this.title, this.artist});

  factory LinkTrackInfo.fromJson(Json json) => LinkTrackInfo(
    id: json['id'] as String,
    title: json['title'] as String,
    artist: json['artist'] as String?,
  );

  /// UUID en mayúsculas.
  final String id;
  final String title;

  /// Ausente si es nulo.
  final String? artist;

  Json toJson() => {
    'id': id,
    'title': title,
    if (artist != null) 'artist': artist,
  };
}

/// Candidato de vídeo (`LinkResolveResult.candidates`, `LinkAddManualResult.resolution`).
class LinkCandidateInfo {
  const LinkCandidateInfo({
    required this.id,
    required this.title,
    required this.source,
    required this.url,
    required this.isClose,
    required this.isLive,
    this.artist,
    this.duration,
    this.thumbnail,
    this.difference,
    this.inLibrary,
  });

  factory LinkCandidateInfo.fromJson(Json json) => LinkCandidateInfo(
    id: json['id'] as String,
    title: json['title'] as String,
    artist: json['artist'] as String?,
    duration: jsonOptDouble(json['duration']),
    thumbnail: json['thumbnail'] as String?,
    source: json['source'] as String,
    url: json['url'] as String,
    isClose: json['isClose'] as bool,
    isLive: json['isLive'] as bool,
    difference: jsonOptDouble(json['difference']),
    inLibrary: json['inLibrary'] == null
        ? null
        : LinkTrackInfo.fromJson(json['inLibrary'] as Json),
  );

  /// Id de vídeo de YouTube.
  final String id;
  final String title;

  /// Ausente si es nulo.
  final String? artist;

  /// Segundos. Ausente si es nulo.
  final double? duration;

  /// Ausente si es nulo.
  final String? thumbnail;

  /// Siempre `"youtube"`.
  final String source;
  final String url;
  final bool isClose;
  final bool isLive;

  /// Diferencia de duración en segundos. Ausente en la confirmación.
  final double? difference;

  /// Presente si ese vídeo ya está en la biblioteca (no seleccionable).
  final LinkTrackInfo? inLibrary;

  Json toJson() => {
    'id': id,
    'title': title,
    if (artist != null) 'artist': artist,
    if (duration != null) 'duration': duration,
    if (thumbnail != null) 'thumbnail': thumbnail,
    'source': source,
    'url': url,
    'isClose': isClose,
    'isLive': isLive,
    if (difference != null) 'difference': difference,
    if (inLibrary != null) 'inLibrary': inLibrary?.toJson(),
  };
}

/// Resultado de `link.resolve`. Si la URL es lista o álbum, [link] es
/// [LinkResolveKind.playlist] y [playlist] viene relleno.
class LinkResolveResult {
  const LinkResolveResult({
    required this.link,
    required this.pastedURL,
    required this.title,
    required this.noCloseCandidate,
    required this.candidates,
    this.artist,
    this.album,
    this.duration,
    this.thumbnail,
    this.existing,
    this.possibleDuplicate,
    this.playlist,
  });

  factory LinkResolveResult.fromJson(Json json) => LinkResolveResult(
    link: LinkResolveKind.fromRaw(json['link'] as String),
    pastedURL: json['pastedURL'] as String,
    title: json['title'] as String,
    artist: json['artist'] as String?,
    album: json['album'] as String?,
    duration: jsonOptDouble(json['duration']),
    thumbnail: json['thumbnail'] as String?,
    existing: json['existing'] == null
        ? null
        : LinkTrackInfo.fromJson(json['existing'] as Json),
    possibleDuplicate: json['possibleDuplicate'] == null
        ? null
        : LinkTrackInfo.fromJson(json['possibleDuplicate'] as Json),
    noCloseCandidate: json['noCloseCandidate'] as bool,
    candidates: jsonList(json['candidates'], LinkCandidateInfo.fromJson),
    playlist: json['playlist'] as Json?,
  );

  final LinkResolveKind link;
  final String pastedURL;
  final String title;

  /// Ausente si es nulo.
  final String? artist;

  /// Ausente si es nulo.
  final String? album;

  /// Segundos. Ausente si es nulo.
  final double? duration;

  /// URL https. Ausente si es nulo.
  final String? thumbnail;

  /// Tema ya en la biblioteca; si viene, `candidates` va vacío.
  final LinkTrackInfo? existing;
  final LinkTrackInfo? possibleDuplicate;
  final bool noCloseCandidate;
  final List<LinkCandidateInfo> candidates;

  /// `PlaylistSnapshot` crudo. Ausente si es nulo.
  final Json? playlist;

  /// [playlist] decodificado como [PlaylistSnapshot]. Nulo si no viene.
  PlaylistSnapshot? get playlistSnapshot {
    final raw = playlist;
    return raw == null ? null : PlaylistSnapshot.fromJson(raw);
  }

  Json toJson() => {
    'link': link.raw,
    'pastedURL': pastedURL,
    'title': title,
    if (artist != null) 'artist': artist,
    if (album != null) 'album': album,
    if (duration != null) 'duration': duration,
    if (thumbnail != null) 'thumbnail': thumbnail,
    if (existing != null) 'existing': existing?.toJson(),
    if (possibleDuplicate != null)
      'possibleDuplicate': possibleDuplicate?.toJson(),
    'noCloseCandidate': noCloseCandidate,
    'candidates': [for (final c in candidates) c.toJson()],
    if (playlist != null) 'playlist': playlist,
  };
}
