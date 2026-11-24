import '../core/core_client.dart' show Json;
import 'json_read.dart';
import 'link_resolve.dart';

/// Parámetros de `link.search`.
class LinkSearchParams {
  const LinkSearchParams({required this.query});

  factory LinkSearchParams.fromJson(Json json) =>
      LinkSearchParams(query: json['query'] as String);

  final String query;

  Json toJson() => {'query': query};
}

/// Tema de Spotify (`LinkSearchResult.tracks`). `imageURL` ausente si es nulo.
class LinkSpotifyTrack {
  const LinkSpotifyTrack({
    required this.id,
    required this.name,
    required this.artists,
    required this.album,
    required this.durationText,
    required this.trackURL,
    required this.appURL,
    this.year,
    this.imageURL,
  });

  factory LinkSpotifyTrack.fromJson(Json json) => LinkSpotifyTrack(
    id: json['id'] as String,
    name: json['name'] as String,
    artists: List.unmodifiable((json['artists'] as List<Object?>).cast<String>()),
    album: json['album'] as String,
    year: json['year'] as int?,
    durationText: json['durationText'] as String,
    imageURL: json['imageURL'] as String?,
    trackURL: json['trackURL'] as String,
    appURL: json['appURL'] as String,
  );

  final String id;
  final String name;
  final List<String> artists;
  final String album;

  /// Ausente si es nulo.
  final int? year;

  /// Ya formateado por SourceKit (`"4:13"`).
  final String durationText;

  /// Ausente si es nulo.
  final String? imageURL;

  /// URL absoluta en cadena.
  final String trackURL;

  /// URL absoluta en cadena.
  final String appURL;

  Json toJson() => {
    'id': id,
    'name': name,
    'artists': artists,
    'album': album,
    if (year != null) 'year': year,
    'durationText': durationText,
    if (imageURL != null) 'imageURL': imageURL,
    'trackURL': trackURL,
    'appURL': appURL,
  };
}

/// Resultado de `link.search`.
class LinkSearchResult {
  const LinkSearchResult({required this.query, required this.tracks});

  factory LinkSearchResult.fromJson(Json json) => LinkSearchResult(
    query: json['query'] as String,
    tracks: jsonList(json['tracks'], LinkSpotifyTrack.fromJson),
  );

  /// Recortado por el núcleo.
  final String query;
  final List<LinkSpotifyTrack> tracks;

  Json toJson() => {
    'query': query,
    'tracks': [for (final t in tracks) t.toJson()],
  };
}

/// Parámetros de `link.addManual`.
class LinkAddManualParams {
  const LinkAddManualParams({required this.url});

  factory LinkAddManualParams.fromJson(Json json) =>
      LinkAddManualParams(url: json['url'] as String);

  final String url;

  Json toJson() => {'url': url};
}

/// Resultado de `link.addManual`. `added` va primero en `resolution.candidates`.
class LinkAddManualResult {
  const LinkAddManualResult({
    required this.added,
    required this.selectable,
    required this.resolution,
  });

  factory LinkAddManualResult.fromJson(Json json) => LinkAddManualResult(
    added: json['added'] as String,
    selectable: json['selectable'] as bool,
    resolution: LinkResolveResult.fromJson(json['resolution'] as Json),
  );

  /// Id del vídeo añadido.
  final String added;

  /// `false` si ya está en la biblioteca.
  final bool selectable;
  final LinkResolveResult resolution;

  Json toJson() => {
    'added': added,
    'resolution': resolution.toJson(),
    'selectable': selectable,
  };
}

/// Parámetros de `link.import`. Hace falta `candidateId` o `url`.
/// `artist: ""` borra el artista; `title` vacío se ignora.
class LinkImportParams {
  const LinkImportParams({
    this.candidateId,
    this.url,
    this.title,
    this.artist,
  });

  factory LinkImportParams.fromJson(Json json) => LinkImportParams(
    candidateId: json['candidateId'] as String?,
    url: json['url'] as String?,
    title: json['title'] as String?,
    artist: json['artist'] as String?,
  );

  /// Ausente si es nulo.
  final String? candidateId;

  /// Ausente si es nulo.
  final String? url;

  /// Ausente si es nulo.
  final String? title;

  /// Ausente si es nulo.
  final String? artist;

  Json toJson() => {
    if (candidateId != null) 'candidateId': candidateId,
    if (url != null) 'url': url,
    if (title != null) 'title': title,
    if (artist != null) 'artist': artist,
  };
}

/// Resultado de `link.import`: el trabajo `link-N` encolado.
class LinkJobResult {
  const LinkJobResult({required this.jobId});

  factory LinkJobResult.fromJson(Json json) =>
      LinkJobResult(jobId: json['jobId'] as String);

  final String jobId;

  Json toJson() => {'jobId': jobId};
}

/// Parámetros de `link.cancel`. Sin `jobId` cancela la resolución viva.
class LinkCancelParams {
  const LinkCancelParams({this.jobId});

  factory LinkCancelParams.fromJson(Json json) =>
      LinkCancelParams(jobId: json['jobId'] as String?);

  /// Ausente si es nulo.
  final String? jobId;

  Json toJson() => {if (jobId != null) 'jobId': jobId};
}

/// Resultado de `link.cancel`. `false` si el `jobId` no existe o no había resolución.
class CancelledResult {
  const CancelledResult({required this.cancelled});

  factory CancelledResult.fromJson(Json json) =>
      CancelledResult(cancelled: json['cancelled'] as bool);

  final bool cancelled;

  Json toJson() => {'cancelled': cancelled};
}

/// Error de `link.finished` (`error.code`, `error.message`).
class LinkFailure {
  const LinkFailure({required this.code, required this.message});

  factory LinkFailure.fromJson(Json json) => LinkFailure(
    code: json['code'] as String,
    message: json['message'] as String,
  );

  final String code;

  /// `"<título>\n<detalle>"` o solo el título.
  final String message;

  Json toJson() => {'code': code, 'message': message};
}

/// Evento `link.finished`: uno por cada `link.import` al terminar.
class LinkFinished {
  const LinkFinished({
    required this.jobId,
    required this.duplicate,
    required this.notices,
    this.id,
    this.error,
  });

  factory LinkFinished.fromJson(Json json) => LinkFinished(
    jobId: json['jobId'] as String,
    id: json['id'] as String?,
    duplicate: json['duplicate'] as bool,
    notices: List.unmodifiable((json['notices'] as List<Object?>).cast<String>()),
    error: json['error'] == null
        ? null
        : LinkFailure.fromJson(json['error'] as Json),
  );

  final String jobId;

  /// UUID del proyecto. Ausente si hay [error].
  final String? id;
  final bool duplicate;

  /// Avisos no fatales de la descarga.
  final List<String> notices;

  /// Ausente si es nulo. Si se canceló, `code == "cancelled"`.
  final LinkFailure? error;

  Json toJson() => {
    'jobId': jobId,
    if (id != null) 'id': id,
    'duplicate': duplicate,
    'notices': notices,
    if (error != null) 'error': error?.toJson(),
  };
}
