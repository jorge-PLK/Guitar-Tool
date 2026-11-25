// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get commonAnchor => '';

  @override
  String get common_accept => 'Aceptar';

  @override
  String get common_cancel => 'Cancelar';

  @override
  String get common_delete => 'Borrar';

  @override
  String get shellAnchor => '';

  @override
  String get shell_appTitle => 'ToneForge';

  @override
  String get shell_logoForge => 'Forge';

  @override
  String get shell_logoTone => 'Tone';

  @override
  String get shell_navBacking => 'Backing track';

  @override
  String get shell_navLibrary => 'Biblioteca';

  @override
  String get shell_navMontage => 'Montaje';

  @override
  String get shell_navRecord => 'Grabar';

  @override
  String get shell_navSettings => 'Ajustes';

  @override
  String get shell_navTab => 'Tablatura';

  @override
  String get shell_selectedThemeHelp => 'Abrir la página del tema';

  @override
  String shell_selectedThemeLabel(String title) {
    return 'Tema seleccionado: $title';
  }

  @override
  String get libraryAnchor => '';

  @override
  String get library_artistsBack => 'Artistas';

  @override
  String library_artistTileLabel(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count temas',
      one: '1 tema',
    );
    return '$name, $_temp0';
  }

  @override
  String library_artistTrackCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count temas',
      one: '1 tema',
    );
    return '$_temp0';
  }

  @override
  String get library_cancel => 'Cancelar';

  @override
  String library_cleanConfirm(String bytes) {
    return 'Limpiar $bytes';
  }

  @override
  String library_cleanMessage(String bytes) {
    return 'Se borrarán tomas descartadas y stems por $bytes. Los stems se pueden volver a generar.';
  }

  @override
  String get library_cleanTitleAll => 'Limpiar toda la biblioteca';

  @override
  String library_cleanTitle(String title) {
    return 'Limpiar «$title»';
  }

  @override
  String get library_colSong => 'Tema / Artista';

  @override
  String get library_colState => 'Estado';

  @override
  String get library_colTakes => 'Tomas';

  @override
  String get library_deleteButton => 'Eliminar…';

  @override
  String get library_deleteLabel => 'Eliminar';

  @override
  String get library_deleteTooltip => 'Eliminar…';

  @override
  String get library_detailBack => 'Biblioteca';

  @override
  String get library_duplicateMessage =>
      'Ya hay un proyecto con el mismo audio (mismo SHA-256) o con el mismo vídeo de origen. ¿Quieres abrirlo?';

  @override
  String get library_duplicateOpen => 'Abrir el existente';

  @override
  String get library_duplicateTitle => 'Este tema ya está en la biblioteca';

  @override
  String get library_editSheetTitle => 'Corregir título y artista';

  @override
  String get library_editTooltip => 'Editar título y artista';

  @override
  String get library_emptyBody =>
      'Importa un wav, flac o mp3, arrástralo a esta ventana o pega un enlace de YouTube o Spotify.';

  @override
  String get library_emptyTitle => 'Todavía no hay temas';

  @override
  String get library_errBusy =>
      'El tema está ocupado (separándose o reconvirtiéndose).';

  @override
  String get library_errCancel => 'No se pudo cancelar';

  @override
  String get library_errClean => 'No se pudo limpiar';

  @override
  String get library_errDelete => 'No se pudo eliminar del disco';

  @override
  String get library_errDuplicate => 'Ese tema ya está en la biblioteca.';

  @override
  String library_errImportFile(String file) {
    return 'No se pudo importar $file';
  }

  @override
  String get library_errOpen => 'No se pudo abrir el tema';

  @override
  String get library_errProjectNotFound =>
      'No se encuentra el proyecto en la carpeta.';

  @override
  String get library_errSave => 'No se pudo guardar el título';

  @override
  String library_errSeparate(String title) {
    return 'No se pudo separar $title';
  }

  @override
  String get library_errSeparateBar => 'No se pudo separar';

  @override
  String get library_errTitleEmptyBody => 'El título no puede quedar vacío.';

  @override
  String get library_errTitleEmptyTitle => 'Falta el título';

  @override
  String library_errTrashBody(String error) {
    return '$error No se ha borrado nada; te queda «Eliminar del disco».';
  }

  @override
  String get library_errTrashTitleMac => 'No se pudo mover a la Papelera';

  @override
  String get library_errTrashTitleWindows =>
      'No se pudo mover a la Papelera de reciclaje';

  @override
  String get library_errUnsafeDeletion =>
      'La carpeta del tema no es un proyecto válido de la biblioteca; no se ha borrado nada.';

  @override
  String get library_errWorkInProgress =>
      'Hay una separación en curso o en cola.';

  @override
  String get library_fieldArtist => 'Artista';

  @override
  String get library_fieldTitle => 'Título';

  @override
  String get library_firstRunBody =>
      'Cada tema vive en su propia carpeta, con sus stems, tomas y vídeo. Puedes cambiarla más tarde en Ajustes.';

  @override
  String get library_firstRunChoose => 'Elegir carpeta…';

  @override
  String library_firstRunProposal(String path) {
    return 'Propuesta: $path';
  }

  @override
  String get library_firstRunTitle => 'Elige tu carpeta de proyectos';

  @override
  String get library_importAlreadyLatest =>
      'yt-dlp ya es la última versión: YouTube ha cambiado algo y hay que esperar a que se corrija. Mientras, importa el fichero a mano (Importar tema > Desde fichero…).';

  @override
  String get library_importButton => 'Importar tema';

  @override
  String get library_importCancel => 'Cancelar';

  @override
  String get library_importCandidatesLabel => 'CANDIDATOS EN YOUTUBE';

  @override
  String get library_importChipClose => 'cercano';

  @override
  String get library_importChipInLibrary => 'En la biblioteca';

  @override
  String get library_importChipLive => 'directo';

  @override
  String get library_importChoose => 'Elegir';

  @override
  String get library_importClose => 'Cerrar';

  @override
  String get library_importConverting => 'Convirtiendo a WAV…';

  @override
  String get library_importDone => 'Tema importado';

  @override
  String get library_importDownloading => 'Descargando audio…';

  @override
  String get library_importFailTitle => 'No se pudo importar';

  @override
  String get library_importFile => 'Importar fichero…';

  @override
  String get library_importGo => 'Importar';

  @override
  String get library_importImporting => 'Importando en la biblioteca…';

  @override
  String library_importing(String percent) {
    return 'Importando $percent';
  }

  @override
  String get library_importLinkHint => 'Pega un enlace o busca en Spotify';

  @override
  String get library_importListenTooltip => 'Oír en Spotify';

  @override
  String get library_importManualAdd => 'Añadir';

  @override
  String get library_importManualHint => 'https://www.youtube.com/watch?v=…';

  @override
  String get library_importManualLabel =>
      '¿Ninguno convence? Pega un enlace de YouTube';

  @override
  String library_importNoClose(int seconds) {
    return 'Ningún candidato queda a $seconds s o menos de la duración de Spotify. Elige con cuidado o pega a mano un enlace de YouTube.';
  }

  @override
  String get library_importNoResults =>
      'La búsqueda no ha dado resultados. Pega a mano un enlace de YouTube.';

  @override
  String get library_importOpen => 'Abrir';

  @override
  String get library_importOpenBrowser => 'Abrir en el navegador';

  @override
  String get library_importOtherLink => 'Probar con otro enlace';

  @override
  String get library_importPasteYt => 'Pegar un enlace de YouTube';

  @override
  String library_importPossible(String name) {
    return 'Puede que ya lo tengas: $name';
  }

  @override
  String get library_importPreparing => 'Preparando…';

  @override
  String get library_importReadingMeta => 'Leyendo metadatos…';

  @override
  String get library_importRepeatedBody => 'No se busca ni se descarga nada.';

  @override
  String get library_importRepeatedTitle => 'Ya está en la biblioteca';

  @override
  String get library_importRetry => 'Reintentar';

  @override
  String get library_importSearchingYt => 'Buscando en YouTube…';

  @override
  String get library_importSlow => 'Suele tardar unos 9 s.';

  @override
  String library_importSpotifyDuration(String duration) {
    return 'Spotify: $duration';
  }

  @override
  String library_importSpotifyNone(String query) {
    return 'Spotify no ha encontrado nada para «$query»';
  }

  @override
  String get library_importSupported =>
      'Se admiten enlaces de un vídeo de YouTube (youtube.com/watch, youtu.be, music.youtube.com) y de una canción de Spotify (open.spotify.com/track o spotify:track), además de listas de YouTube (youtube.com/playlist) y listas o álbumes de Spotify (open.spotify.com/playlist, open.spotify.com/album). Episodios no.';

  @override
  String get library_importTitleEmpty => 'Importar tema';

  @override
  String get library_importTitleLink => 'Importar desde enlace';

  @override
  String get library_importTitleList => 'Importar lista';

  @override
  String get library_importUpdateRetry => 'Actualizar y reintentar';

  @override
  String get library_importUpdating => 'Actualizando yt-dlp…';

  @override
  String get library_importVideoLabel => 'VÍDEO A IMPORTAR';

  @override
  String get library_infoDuration => 'Duración';

  @override
  String get library_infoRate => 'Frecuencia';

  @override
  String get library_infoState => 'Estado';

  @override
  String get library_menuCancelSeparation => 'Cancelar separación';

  @override
  String get library_menuClean => 'Limpiar…';

  @override
  String get library_menuDelete => 'Eliminar…';

  @override
  String get library_menuRevealMac => 'Mostrar en Finder';

  @override
  String get library_menuRevealWindows =>
      'Mostrar en el Explorador de archivos';

  @override
  String get library_menuSeparate => 'Separar de nuevo';

  @override
  String get library_noArtist => 'Sin artista';

  @override
  String library_noMatch(String query) {
    return 'Ningún tema coincide con «$query»';
  }

  @override
  String get library_noticeTitle => 'Aviso';

  @override
  String get library_noticeOk => 'Aceptar';

  @override
  String get library_openInBacking => 'Abrir en Backing track';

  @override
  String get library_playlistIndicatorTooltip =>
      'Ver la importación de la lista';

  @override
  String get library_plCancel => 'Cancelar';

  @override
  String get library_plCancelledTitle =>
      'Cola cancelada: lo ya importado se conserva';

  @override
  String get library_plCap =>
      'Spotify devuelve como máximo 100 temas por lista: puede haber cortado esta. Si faltan temas, impórtalos desde su enlace.';

  @override
  String get library_plChipDoubtful => 'dudoso';

  @override
  String get library_plChipMaybe => 'Puede que ya lo tengas';

  @override
  String library_plChoiceFailed(String title) {
    return 'Falló la búsqueda: $title';
  }

  @override
  String get library_plChoiceNoResults => 'Sin resultados: omitir';

  @override
  String get library_plChoicePending => 'Sin buscar';

  @override
  String get library_plChoicePick => 'Elige un candidato…';

  @override
  String get library_plChoiceSkipped => 'Omitido';

  @override
  String get library_plCloseTooltip => 'La cola sigue en segundo plano';

  @override
  String get library_plConverting => 'Convirtiendo…';

  @override
  String get library_plDefaultName => 'Lista';

  @override
  String get library_plDoneTitle => 'Importación terminada';

  @override
  String library_plDownload(int n) {
    return 'Descargar y procesar ($n)';
  }

  @override
  String get library_plDownloading => 'Descargando';

  @override
  String library_plDownloadingPercent(String percent) {
    return 'Descargando $percent';
  }

  @override
  String get library_plFailedHeader => 'FALLIDOS';

  @override
  String get library_plIndCancelled => 'Importación cancelada';

  @override
  String get library_plIndFinished => 'Importación terminada';

  @override
  String library_plIndImporting(int n, int total) {
    return 'Importando $n de $total';
  }

  @override
  String get library_plIndLoading => 'Leyendo la lista…';

  @override
  String library_plIndSearching(int n, int total) {
    return 'Buscando $n de $total';
  }

  @override
  String get library_plIndStopped => 'Importación detenida';

  @override
  String library_plInLibrarySuffix(String label) {
    return '$label · En la biblioteca';
  }

  @override
  String get library_plKeepSearching => 'Seguir buscando';

  @override
  String get library_plLatestKept =>
      'yt-dlp ya es la última versión: YouTube ha cambiado algo y hay que esperar a que se corrija. Lo ya importado se conserva.';

  @override
  String library_plMaybeTooltip(String title) {
    return 'Parecido a: $title';
  }

  @override
  String get library_plNothingYet =>
      'Nada se descarga todavía: después podrás revisar los candidatos.';

  @override
  String library_plOpenExisting(String title) {
    return 'Abrir «$title» en la biblioteca';
  }

  @override
  String get library_plQImported => 'Importado';

  @override
  String get library_plQInLibrary => 'En la biblioteca';

  @override
  String get library_plQQueued => 'En cola';

  @override
  String get library_plQSkipped => 'Omitido';

  @override
  String library_plQueueCount(int done, int total) {
    return '$done de $total temas';
  }

  @override
  String get library_plQueueStopped => 'Cola detenida';

  @override
  String get library_plQueueTitle => 'Descargando, importando y separando';

  @override
  String get library_plRateLimitedHint =>
      'No se reintenta sola: reanuda cuando quieras.';

  @override
  String get library_plResume => 'Reanudar';

  @override
  String library_plResumeN(int n) {
    return 'Reanudar ($n)';
  }

  @override
  String library_plRetryFailed(int n) {
    return 'Reintentar fallidos ($n)';
  }

  @override
  String get library_plReviewBanner =>
      'Revisa lo propuesto: nada se descarga hasta que pulses «Descargar y procesar». Los «dudosos» no tienen propuesta: elige uno o se omiten.';

  @override
  String library_plReviewSummary(int proposed, int doubtful, int skipped) {
    return '$proposed con candidato · $doubtful dudosos · $skipped omitidos';
  }

  @override
  String library_plSearch(int n) {
    return 'Buscar en YouTube ($n)';
  }

  @override
  String get library_plSearchingAll => 'Buscando cada tema en YouTube';

  @override
  String library_plSearchingN(int n, int total) {
    return 'Buscando $n de $total';
  }

  @override
  String get library_plSelectAll => 'Marcar todos';

  @override
  String get library_plSelectNone => 'Ninguno';

  @override
  String get library_plSeparatingNote =>
      'Los temas importados se están separando en stems; verás el avance en la Biblioteca.';

  @override
  String get library_plSkipItem => 'Omitir este tema';

  @override
  String get library_plStatFailed => 'Fallidos';

  @override
  String get library_plStatImported => 'Importados';

  @override
  String get library_plStatInLibrary => 'Ya en la biblioteca';

  @override
  String get library_plStatSkipped => 'Omitidos';

  @override
  String library_plSummary(int total, int selected) {
    return '$total temas · $selected marcados';
  }

  @override
  String library_plSummaryInLibrary(int n) {
    return ' · $n ya en la biblioteca';
  }

  @override
  String get library_plUpdateRetry => 'Actualizar y reintentar';

  @override
  String get library_plUpdating => 'Actualizando…';

  @override
  String get library_recordingsNone => 'Este tema aún no tiene tomas grabadas.';

  @override
  String get library_recordingsTitle => 'Grabaciones';

  @override
  String get library_revealButtonMac => 'Mostrar en Finder';

  @override
  String get library_revealButtonWindows =>
      'Mostrar en el Explorador de archivos';

  @override
  String get library_revealTooltipMac => 'Mostrar en Finder';

  @override
  String get library_revealTooltipWindows =>
      'Mostrar en el Explorador de archivos';

  @override
  String get library_save => 'Guardar';

  @override
  String get library_searchClear => 'Borrar búsqueda';

  @override
  String get library_searchHint => 'Buscar tema o artista';

  @override
  String get library_srcAgeRestrictedDetail =>
      'Vídeo con restricción de edad: no se puede descargar sin cuenta.';

  @override
  String get library_srcAgeRestrictedTitle => 'Vídeo con restricción de edad';

  @override
  String get library_srcCancelledTitle => 'Cancelado';

  @override
  String get library_srcChecksumDetail =>
      'La suma SHA-256 del yt-dlp descargado no coincide. No se ha instalado nada.';

  @override
  String get library_srcChecksumTitle => 'Actualización rechazada';

  @override
  String get library_srcExtractorBrokenDetail =>
      'YouTube ha cambiado algo y yt-dlp no sabe leerlo.';

  @override
  String get library_srcExtractorBrokenTitle =>
      'yt-dlp puede estar desactualizado';

  @override
  String library_srcExtractorBrokenTitleVersion(String version) {
    return 'yt-dlp puede estar desactualizado (versión $version)';
  }

  @override
  String get library_srcFfmpegFailedTitle => 'Falló la conversión';

  @override
  String library_srcHelperMissingDetail(String name) {
    return 'No se encuentra «$name» dentro de la app. Reinstala ToneForge.';
  }

  @override
  String get library_srcHelperMissingTitle => 'Falta un componente';

  @override
  String library_srcHttpStatusDetail(int code) {
    return 'El servidor respondió con el código $code.';
  }

  @override
  String get library_srcHttpStatusTitle => 'Respuesta inesperada';

  @override
  String get library_srcLaunchFailedTitle => 'No se pudo lanzar el proceso';

  @override
  String get library_srcNoAudioFormatDetail =>
      'Este vídeo no ofrece audio descargable.';

  @override
  String get library_srcNoAudioFormatTitle => 'Sin audio descargable';

  @override
  String get library_srcNoAudioProducedDetail =>
      'yt-dlp terminó pero no dejó ningún fichero de audio.';

  @override
  String get library_srcNoAudioProducedTitle => 'Sin audio';

  @override
  String get library_srcOfflineDetail =>
      'No se ha podido conectar. Comprueba la red y reintenta.';

  @override
  String get library_srcOfflineTitle => 'Sin conexión';

  @override
  String get library_srcPrivateDetail => 'Este vídeo es privado.';

  @override
  String get library_srcPrivateTitle => 'Vídeo privado';

  @override
  String get library_srcRateLimitedDetail =>
      'YouTube ha limitado las peticiones; espera unos minutos y reintenta.';

  @override
  String get library_srcRateLimitedTitle =>
      'YouTube ha limitado las peticiones';

  @override
  String get library_srcRegionDetail =>
      'Este vídeo no está disponible en tu país.';

  @override
  String get library_srcRegionTitle => 'No disponible en tu región';

  @override
  String get library_srcRemovedDetail =>
      'Este vídeo se ha retirado o ya no está disponible.';

  @override
  String get library_srcRemovedTitle => 'Vídeo no disponible';

  @override
  String get library_srcSpotifyUnreadableDetail =>
      'Pega un enlace de YouTube del tema en su lugar.';

  @override
  String get library_srcSpotifyUnreadableTitle =>
      'No se han podido leer los datos de Spotify';

  @override
  String get library_srcTimedOutDetail =>
      'El servidor tarda demasiado en responder. Reintenta.';

  @override
  String get library_srcTimedOutTitle => 'Tiempo agotado';

  @override
  String get library_srcUnsupportedTitle => 'Enlace no admitido';

  @override
  String get library_srcUpdateFailedTitle => 'No se pudo actualizar yt-dlp';

  @override
  String get library_stateDetailDone => 'Separado';

  @override
  String library_stateDetailFailed(String message) {
    return 'Error: $message';
  }

  @override
  String get library_stateDetailFailedUnknown => 'desconocido';

  @override
  String get library_stateDetailImported => 'Importado';

  @override
  String get library_stateDetailQueued => 'En cola';

  @override
  String get library_stateDetailRunning => 'Separando';

  @override
  String get library_stateDone => 'Separado';

  @override
  String get library_stateFailed => 'Error';

  @override
  String get library_stateFailedUnknown => 'Error desconocido';

  @override
  String get library_stateImported => 'Importado';

  @override
  String get library_stateQueued => 'En cola';

  @override
  String library_stateRunning(String percent) {
    return 'Separando $percent';
  }

  @override
  String get library_stemEmpty => 'vacío';

  @override
  String get library_stemsNone => 'Sin stems todavía.';

  @override
  String get library_stemsTitle => 'Stems';

  @override
  String get library_subtitle => 'Tus temas.';

  @override
  String get library_swapTooltip => 'Intercambiar título y artista';

  @override
  String get library_takeBest => 'Mejor toma';

  @override
  String library_takeBestError(String error) {
    return 'No se pudo marcar la toma como mejor ($error).';
  }

  @override
  String get library_takeDelete => 'Eliminar';

  @override
  String library_takeDeleteConfirm(String label) {
    return 'Eliminar $label';
  }

  @override
  String library_takeDeleteError(String error) {
    return 'No se pudo eliminar la toma ($error).';
  }

  @override
  String get library_takeDeleteMessage =>
      'Se borra su carpeta (audio y vídeo). No se puede deshacer.';

  @override
  String get library_takeDeleteTitle => '¿Eliminar la toma?';

  @override
  String library_takeLabel(int n, String part) {
    return 'Toma $n · $part';
  }

  @override
  String get library_takeNoDuration => '–';

  @override
  String get library_takeNoVideo => 'Sin vídeo';

  @override
  String library_takeNumber(int n) {
    return 'Toma $n';
  }

  @override
  String library_takePunches(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count punches',
      one: '1 punch',
    );
    return '$_temp0';
  }

  @override
  String get library_takesNone => '—';

  @override
  String get library_takeView => 'Ver toma';

  @override
  String get library_takeWithVideo => 'Con vídeo';

  @override
  String get library_title => 'Biblioteca';

  @override
  String library_trashContentsStems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count stems',
      one: '1 stem',
      zero: 'sus stems',
    );
    return '$_temp0';
  }

  @override
  String library_trashContentsTakes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tomas',
      one: '1 toma',
    );
    return '$_temp0';
  }

  @override
  String library_trashContentsVideos(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count vídeos',
      one: '1 vídeo',
    );
    return '$_temp0';
  }

  @override
  String get library_trashDelete => 'Eliminar del disco';

  @override
  String library_trashMessageMac(String contents) {
    return 'Se va con el tema: $contents. Si se está separando o está abierto en Backing, se detiene primero.\nEliminar del disco no se puede deshacer. La Papelera conserva la carpeta hasta que la vacíes.';
  }

  @override
  String library_trashMessageWindows(String contents) {
    return 'Se va con el tema: $contents. Si se está separando o está abierto en Backing, se detiene primero.\nEliminar del disco no se puede deshacer. La Papelera de reciclaje conserva la carpeta hasta que la vacíes.';
  }

  @override
  String library_trashTitle(String title) {
    return '¿Eliminar “$title”?';
  }

  @override
  String get library_trashToBinMac => 'Mover a la Papelera';

  @override
  String get library_trashToBinWindows => 'Mover a la Papelera de reciclaje';

  @override
  String get library_viewArtists => 'Artistas';

  @override
  String get library_viewLabel => 'Vista';

  @override
  String get library_viewSongs => 'Temas';

  @override
  String get backingAnchor => '';

  @override
  String get tabAnchor => '';

  @override
  String get recordAnchor => '';

  @override
  String get montageAnchor => '';

  @override
  String get settingsAnchor => '';

  @override
  String get settings_lang_en => 'English';

  @override
  String get settings_lang_es => 'Español';

  @override
  String get settings_lang_label => 'Idioma';

  @override
  String get settings_lang_system => 'Sistema';

  @override
  String get settings_lang_title => 'Idioma';

  @override
  String get settings_lib_cancel => 'Cancelar';

  @override
  String get settings_lib_change => 'Cambiar carpeta';

  @override
  String get settings_lib_clean => 'Limpiar tomas descartadas y stems';

  @override
  String get settings_lib_cleanTitle => 'Limpiar toda la biblioteca';

  @override
  String get settings_lib_folder => 'Carpeta de proyectos';

  @override
  String get settings_lib_moveHere => 'Mover los temas aquí';

  @override
  String settings_lib_moving(String percent) {
    return 'Moviendo $percent';
  }

  @override
  String get settings_lib_note =>
      'Una carpeta por tema, con sus stems, tomas y vídeo.';

  @override
  String get settings_lib_pointOnly => 'Solo apuntar a esta carpeta';

  @override
  String settings_lib_relocateMessage(String path) {
    return '«$path»: ¿mover los temas existentes a la carpeta nueva o solo apuntar a ella?';
  }

  @override
  String get settings_lib_title => 'Biblioteca';

  @override
  String get settings_lib_usage => 'Espacio usado';

  @override
  String get settings_lib_workInProgress =>
      'Hay trabajo en curso. Espera a que terminen las separaciones y vuelve a cambiar la carpeta.';

  @override
  String get settings_models_delete => 'Borrar';

  @override
  String get settings_models_deleteMessage =>
      'Se volverá a descargar la próxima vez que separes un tema.';

  @override
  String get settings_models_deleteTitle => 'Borrar el modelo';

  @override
  String get settings_models_download => 'Descargar';

  @override
  String settings_models_downloading(String percent) {
    return 'Descargando $percent';
  }

  @override
  String get settings_models_error => 'Error';

  @override
  String settings_models_installed(String size) {
    return 'Descargado · $size';
  }

  @override
  String get settings_models_installing => 'Instalando…';

  @override
  String get settings_models_note => 'Se descargan la primera vez que se usan.';

  @override
  String settings_models_pending(String size) {
    return 'Pendiente · $size';
  }

  @override
  String get settings_models_title => 'Modelos';

  @override
  String get settings_models_verifying => 'Verificando…';

  @override
  String get settings_subtitle =>
      'Se configura una vez y lo usan todas las pantallas. Se guarda en tu perfil de equipo.';

  @override
  String get settings_tabAudio => 'Audio';

  @override
  String get settings_tabLibrary => 'Biblioteca';

  @override
  String get settings_tabVideo => 'Cámara y vídeo';

  @override
  String get settings_tools_checking => 'comprobando…';

  @override
  String get settings_tools_embedded => 'embebida';

  @override
  String get settings_tools_note =>
      'Importar desde enlace usa yt-dlp, Deno y ffmpeg, que van dentro de la app. Si YouTube cambia y las descargas fallan, actualiza yt-dlp.';

  @override
  String get settings_tools_revert => 'Volver a la embebida';

  @override
  String get settings_tools_title => 'Fuentes externas';

  @override
  String get settings_tools_unavailable => 'no disponible';

  @override
  String get settings_tools_update => 'Actualizar yt-dlp';

  @override
  String get settings_tools_updated => 'actualizada';

  @override
  String settings_tools_updateDone(String version) {
    return 'yt-dlp actualizado a $version.';
  }

  @override
  String settings_tools_upToDate(String version) {
    return 'Ya tienes la última versión ($version).';
  }

  @override
  String get errorAnchor => '';

  @override
  String get error_unknown => 'Error desconocido';
}
