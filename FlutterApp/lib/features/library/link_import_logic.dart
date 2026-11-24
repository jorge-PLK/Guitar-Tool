import 'package:toneforge/contract/jobs.dart';
import 'package:toneforge/contract/link_import.dart';
import 'package:toneforge/contract/link_resolve.dart';
import 'package:toneforge/contract/playlist_snapshot.dart';
import 'package:toneforge/core/core_client.dart';

const Object _keep = Object();

/// Pantalla de la hoja «Importar tema / desde enlace» (`LinkImportSession.Screen`).
enum LinkImportScreen { empty, resolving, preparing, candidates, working, error, done, repeated, playlist }

/// Qué se está haciendo mientras se resuelve. El núcleo no emite fases: es
/// `metadata` para un enlace de YouTube y `searching` para uno de Spotify (que
/// además busca en YouTube; «Suele tardar unos 9 s.»).
enum LinkResolvePhase { metadata, searching }

/// Etiqueta de la pantalla «Trabajando» (se traduce en la vista).
enum LinkWorkPhase { updating, downloading, converting, importing }

/// Acción del botón principal de la pantalla de error. Null en el estado = ninguna.
enum LinkErrorAction { updateAndRetry, tryOtherLink, pasteYoutube, retry }

/// Códigos tras los que la hoja vuelve a los candidatos (`SourceError.returnsToCandidates`).
const Set<String> linkReturnsToCandidates = {
  'age-restricted',
  'region',
  'private-video',
  'removed',
  'no-audio-format',
};

/// Error mostrado. `message` es `«título\ndetalle»` o solo título; la vista traduce por `code`.
class LinkImportError {
  const LinkImportError({required this.code, required this.message});

  factory LinkImportError.fromCore(CoreError e) => LinkImportError(code: e.code, message: e.message);

  final String code;
  final String message;

  /// Ofrece «Actualizar y reintentar» (`SourceError.suggestsYtDlpUpdate`).
  bool get suggestsUpdate => code == 'extractor-broken';

  bool get returnsToCandidates => linkReturnsToCandidates.contains(code);
}

/// Estado de la hoja. Inmutable.
class LinkImportState {
  const LinkImportState({
    this.screen = LinkImportScreen.empty,
    this.text = '',
    this.searching = false,
    this.passRunning = false,
    this.spotifyQuery,
    this.spotifyTracks,
    this.spotifyError,
    this.resolvePhase = LinkResolvePhase.metadata,
    this.resolved,
    this.title = '',
    this.artist = '',
    this.selectedId,
    this.manualError,
    this.jobId,
    this.progress,
    this.workPhase = LinkWorkPhase.downloading,
    this.notices = const [],
    this.error,
    this.alreadyLatest = false,
    this.duplicateOf,
    this.importedId,
    this.playlist,
  });

  final LinkImportScreen screen;

  /// Texto del campo de enlace.
  final String text;

  /// `link.search` en curso (spinner del campo).
  final bool searching;

  /// Una pasada (clasificar, resolver, añadir, importar, actualizar) en curso.
  final bool passRunning;

  /// Consulta y resultados de Spotify (null = sin resultados que mostrar).
  final String? spotifyQuery;
  final List<LinkSpotifyTrack>? spotifyTracks;
  final CoreError? spotifyError;

  final LinkResolvePhase resolvePhase;

  /// Última `link.resolve` (portada, existente, candidatos). Null antes de resolver.
  final LinkResolveResult? resolved;
  final String title;
  final String artist;
  final String? selectedId;
  final CoreError? manualError;

  /// Trabajo `link-N` propio; fracción (null = indeterminada) y etiqueta de fase.
  final String? jobId;
  final double? progress;
  final LinkWorkPhase workPhase;

  /// Avisos de la importación terminada (pantalla `done`).
  final List<String> notices;

  /// Error de la pantalla `error`; en `candidates` es el banner de error.
  final LinkImportError? error;

  /// Tras «Actualizar y reintentar»: yt-dlp ya era la última versión.
  final bool alreadyLatest;

  /// Id del tema existente cuando `link.finished` llegó con `duplicate:true`:
  /// la vista cierra la hoja y enseña la alerta; luego `dismissDuplicate()`.
  final String? duplicateOf;

  /// Id del tema importado (`link.finished` ok).
  final String? importedId;

  /// Lista o álbum resuelto (`screen == playlist`): lo adopta `playlistStore`.
  final PlaylistSnapshot? playlist;

  bool get busy => passRunning || searching;

