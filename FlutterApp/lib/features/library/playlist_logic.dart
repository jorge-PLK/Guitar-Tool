import 'package:toneforge/contract/playlist.dart';

/// Recuentos y botones de la hoja de lista, derivados del snapshot (sin textos).
/// Las fórmulas vienen de `PlaylistImportView` (`PlaylistImport.swift:281-546`).

/// «{total} temas · {marcados} marcados[ · {n} ya en la biblioteca]».
typedef TracksCounts = ({int total, int selected, int inLibrary});

/// «{n} con candidato · {n} dudosos · {n} omitidos».
typedef ReviewCounts = ({int proposed, int doubtful, int skipped});

/// «{hechos} de {total} temas».
typedef QueueCounts = ({int done, int total});

/// Cuatro cifras del resumen (duplicados ya repartidos por el núcleo).
typedef SummaryCounts = ({int imported, int skipped, int inLibrary, int failed});

/// «Buscando {current} de {total}».
typedef SearchProgress = ({int current, int done, int total, double fraction});

TracksCounts tracksCounts(PlaylistSnapshot s) =>
    (total: s.totals.total, selected: s.totals.selected, inLibrary: s.totals.inLibrary);

/// Temas de la revisión: marcados y sin terminar de importar.
List<PlaylistItemInfo> reviewItems(PlaylistSnapshot s) => [
  for (final i in s.items)
    if (i.selected && i.status != PlaylistItemStatus.imported && i.status != PlaylistItemStatus.inLibrary) i,
];

ReviewCounts reviewCounts(PlaylistSnapshot s) {
  final items = reviewItems(s);
  int n(PlaylistItemStatus st) => items.where((i) => i.status == st).length;
  return (
    proposed: n(PlaylistItemStatus.proposed),
    doubtful: n(PlaylistItemStatus.doubtful),
    skipped: n(PlaylistItemStatus.skipped),
  );
}

/// Hay marcados de Spotify aún sin buscar (visible «Seguir buscando»).
bool hasUnsearched(PlaylistSnapshot s) => reviewItems(s).any(
  (i) => i.status == PlaylistItemStatus.pending && i.chosen == null && i.kind == PlaylistSource.spotify,
);

SearchProgress searchProgress(PlaylistSnapshot s) {
  final done = s.searchDone ?? 0;
  final total = s.searchTotal ?? 0;
  return (
    current: (done + 1).clamp(1, total < 1 ? 1 : total),
    done: done,
    total: total,
    fraction: total == 0 ? 0 : done / total,
  );
}

QueueCounts queueCounts(PlaylistSnapshot s) =>
    (done: s.totals.selected - s.totals.remaining, total: s.totals.selected);

/// Filas de la cola: los temas marcados.
List<PlaylistItemInfo> queueItems(PlaylistSnapshot s) => [
  for (final i in s.items)
    if (i.selected) i,
];

SummaryCounts summaryCounts(PlaylistSnapshot s) =>
    (imported: s.summary.imported, skipped: s.summary.skipped, inLibrary: s.summary.inLibrary, failed: s.summary.failed);

List<PlaylistItemInfo> failedItems(PlaylistSnapshot s) => [
  for (final i in s.items)
    if (i.status == PlaylistItemStatus.failed) i,
];

/// Botones de cada paso. «Cerrar» está siempre; en cola, con tooltip «La cola sigue en segundo plano».
class PlaylistButtons {
  const PlaylistButtons({
    this.markAll = false,
    this.markNone = false,
    this.showContinue = false,
    this.continueEnabled = false,
    this.continueCount = 0,
    this.continueIsSearch = false,
    this.showSearchMore = false,
    this.showStart = false,
    this.startEnabled = false,
    this.startCount = 0,
    this.showCancel = false,
    this.showResume = false,
    this.resumeCount,
    this.showUpdateAndRetry = false,
    this.updateEnabled = false,
    this.showRetryFailed = false,
    this.retryFailedCount = 0,
    this.showTryAnother = false,
    this.closeKeepsQueue = false,
  });

  /// «Marcar todos» y «Ninguno» (paso Elegir temas).
  final bool markAll;
  final bool markNone;

  /// «Descargar y procesar (N)» (YouTube) o «Buscar en YouTube (N)»: llama a `continue`.
  final bool showContinue;
  final bool continueEnabled;
  final int continueCount;
  final bool continueIsSearch;

  /// «Seguir buscando» (Revisar).
  final bool showSearchMore;

  /// «Descargar y procesar (N)» (Revisar): llama a `start`.
  final bool showStart;
  final bool startEnabled;
  final int startCount;

  /// «Cancelar» (Leyendo, Buscando, Cola en marcha).
  final bool showCancel;

  /// «Reanudar» (Cola detenida, sin cifra) o «Reanudar (N)» (Resumen cancelado).
  final bool showResume;
  final int? resumeCount;

  /// «Actualizar y reintentar» / «Actualizando…» (deshabilitado mientras actualiza).
  final bool showUpdateAndRetry;
  final bool updateEnabled;

  /// «Reintentar fallidos (N)».
  final bool showRetryFailed;
  final int retryFailedCount;

  /// «Probar con otro enlace» (Error de lista).
  final bool showTryAnother;

  /// Tooltip «La cola sigue en segundo plano» en «Cerrar».
  final bool closeKeepsQueue;
}

PlaylistButtons buttonsFor(PlaylistSnapshot s) {
  switch (s.step) {
    case PlaylistStep.loading:
    case PlaylistStep.searching:
      return const PlaylistButtons(showCancel: true);
    case PlaylistStep.tracks:
      final sel = s.totals.selected;
      return PlaylistButtons(
        markAll: true,
        markNone: true,
        showContinue: true,
        continueEnabled: sel > 0,
        continueCount: sel,
        continueIsSearch: s.source != PlaylistSource.youtube,
      );
    case PlaylistStep.review:
      return PlaylistButtons(
        showSearchMore: hasUnsearched(s),
        showStart: true,
        startEnabled: s.totals.queued > 0,
        startCount: s.totals.queued,
      );
    case PlaylistStep.running:
      return const PlaylistButtons(showCancel: true, closeKeepsQueue: true);
    case PlaylistStep.stopped:
      final suggests = s.error?.suggestsUpdate ?? false;
      return PlaylistButtons(
        closeKeepsQueue: true,
        showUpdateAndRetry: suggests && !s.update.alreadyLatest,
        updateEnabled: !s.update.updating,
        showResume: !suggests,
      );
    case PlaylistStep.summary:
      final failed = failedItems(s).length;
      final resumable = s.summary.cancelled && s.summary.remaining > 0;
      return PlaylistButtons(
        showResume: resumable,
        resumeCount: resumable ? s.summary.remaining : null,
        showRetryFailed: failed > 0,
        retryFailedCount: failed,
      );
    case PlaylistStep.error:
      return const PlaylistButtons(showTryAnother: true);
    case PlaylistStep.unknown:
      return const PlaylistButtons();
  }
}
