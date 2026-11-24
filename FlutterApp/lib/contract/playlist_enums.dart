/// Paso de la sesión de lista (`PlaylistSnapshot.step`). Valor no previsto → [unknown].
enum PlaylistStep {
  loading('loading'),
  tracks('tracks'),
  searching('searching'),
  review('review'),
  running('running'),
  stopped('stopped'),
  summary('summary'),
  error('error'),
  unknown('unknown');

  const PlaylistStep(this.raw);

  /// Valor crudo del contrato.
  final String raw;

  static PlaylistStep fromRaw(String raw) => values.firstWhere(
    (v) => v != PlaylistStep.unknown && v.raw == raw,
    orElse: () => PlaylistStep.unknown,
  );
}

/// Origen de la lista y de cada tema (`source` y `kind` del ítem). Valor no previsto → [unknown].
enum PlaylistSource {
  spotify('spotify'),
  youtube('youtube'),
  unknown('unknown');

  const PlaylistSource(this.raw);

  /// Valor crudo del contrato.
  final String raw;

  static PlaylistSource fromRaw(String raw) => values.firstWhere(
    (v) => v != PlaylistSource.unknown && v.raw == raw,
    orElse: () => PlaylistSource.unknown,
  );
}

/// Tipo de colección (`PlaylistSnapshot.kind`). Valor no previsto → [unknown].
enum PlaylistKind {
  playlist('playlist'),
  album('album'),
  unknown('unknown');

  const PlaylistKind(this.raw);

  /// Valor crudo del contrato.
  final String raw;

  static PlaylistKind fromRaw(String raw) => values.firstWhere(
    (v) => v != PlaylistKind.unknown && v.raw == raw,
    orElse: () => PlaylistKind.unknown,
  );
}

/// Estado de un tema (`PlaylistItemInfo.status`). Valor no previsto → [unknown].
enum PlaylistItemStatus {
  pending('pending'),
  searching('searching'),
  proposed('proposed'),
  doubtful('doubtful'),
  downloading('downloading'),
  imported('imported'),
  skipped('skipped'),
  inLibrary('inLibrary'),
  failed('failed'),
  unknown('unknown');

  const PlaylistItemStatus(this.raw);

  /// Valor crudo del contrato.
  final String raw;

  static PlaylistItemStatus fromRaw(String raw) => values.firstWhere(
    (v) => v != PlaylistItemStatus.unknown && v.raw == raw,
    orElse: () => PlaylistItemStatus.unknown,
  );
}

/// Fase de un tema en descarga (`PlaylistItemInfo.stage`). Valor no previsto → [unknown].
enum PlaylistItemStage {
  download('download'),
  convert('convert'),
  unknown('unknown');

  const PlaylistItemStage(this.raw);

  /// Valor crudo del contrato.
  final String raw;

  static PlaylistItemStage fromRaw(String raw) => values.firstWhere(
    (v) => v != PlaylistItemStage.unknown && v.raw == raw,
    orElse: () => PlaylistItemStage.unknown,
  );
}
