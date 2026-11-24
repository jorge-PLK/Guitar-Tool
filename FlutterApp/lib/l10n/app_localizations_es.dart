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
  String get record_addPart => 'Añadir parte';

  @override
  String get record_addPartAdd => 'Añadir';

  @override
  String get record_addPartName => 'Nombre de la parte';

  @override
  String get record_addPartNone => 'Ninguna (parte añadida)';

  @override
  String get record_addPartReplaces => 'Guitarra que sustituye';

  @override
  String get record_addPartTitle => 'Añadir parte';

  @override
  String get record_blockMarkPunch =>
      'Marca la entrada y la salida del punch-in en la línea de tiempo.';

  @override
  String get record_blockPickPart => 'Elige una parte.';

  @override
  String get record_blockPickTake =>
      'Elige la toma sobre la que hacer el punch-in.';

  @override
  String record_cameraAudioOnly(String message) {
    return '$message Se grabará solo el audio.';
  }

  @override
  String get record_cameraDenied =>
      'Sin permiso de cámara: se grabará solo el audio. Concédelo en Ajustes del Sistema > Privacidad > Cámara.';

  @override
  String get record_cameraMissing =>
      'La cámara elegida en Ajustes no está conectada.';

  @override
  String get record_cameraNone => 'No hay ninguna cámara conectada.';

  @override
  String record_cameraOpenFailed(String error) {
    return 'No se pudo abrir la cámara ($error).';
  }

  @override
  String get record_cameraUnplugged =>
      'Se desconectó la cámara: se grabará solo el audio.';

  @override
  String get record_cancel => 'Cancelar';

  @override
  String get record_chooserEmpty =>
      'Aún no hay temas separados. Importa uno y sepáralo en la biblioteca.';

  @override
  String get record_chooserPick => 'Elige un tema';

  @override
  String get record_countIn => 'Cuenta de 1 compás';

  @override
  String get record_deleteBody =>
      'Se borra su carpeta (audio y vídeo). No se puede deshacer.';

  @override
  String get record_deleteConfirm => 'Borrar toma';

  @override
  String get record_deleteTitle => '¿Borrar la toma?';

  @override
  String get record_durationHelpAuto =>
      'Para sola al acabar la sección más el margen';

  @override
  String get record_durationHelpTheme => 'Duración del tema';

  @override
  String record_errDelete(String error) {
    return 'No se pudo borrar la toma ($error).';
  }

  @override
  String get record_errDeviceClosed => 'El dispositivo no está abierto.';

  @override
  String record_errPriorTakes(String error) {
    return 'No se pudieron cargar tus tomas anteriores ($error).';
  }

  @override
  String get record_errPunchTake => 'No se encontró la toma del punch.';

  @override
  String get record_errSave => 'No se pudo guardar la toma.';

  @override
  String get record_errStart => 'No se pudo empezar a grabar.';

  @override
  String record_errStems(String error) {
    return 'No se pudieron cargar los stems ($error).';
  }

  @override
  String record_errTake(String error) {
    return 'No se pudo grabar la toma ($error).';
  }

  @override
  String get record_faderA11y => 'Volumen';

  @override
  String get record_goLibrary => 'Ir a la biblioteca';

  @override
  String get record_goMontage => 'Ir al montaje';

  @override
  String get record_goMontageHelp => 'Monta las mejores tomas en un vídeo';

  @override
  String get record_headerMulti => 'Multitoma';

  @override
  String get record_inputLevelA11y => 'Nivel de la entrada de guitarra';

  @override
  String get record_inputWord => 'Entrada';

  @override
  String get record_master => 'Master';

  @override
  String get record_menuBest => 'Marcar como mejor';

  @override
  String get record_menuDelete => 'Borrar…';

  @override
  String get record_menuOffset => 'Ajustar desfase…';

  @override
  String get record_menuPunch => 'Punch-in';

  @override
  String get record_mixerExpand => 'Expandir';

  @override
  String get record_mixerExpandA11y => 'Expandir el mezclador';

  @override
  String get record_mixerFold => 'Plegar';

  @override
  String get record_mixerFoldA11y => 'Plegar el mezclador';

  @override
  String record_mixerOutput(String device) {
    return 'Salida: $device';
  }

  @override
  String get record_mixerTitle => 'Mezclador';

  @override
  String record_muteA11y(String name) {
    return 'Silenciar $name';
  }

  @override
  String get record_muted => 'Silenciado';

  @override
  String get record_notSeparatedBody =>
      'Grabar necesita los stems. Sepáralo desde la biblioteca y vuelve.';

  @override
  String get record_notSeparatedTitle => 'Este tema aún no está separado';

  @override
  String get record_noticeNoFrames =>
      'No llegaron fotogramas de la cámara: la toma es solo de audio.';

  @override
  String get record_noticeStopped =>
      'La toma se detuvo y se guardó lo grabado.';

  @override
  String get record_offsetDiscard => 'Descartar toma';

  @override
  String record_offsetFrameNote(int ms) {
    return 'Fotograma = $ms ms';
  }

  @override
  String get record_offsetHelp =>
      'Dale al play y mueve el desfase hasta que imagen y sonido coincidan (un golpe seco en las cuerdas ayuda). Positivo = la imagen llega tarde.';

  @override
  String record_offsetLoadError(String error) {
    return 'No se pudo abrir la toma ($error).';
  }

  @override
  String record_offsetMakeDefault(String camera) {
    return 'Guardar como desfase por defecto de esta cámara ($camera)';
  }

  @override
  String get record_offsetMinusFrame => '−1 fotograma';

  @override
  String get record_offsetMinusMs => '−1 ms';

  @override
  String get record_offsetMsA11y => 'Desfase en milisegundos';

  @override
  String get record_offsetPlayPause => 'Reproducir / pausa';

  @override
  String get record_offsetPlusFrame => '+1 fotograma';

  @override
  String get record_offsetPlusMs => '+1 ms';

  @override
  String get record_offsetRestart => 'Al principio';

  @override
  String get record_offsetSave => 'Guardar';

  @override
  String get record_offsetSaveTake => 'Guardar toma';

  @override
  String get record_offsetTitle => 'Ajustar desfase';

  @override
  String get record_offsetUnit => 'ms';

  @override
  String get record_offsetUnset => 'Desfase de la cámara: sin ajustar';

  @override
  String record_offsetValue(String ms) {
    return 'Desfase de la cámara: $ms ms';
  }

  @override
  String get record_partAdded => 'Parte añadida';

  @override
  String record_partReplaces(String guitar) {
    return 'Sustituye: $guitar';
  }

  @override
  String get record_parts => 'Partes';

  @override
  String get record_partsHelp =>
      'En cada toma suena el backing sin esa parte y con tus tomas anteriores.';

  @override
  String get record_preRoll => 'Margen';

  @override
  String get record_preRoll0 => 'Sin margen';

  @override
  String get record_preRoll1 => '1 compás';

  @override
  String get record_preRoll2 => '2 compases';

  @override
  String get record_previewNoVideo => 'Sin vídeo: se grabará solo el audio';

  @override
  String record_previewSimulated(String camera) {
    return 'Vista previa de la cámara · $camera (simulada)';
  }

  @override
  String get record_punchEntryA11y => 'Entrada del punch-in';

  @override
  String get record_punchExitA11y => 'Salida del punch-in';

  @override
  String get record_punchHelp_mac =>
      'Haz clic para marcar la entrada y después la salida; arrastra las marcas para moverlas (⌥ = libre, sin imán al compás).';

  @override
  String get record_punchHelp_win =>
      'Haz clic para marcar la entrada y después la salida; arrastra las marcas para moverlas (Alt = libre, sin imán al compás).';

  @override
  String record_punchSummary(String entry, String exit) {
    return 'Entrada $entry · Salida $exit';
  }

  @override
  String get record_punchTitle => 'Punch-in';

  @override
  String get record_punchToggle => 'Punch-in';

  @override
  String get record_punchToggleHelp => 'Vuelve a grabar un tramo de una toma';

  @override
  String get record_recPrefix => 'REC · ';

  @override
  String get record_rotate => 'Rotar';

  @override
  String record_rotateA11y(int degrees) {
    return 'Rotar cámara, ahora $degrees grados';
  }

  @override
  String record_rotateDegrees(int degrees) {
    return 'Rotar · $degrees°';
  }

  @override
  String get record_rotateHelp =>
      'Gira la imagen de esta cámara 90° en sentido horario (no se recodifica; se aplica al ver y montar)';

  @override
  String record_soloA11y(String name) {
    return 'Solo $name';
  }

  @override
  String get record_start => 'Grabar';

  @override
  String get record_startAt => 'Empezar en';

  @override
  String get record_startBeginning => 'Principio';

  @override
  String get record_statusDone => 'Hecha';

  @override
  String get record_statusPending => 'Pendiente';

  @override
  String get record_statusRecording => 'Grabando';

  @override
  String get record_stemBass => 'Bajo';

  @override
  String get record_stemDrums => 'Batería';

  @override
  String get record_stemGuitar => 'Guitarra';

  @override
  String get record_stemOther => 'Resto';

  @override
  String get record_stemPiano => 'Piano';

  @override
  String get record_stemVocals => 'Voz';

  @override
  String get record_stop => 'Parar';

  @override
  String get record_stopA11y => 'Parar la grabación';

  @override
  String record_take(int n) {
    return 'Toma $n';
  }

  @override
  String record_takeA11y(int n) {
    return 'Toma $n';
  }

  @override
  String record_takeA11yBest(int n) {
    return 'Toma $n, mejor';
  }

  @override
  String record_takeBest(int n) {
    return 'Toma $n · mejor';
  }

  @override
  String record_takePill(int n, String part) {
    return 'Toma $n · $part';
  }

  @override
  String get record_title => 'Grabar';

  @override
  String get record_uncalibrated =>
      'Sin calibrar: la toma puede ir desfasada decenas de ms; se corregirá al calibrar.';

  @override
  String record_unmuteA11y(String name) {
    return 'Activar $name';
  }

  @override
  String get record_viewTake => 'Ver toma';

  @override
  String record_viewTakeA11y(int n) {
    return 'Ver toma $n';
  }

  @override
  String record_viewerTitle(int n, String part) {
    return 'Toma $n · $part';
  }

  @override
  String get record_yourGuitar => 'Tu guitarra';

  @override
  String get takeview_backing => 'Backing';

  @override
  String get takeview_backingMuteHelp => 'Silenciar el backing';

  @override
  String get takeview_backingMuted => 'Backing mudo';

  @override
  String get takeview_backingUnmuteHelp => 'Oír el backing';

  @override
  String get takeview_bestChip => '★ mejor';

  @override
  String get takeview_close => 'Cerrar';

  @override
  String get takeview_delete => 'Eliminar…';

  @override
  String get takeview_deleteBody =>
      'Se borra su carpeta (audio y vídeo). No se puede deshacer.';

  @override
  String get takeview_deleteConfirm => 'Eliminar toma';

  @override
  String get takeview_deleteTitle => '¿Eliminar la toma?';

  @override
  String takeview_errInnerAudio(String file) {
    return 'no se pudo leer el audio $file';
  }

  @override
  String get takeview_errInnerNoAudio => 'la toma no tiene audio procesado';

  @override
  String get takeview_errNoAudio => 'Esta toma no tiene audio que reproducir.';

  @override
  String takeview_errPrepare(String error) {
    return 'No se pudo preparar la toma ($error).';
  }

  @override
  String get takeview_markBest => 'Marcar como mejor';

  @override
  String get takeview_noVideo => 'Sin vídeo: solo audio';

  @override
  String get takeview_pause => 'Pausa';

  @override
  String get takeview_play => 'Reproducir';

  @override
  String get takeview_position => 'Posición';

  @override
  String get record_block_busy =>
      'Hay una calibración o una grabación en marcha.';

  @override
  String get record_block_invalidChannels =>
      'Los canales elegidos se repiten: revisa Ajustes · Audio.';

  @override
  String get record_block_inputDisconnected =>
      'El dispositivo de entrada no está conectado.';

  @override
  String get record_block_loop => 'Solo se graba sin bucle: quita el bucle.';

  @override
  String get record_block_noGuitarInput =>
      'Asigna la entrada de guitarra en Ajustes · Audio.';

  @override
  String get record_block_noInputDevice =>
      'Elige un dispositivo de entrada en Ajustes · Audio.';

  @override
  String get record_block_noPart => 'Elige una parte.';

  @override
  String get record_block_outputDisconnected =>
      'El dispositivo de salida no está conectado.';

  @override
  String get record_block_punchNoMarks =>
      'Marca la entrada y la salida del punch-in en la línea de tiempo.';

  @override
  String get record_block_punchNoTake =>
      'Elige la toma sobre la que hacer el punch-in.';

  @override
  String record_block_rateMismatch(num deviceHz, num workingHz) {
    return 'El dispositivo está a $deviceHz kHz y la frecuencia de trabajo es $workingHz kHz';
  }

  @override
  String record_block_sessionUnavailable(String detail) {
    return '$detail';
  }

  @override
  String record_block_speed(num rate) {
    return 'Solo se graba a velocidad 100 %: pon el tempo al 100 %.';
  }

  @override
  String get settingsAudioAnchor => '';

  @override
  String settings_audio_backingChoice(String l, String r) {
    return 'Salidas $l y $r · estéreo';
  }

  @override
  String get settings_audio_backingOut => 'Salida del backing';

  @override
  String get settings_audio_block_busy =>
      'Hay una calibración o una grabación en marcha.';

  @override
  String get settings_audio_block_invalidChannels =>
      'Los canales elegidos se repiten: revisa Ajustes · Audio.';

  @override
  String get settings_audio_block_inputDisconnected =>
      'El dispositivo de entrada no está conectado.';

  @override
  String get settings_audio_block_loop =>
      'Solo se graba sin bucle: quita el bucle.';

  @override
  String get settings_audio_block_noGuitarInput =>
      'Asigna la entrada de guitarra en Ajustes · Audio.';

  @override
  String get settings_audio_block_noInputDevice =>
      'Elige un dispositivo de entrada en Ajustes · Audio.';

  @override
  String get settings_audio_block_outputDisconnected =>
      'El dispositivo de salida no está conectado.';

  @override
  String settings_audio_block_rateMismatch(num deviceHz, num workingHz) {
    return 'El dispositivo está a $deviceHz kHz y la frecuencia de trabajo es $workingHz kHz';
  }

  @override
  String settings_audio_block_sessionUnavailable(String detail) {
    return '$detail';
  }

  @override
  String settings_audio_block_speed(num rate) {
    return 'Solo se graba a velocidad 100 %: pon el tempo al 100 %.';
  }

  @override
  String get settings_audio_calibrate => 'Calibrar latencia';

  @override
  String settings_audio_calibrated(num ms, String date) {
    return 'Calibrada · $ms ms · $date';
  }

  @override
  String get settings_audio_calNote =>
      'Un pulso de prueba mide el retardo de ida y vuelta del dispositivo.';

  @override
  String get settings_audio_calTitle => 'Calibración';

  @override
  String get settings_audio_channelsNote =>
      'Qué entra y qué sale por cada canal del dispositivo.';

  @override
  String get settings_audio_channelsTitle => 'Canales';

  @override
  String get settings_audio_chosenFallback => 'Dispositivo elegido';

  @override
  String settings_audio_deviceDisconnected(String name) {
    return '$name · desconectado';
  }

  @override
  String get settings_audio_deviceNote =>
      'Por dónde suena el backing y por dónde entra tu guitarra.';

  @override
  String settings_audio_deviceOption(String name, int channels) {
    return '$name · $channels can.';
  }

  @override
  String get settings_audio_deviceTitle => 'Dispositivo';

  @override
  String get settings_audio_guitarIn => 'Entrada de guitarra';

  @override
  String get settings_audio_input => 'Dispositivo de entrada';

  @override
  String settings_audio_inputN(int n) {
    return 'Entrada $n';
  }

  @override
  String settings_audio_inputsNM(int n, int m) {
    return 'Entradas $n y $m';
  }

  @override
  String get settings_audio_latency => 'Latencia';

  @override
  String get settings_audio_noInput => 'Ninguna';

  @override
  String get settings_audio_output => 'Dispositivo de salida';

  @override
  String get settings_audio_rate => 'Frecuencia de trabajo';

  @override
  String settings_audio_rateMismatch(String device, String working) {
    return 'El dispositivo está a $device y la frecuencia de trabajo es $working';
  }

  @override
  String get settings_audio_rateMismatchHint =>
      'Grabar y calibrar quedan bloqueados; el backing suena igual.';

  @override
  String get settings_audio_systemOutput => 'Salida del sistema';

  @override
  String get settings_audio_unassigned => 'Sin asignar';

  @override
  String get settings_audio_uncalibrated => 'Sin calibrar';

  @override
  String settings_audio_useRate(String rate) {
    return 'Usar $rate como frecuencia de trabajo';
  }

  @override
  String get settings_cal_cancel => 'Cancelar';

  @override
  String get settings_cal_close => 'Cerrar';

  @override
  String settings_cal_correctedNote(int n) {
    return '$n de este tema, hechas sin calibrar';
  }

  @override
  String get settings_cal_done => 'Calibrada';

  @override
  String get settings_cal_errorTitle => 'No se pudo calibrar';

  @override
  String get settings_cal_noSignalHint =>
      'Comprueba el cable de una salida del dispositivo a la entrada de guitarra, y que la entrada elegida sea esa. Después repite.';

  @override
  String get settings_cal_noSignalTitle => 'No llegó la señal de prueba';

  @override
  String get settings_cal_retry => 'Repetir';

  @override
  String get settings_cal_rigNone =>
      'sin canal de referencia: la latencia calibrada vale tal cual';

  @override
  String settings_cal_rigNote(num ms) {
    return '$ms ms · se corregirá en cada toma';
  }

  @override
  String get settings_cal_rowCorrected => 'Tomas corregidas';

  @override
  String get settings_cal_rowLatency => 'Latencia';

  @override
  String get settings_cal_rowRig => 'Retardo del rig';

  @override
  String get settings_cal_rowSpread => 'Dispersión';

  @override
  String get settings_cal_running =>
      'Midiendo… no toques la guitarra ni muevas el cable.';

  @override
  String get settings_cal_saturatedHint =>
      'Baja el volumen de salida del dispositivo (con una pedalera, el del rig o el de la salida) y repite.';

  @override
  String get settings_cal_saturatedTitle => 'La señal llegó saturada';

  @override
  String get settings_cal_start => 'Empezar';

  @override
  String get settings_cal_step1 =>
      'Conecta con un cable una salida del dispositivo a su entrada de guitarra.';

  @override
  String get settings_cal_step2 =>
      'Con una pedalera, carga un rig vacío y baja el volumen de salida: el bucle realimenta (entrada, rig, salida, cable, entrada).';

  @override
  String get settings_cal_step3 =>
      'La prueba son 10 pitidos agudos en unos 5 segundos. Mide el retardo de ida y vuelta, que es el desfase que tendrá una toma respecto al backing que se oye.';

  @override
  String get settings_cal_title => 'Calibrar latencia';

  @override
  String get settings_cal_unstableHint =>
      'Carga un rig vacío o sin delay ni reverb, cierra otras apps de audio y repite.';

  @override
  String settings_cal_unstableTitle(num ms) {
    return 'Las medidas no coinciden entre sí (dispersión de $ms ms)';
  }

  @override
  String get settingsVideoAnchor => '';

  @override
  String get settings_video_camera => 'Cámara';

  @override
  String settings_video_cameraDisconnected(String name) {
    return '$name · desconectada';
  }

  @override
  String get settings_video_cameraTitle => 'Cámara';

  @override
  String get settings_video_chosenFallback => 'Cámara elegida';

  @override
  String get settings_video_chosenOff => 'La cámara elegida está desconectada.';

  @override
  String get settings_video_denied =>
      'ToneForge no tiene permiso para usar la cámara.';

  @override
  String get settings_video_exportNote => 'Se puede cambiar en cada montaje.';

  @override
  String get settings_video_exportTitle => 'Exportación por defecto';

  @override
  String get settings_video_format => 'Formato de vídeo';

  @override
  String get settings_video_fps => 'Fotogramas por segundo';

  @override
  String settings_video_inUse(String name) {
    return 'En uso: $name.';
  }

  @override
  String get settings_video_none => 'No hay ninguna cámara conectada.';

  @override
  String get settings_video_offset => 'Desfase por defecto de esta cámara';

  @override
  String settings_video_openFailed(String error) {
    return 'No se pudo abrir la cámara ($error).';
  }

  @override
  String get settings_video_openSystem_mac => 'Abrir Ajustes del Sistema';

  @override
  String get settings_video_openSystem_win => 'Abrir Configuración';

  @override
  String get settings_video_resolution => 'Resolución';

  @override
  String get settings_video_simulated => 'Vista previa simulada';

  @override
  String get settings_video_stemWavs => 'WAV de cada pista';

  @override
  String get settings_video_syncNote =>
      'Se ajusta al terminar cada toma; este es el valor con el que empieza la siguiente.';

  @override
  String get settings_video_syncTitle => 'Sincronía';

  @override
  String get settings_video_systemDefault => 'Por defecto del sistema';

  @override
  String get settings_video_titleOverlay => 'Rótulo con el título del tema';

  @override
  String get settings_video_volume => 'Volumen';

  @override
  String get settings_video_volumeValue => 'normalizado a −14 LUFS';

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
  String get errorAnchor => '';

  @override
  String get error_unknown => 'Error desconocido';
}
