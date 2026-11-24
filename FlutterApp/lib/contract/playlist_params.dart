import '../core/core_client.dart' show Json;

/// Parámetros de `playlist.skip` (solo `id` del tema).
class PlaylistItemParams {
  const PlaylistItemParams({required this.id});

  factory PlaylistItemParams.fromJson(Json json) =>
      PlaylistItemParams(id: json['id'] as String);

  /// Id de tema de la lista.
  final String id;

  Json toJson() => {'id': id};
}

/// Parámetros de `playlist.select`.
class PlaylistSelectParams {
  const PlaylistSelectParams({required this.id, required this.selected});

  factory PlaylistSelectParams.fromJson(Json json) => PlaylistSelectParams(
    id: json['id'] as String,
    selected: json['selected'] as bool,
  );

  final String id;
  final bool selected;

  Json toJson() => {'id': id, 'selected': selected};
}

/// Parámetros de `playlist.choose`.
class PlaylistChooseParams {
  const PlaylistChooseParams({required this.id, required this.candidateId});

  factory PlaylistChooseParams.fromJson(Json json) => PlaylistChooseParams(
    id: json['id'] as String,
    candidateId: json['candidateId'] as String,
  );

  final String id;

  /// Id de vídeo de YouTube del candidato elegido.
  final String candidateId;

  Json toJson() => {'id': id, 'candidateId': candidateId};
}

/// Parámetros de `playlist.close`. Ausente = `false`.
class PlaylistCloseParams {
  const PlaylistCloseParams({this.force});

  factory PlaylistCloseParams.fromJson(Json json) =>
      PlaylistCloseParams(force: json['force'] as bool?);

  /// Ausente si es nulo.
  final bool? force;

  Json toJson() => {if (force != null) 'force': force};
}

/// Resultado de `playlist.close` (no es un `PlaylistSnapshot`).
/// Sin sesión: `closed:false, live:false`. Viva sin `force`: `closed:false, live:true`.
class PlaylistCloseResult {
  const PlaylistCloseResult({required this.closed, required this.live});

  factory PlaylistCloseResult.fromJson(Json json) => PlaylistCloseResult(
    closed: json['closed'] as bool,
    live: json['live'] as bool,
  );

  final bool closed;
  final bool live;

  Json toJson() => {'closed': closed, 'live': live};
}