  /// Primer candidato si es la confirmación de un vídeo único (`isClose` sin `difference`).
  LinkCandidateInfo? get confirmation {
    final c = resolved?.candidates;
    if (c == null || c.isEmpty) return null;
    return c.first.isClose && c.first.difference == null ? c.first : null;
  }

  /// Candidato a importar: la confirmación, o el elegido si no está en la biblioteca.
  LinkCandidateInfo? get selectedCandidate {
    final c = confirmation;
    if (c != null) return c;
    for (final x in resolved?.candidates ?? const <LinkCandidateInfo>[]) {
      if (x.id == selectedId && x.inLibrary == null) return x;
    }
    return null;
  }

  LinkTrackInfo? get existing => resolved?.existing;
  LinkTrackInfo? get possibleDuplicate => resolved?.possibleDuplicate;

  bool get canCancel => screen != LinkImportScreen.working ||
      (workPhase != LinkWorkPhase.updating && workPhase != LinkWorkPhase.importing);

  /// «Importar» del campo vacío.
  bool get canSubmit => !busy && text.trim().isNotEmpty;

  /// «Importar» de candidatos.
  bool get canImport => !busy && selectedCandidate != null && title.trim().isNotEmpty;

  /// Botón principal de la pantalla de error (null = ninguno).
  LinkErrorAction? get errorAction {
    final e = error;
    if (e == null) return null;
    if (e.suggestsUpdate && !alreadyLatest) return LinkErrorAction.updateAndRetry;
    if (e.code == 'unsupported-link') return LinkErrorAction.tryOtherLink;
    if (e.code == 'spotify-unreadable') return LinkErrorAction.pasteYoutube;
    return alreadyLatest ? null : LinkErrorAction.retry;
  }

  LinkImportState copyWith({
    LinkImportScreen? screen,
    String? text,
    bool? searching,
    bool? passRunning,
    Object? spotifyQuery = _keep,
    Object? spotifyTracks = _keep,
    Object? spotifyError = _keep,
    LinkResolvePhase? resolvePhase,
    Object? resolved = _keep,
    String? title,
    String? artist,
    Object? selectedId = _keep,
    Object? manualError = _keep,
    Object? jobId = _keep,
    Object? progress = _keep,
    LinkWorkPhase? workPhase,
    List<String>? notices,
    Object? error = _keep,
    bool? alreadyLatest,
    Object? duplicateOf = _keep,
    Object? importedId = _keep,
    Object? playlist = _keep,
  }) => LinkImportState(
    screen: screen ?? this.screen,
    text: text ?? this.text,
    searching: searching ?? this.searching,
    passRunning: passRunning ?? this.passRunning,
    spotifyQuery: identical(spotifyQuery, _keep) ? this.spotifyQuery : spotifyQuery as String?,
    spotifyTracks: identical(spotifyTracks, _keep)
        ? this.spotifyTracks
        : spotifyTracks as List<LinkSpotifyTrack>?,
    spotifyError: identical(spotifyError, _keep) ? this.spotifyError : spotifyError as CoreError?,
    resolvePhase: resolvePhase ?? this.resolvePhase,
    resolved: identical(resolved, _keep) ? this.resolved : resolved as LinkResolveResult?,
    title: title ?? this.title,
    artist: artist ?? this.artist,
    selectedId: identical(selectedId, _keep) ? this.selectedId : selectedId as String?,
    manualError: identical(manualError, _keep) ? this.manualError : manualError as CoreError?,
    jobId: identical(jobId, _keep) ? this.jobId : jobId as String?,
    progress: identical(progress, _keep) ? this.progress : progress as double?,
    workPhase: workPhase ?? this.workPhase,
    notices: notices ?? this.notices,
    error: identical(error, _keep) ? this.error : error as LinkImportError?,
    alreadyLatest: alreadyLatest ?? this.alreadyLatest,
    duplicateOf: identical(duplicateOf, _keep) ? this.duplicateOf : duplicateOf as String?,
    importedId: identical(importedId, _keep) ? this.importedId : importedId as String?,
    playlist: identical(playlist, _keep) ? this.playlist : playlist as PlaylistSnapshot?,
  );
}

/// Etiqueta de trabajo a partir de `jobs.progress` (el núcleo no manda la fase por separado):
/// etapa `import` → importando; `download` con texto «Convirtiendo…» → convirtiendo; si no, descargando.
LinkWorkPhase workPhaseOf(JobInfo j) {
  if (j.stage == JobStage.importStage) return LinkWorkPhase.importing;
  return j.text.startsWith('Convirtiendo') ? LinkWorkPhase.converting : LinkWorkPhase.downloading;
}
