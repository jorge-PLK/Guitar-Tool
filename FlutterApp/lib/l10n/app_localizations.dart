import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
  ];

  /// Ancla del bloque common: añade las claves del área debajo, en orden alfabético; no edites otros bloques.
  ///
  /// In es, this message translates to:
  /// **''**
  String get commonAnchor;

  /// No description provided for @common_accept.
  ///
  /// In es, this message translates to:
  /// **'Aceptar'**
  String get common_accept;

  /// No description provided for @common_cancel.
  ///
  /// In es, this message translates to:
  /// **'Cancelar'**
  String get common_cancel;

  /// No description provided for @common_delete.
  ///
  /// In es, this message translates to:
  /// **'Borrar'**
  String get common_delete;

  /// Ancla del bloque shell: añade las claves del área debajo, en orden alfabético; no edites otros bloques.
  ///
  /// In es, this message translates to:
  /// **''**
  String get shellAnchor;

  /// No description provided for @shell_appTitle.
  ///
  /// In es, this message translates to:
  /// **'ToneForge'**
  String get shell_appTitle;

  /// No description provided for @shell_logoForge.
  ///
  /// In es, this message translates to:
  /// **'Forge'**
  String get shell_logoForge;

  /// No description provided for @shell_logoTone.
  ///
  /// In es, this message translates to:
  /// **'Tone'**
  String get shell_logoTone;

  /// No description provided for @shell_navBacking.
  ///
  /// In es, this message translates to:
  /// **'Backing track'**
  String get shell_navBacking;

  /// No description provided for @shell_navLibrary.
  ///
  /// In es, this message translates to:
  /// **'Biblioteca'**
  String get shell_navLibrary;

  /// No description provided for @shell_navMontage.
  ///
  /// In es, this message translates to:
  /// **'Montaje'**
  String get shell_navMontage;

  /// No description provided for @shell_navRecord.
  ///
  /// In es, this message translates to:
  /// **'Grabar'**
  String get shell_navRecord;

  /// No description provided for @shell_navSettings.
  ///
  /// In es, this message translates to:
  /// **'Ajustes'**
  String get shell_navSettings;

  /// No description provided for @shell_navTab.
  ///
  /// In es, this message translates to:
  /// **'Tablatura'**
  String get shell_navTab;

  /// No description provided for @shell_selectedThemeHelp.
  ///
  /// In es, this message translates to:
  /// **'Abrir la página del tema'**
  String get shell_selectedThemeHelp;

  /// No description provided for @shell_selectedThemeLabel.
  ///
  /// In es, this message translates to:
  /// **'Tema seleccionado: {title}'**
  String shell_selectedThemeLabel(String title);

  /// Ancla del bloque library: añade las claves del área debajo, en orden alfabético; no edites otros bloques.
  ///
  /// In es, this message translates to:
  /// **''**
  String get libraryAnchor;

  /// Artistas: botón atrás de la vista de artista.
  ///
  /// In es, this message translates to:
  /// **'Artistas'**
  String get library_artistsBack;

  /// Artistas: etiqueta de accesibilidad de la tarjeta.
  ///
  /// In es, this message translates to:
  /// **'{name}, {count, plural, one{1 tema} other{{count} temas}}'**
  String library_artistTileLabel(String name, int count);

  /// Artistas: número de temas de un artista.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, one{1 tema} other{{count} temas}}'**
  String library_artistTrackCount(int count);

  /// Detalle: botón cancelar la edición.
  ///
  /// In es, this message translates to:
  /// **'Cancelar'**
  String get library_cancel;

  /// Diálogos y avisos: botón de confirmar limpieza.
  ///
  /// In es, this message translates to:
  /// **'Limpiar {bytes}'**
  String library_cleanConfirm(String bytes);

  /// Diálogos y avisos: cuerpo de la limpieza.
  ///
  /// In es, this message translates to:
  /// **'Se borrarán tomas descartadas y stems por {bytes}. Los stems se pueden volver a generar.'**
  String library_cleanMessage(String bytes);

  /// Cabecera: título del diálogo de limpieza de un tema.
  ///
  /// In es, this message translates to:
  /// **'Limpiar «{title}»'**
  String library_cleanTitle(String title);

  /// Cabecera: columna (se pinta en mayúsculas).
  ///
  /// In es, this message translates to:
  /// **'Tema / Artista'**
  String get library_colSong;

  /// Cabecera: columna (se pinta en mayúsculas).
  ///
  /// In es, this message translates to:
  /// **'Estado'**
  String get library_colState;

  /// Cabecera: columna (se pinta en mayúsculas).
  ///
  /// In es, this message translates to:
  /// **'Tomas'**
  String get library_colTakes;

  /// Detalle: botón eliminar.
  ///
  /// In es, this message translates to:
  /// **'Eliminar…'**
  String get library_deleteButton;

  /// Cabecera: etiqueta de eliminar (accesibilidad).
  ///
  /// In es, this message translates to:
  /// **'Eliminar'**
  String get library_deleteLabel;

  /// Cabecera: tooltip del botón eliminar.
  ///
  /// In es, this message translates to:
  /// **'Eliminar…'**
  String get library_deleteTooltip;

  /// Detalle: botón atrás.
  ///
  /// In es, this message translates to:
  /// **'Biblioteca'**
  String get library_detailBack;

  /// Diálogos y avisos: cuerpo de tema duplicado.
  ///
  /// In es, this message translates to:
  /// **'Ya hay un proyecto con el mismo audio (mismo SHA-256) o con el mismo vídeo de origen. ¿Quieres abrirlo?'**
  String get library_duplicateMessage;

  /// Diálogos y avisos: botón abrir el duplicado.
  ///
  /// In es, this message translates to:
  /// **'Abrir el existente'**
  String get library_duplicateOpen;

  /// Diálogos y avisos: título de tema duplicado.
  ///
  /// In es, this message translates to:
  /// **'Este tema ya está en la biblioteca'**
  String get library_duplicateTitle;

  /// Hoja de corrección: título de la hoja.
  ///
  /// In es, this message translates to:
  /// **'Corregir título y artista'**
  String get library_editSheetTitle;

  /// Cabecera: tooltip del botón editar.
  ///
  /// In es, this message translates to:
  /// **'Editar título y artista'**
  String get library_editTooltip;

  /// Cabecera: texto de la lista vacía.
  ///
  /// In es, this message translates to:
  /// **'Importa un wav, flac o mp3, arrástralo a esta ventana o pega un enlace de YouTube o Spotify.'**
  String get library_emptyBody;

  /// Cabecera: título de la lista vacía.
  ///
  /// In es, this message translates to:
  /// **'Todavía no hay temas'**
  String get library_emptyTitle;

  /// Diálogos y avisos: tema ocupado.
  ///
  /// In es, this message translates to:
  /// **'El tema está ocupado (separándose o reconvirtiéndose).'**
  String get library_errBusy;

  /// Diálogos y avisos: error al cancelar.
  ///
  /// In es, this message translates to:
  /// **'No se pudo cancelar'**
  String get library_errCancel;

  /// Diálogos y avisos: error al limpiar.
  ///
  /// In es, this message translates to:
  /// **'No se pudo limpiar'**
  String get library_errClean;

  /// Diálogos y avisos: error al eliminar del disco.
  ///
  /// In es, this message translates to:
  /// **'No se pudo eliminar del disco'**
  String get library_errDelete;

  /// Diálogos y avisos: tema duplicado.
  ///
  /// In es, this message translates to:
  /// **'Ese tema ya está en la biblioteca.'**
  String get library_errDuplicate;

  /// Diálogos y avisos: error al importar un fichero.
  ///
  /// In es, this message translates to:
  /// **'No se pudo importar {file}'**
  String library_errImportFile(String file);

  /// Diálogos y avisos: error al abrir un tema.
  ///
  /// In es, this message translates to:
  /// **'No se pudo abrir el tema'**
  String get library_errOpen;

  /// Diálogos y avisos: proyecto no encontrado.
  ///
  /// In es, this message translates to:
  /// **'No se encuentra el proyecto en la carpeta.'**
  String get library_errProjectNotFound;

  /// Diálogos y avisos: error al guardar el título.
  ///
  /// In es, this message translates to:
  /// **'No se pudo guardar el título'**
  String get library_errSave;

  /// Diálogos y avisos: error al separar un tema.
  ///
  /// In es, this message translates to:
  /// **'No se pudo separar {title}'**
  String library_errSeparate(String title);

  /// Diálogos y avisos: error al separar en la lista de la barra (sin título).
  ///
  /// In es, this message translates to:
  /// **'No se pudo separar'**
  String get library_errSeparateBar;

  /// Diálogos y avisos: cuerpo de error de título vacío.
  ///
  /// In es, this message translates to:
  /// **'El título no puede quedar vacío.'**
  String get library_errTitleEmptyBody;

  /// Diálogos y avisos: título de error de título vacío.
  ///
  /// In es, this message translates to:
  /// **'Falta el título'**
  String get library_errTitleEmptyTitle;

  /// Diálogos y avisos: cuerpo de error de papelera.
  ///
  /// In es, this message translates to:
  /// **'{error} No se ha borrado nada; te queda «Eliminar del disco».'**
  String library_errTrashBody(String error);

  /// Diálogos y avisos: título de error de papelera (macOS).
  ///
  /// In es, this message translates to:
  /// **'No se pudo mover a la Papelera'**
  String get library_errTrashTitleMac;

  /// Diálogos y avisos: título de error de papelera (Windows).
  ///
  /// In es, this message translates to:
  /// **'No se pudo mover a la Papelera de reciclaje'**
  String get library_errTrashTitleWindows;

  /// Diálogos y avisos: borrado bloqueado por seguridad.
  ///
  /// In es, this message translates to:
  /// **'La carpeta del tema no es un proyecto válido de la biblioteca; no se ha borrado nada.'**
  String get library_errUnsafeDeletion;

  /// Diálogos y avisos: trabajo en curso.
  ///
  /// In es, this message translates to:
  /// **'Hay una separación en curso o en cola.'**
  String get library_errWorkInProgress;

  /// Hoja de corrección: campo artista.
  ///
  /// In es, this message translates to:
  /// **'Artista'**
  String get library_fieldArtist;

  /// Hoja de corrección: campo título.
  ///
  /// In es, this message translates to:
  /// **'Título'**
  String get library_fieldTitle;

  /// Primer arranque: explicación de la carpeta.
  ///
  /// In es, this message translates to:
  /// **'Cada tema vive en su propia carpeta, con sus stems, tomas y vídeo. Puedes cambiarla más tarde en Ajustes.'**
  String get library_firstRunBody;

  /// Primer arranque: botón elegir carpeta.
  ///
  /// In es, this message translates to:
  /// **'Elegir carpeta…'**
  String get library_firstRunChoose;

  /// Primer arranque: ruta propuesta.
  ///
  /// In es, this message translates to:
  /// **'Propuesta: {path}'**
  String library_firstRunProposal(String path);

  /// Primer arranque: título.
  ///
  /// In es, this message translates to:
  /// **'Elige tu carpeta de proyectos'**
  String get library_firstRunTitle;

  /// Importación: aviso de yt-dlp ya actualizado.
  ///
  /// In es, this message translates to:
  /// **'yt-dlp ya es la última versión: YouTube ha cambiado algo y hay que esperar a que se corrija. Mientras, importa el fichero a mano (Importar tema > Desde fichero…).'**
  String get library_importAlreadyLatest;

  /// Cabecera: botón para importar.
  ///
  /// In es, this message translates to:
  /// **'Importar tema'**
  String get library_importButton;

  /// Importación: botón cancelar.
  ///
  /// In es, this message translates to:
  /// **'Cancelar'**
  String get library_importCancel;

  /// Importación: cabecera de sección (mayúsculas).
  ///
  /// In es, this message translates to:
  /// **'CANDIDATOS EN YOUTUBE'**
  String get library_importCandidatesLabel;

  /// Importación: chip de candidato cercano.
  ///
  /// In es, this message translates to:
  /// **'cercano'**
  String get library_importChipClose;

  /// Importación: chip de candidato ya en la biblioteca.
  ///
  /// In es, this message translates to:
  /// **'En la biblioteca'**
  String get library_importChipInLibrary;

  /// Importación: chip de versión en directo.
  ///
  /// In es, this message translates to:
  /// **'directo'**
  String get library_importChipLive;

  /// Importación: botón elegir candidato.
  ///
  /// In es, this message translates to:
  /// **'Elegir'**
  String get library_importChoose;

  /// Importación: botón cerrar.
  ///
  /// In es, this message translates to:
  /// **'Cerrar'**
  String get library_importClose;

  /// Importación: fase convirtiendo.
  ///
  /// In es, this message translates to:
  /// **'Convirtiendo a WAV…'**
  String get library_importConverting;

  /// Importación: estado terminado.
  ///
  /// In es, this message translates to:
  /// **'Tema importado'**
  String get library_importDone;

  /// Importación: fase descargando.
  ///
  /// In es, this message translates to:
  /// **'Descargando audio…'**
  String get library_importDownloading;

  /// Importación: título de error.
  ///
  /// In es, this message translates to:
  /// **'No se pudo importar'**
  String get library_importFailTitle;

  /// Importación: botón importar fichero.
  ///
  /// In es, this message translates to:
  /// **'Importar fichero…'**
  String get library_importFile;

  /// Importación: botón importar.
  ///
  /// In es, this message translates to:
  /// **'Importar'**
  String get library_importGo;

  /// Importación: fase importando.
  ///
  /// In es, this message translates to:
  /// **'Importando en la biblioteca…'**
  String get library_importImporting;

  /// Cabecera: progreso de importación en la fila.
  ///
  /// In es, this message translates to:
  /// **'Importando {percent}'**
  String library_importing(String percent);

  /// Importación: pista del campo de enlace.
  ///
  /// In es, this message translates to:
  /// **'Pega un enlace o busca en Spotify'**
  String get library_importLinkHint;

  /// Importación: tooltip de escuchar en Spotify.
  ///
  /// In es, this message translates to:
  /// **'Oír en Spotify'**
  String get library_importListenTooltip;

  /// Importación: botón añadir enlace manual.
  ///
  /// In es, this message translates to:
  /// **'Añadir'**
  String get library_importManualAdd;

  /// Importación: ejemplo en el campo manual.
  ///
  /// In es, this message translates to:
  /// **'https://www.youtube.com/watch?v=…'**
  String get library_importManualHint;

  /// Importación: etiqueta del campo manual.
  ///
  /// In es, this message translates to:
  /// **'¿Ninguno convence? Pega un enlace de YouTube'**
  String get library_importManualLabel;

  /// Importación: aviso de ningún candidato cercano.
  ///
  /// In es, this message translates to:
  /// **'Ningún candidato queda a {seconds} s o menos de la duración de Spotify. Elige con cuidado o pega a mano un enlace de YouTube.'**
  String library_importNoClose(int seconds);

  /// Importación: sin candidatos.
  ///
  /// In es, this message translates to:
  /// **'La búsqueda no ha dado resultados. Pega a mano un enlace de YouTube.'**
  String get library_importNoResults;

  /// Importación: botón abrir el existente.
  ///
  /// In es, this message translates to:
  /// **'Abrir'**
  String get library_importOpen;

  /// Importación: botón abrir en el navegador.
  ///
  /// In es, this message translates to:
  /// **'Abrir en el navegador'**
  String get library_importOpenBrowser;

  /// Importación: botón de error (también en la lista).
  ///
  /// In es, this message translates to:
  /// **'Probar con otro enlace'**
  String get library_importOtherLink;

  /// Importación: botón de error.
  ///
  /// In es, this message translates to:
  /// **'Pegar un enlace de YouTube'**
  String get library_importPasteYt;

  /// Importación: aviso de posible duplicado.
  ///
  /// In es, this message translates to:
  /// **'Puede que ya lo tengas: {name}'**
  String library_importPossible(String name);

  /// Importación: estado preparando.
  ///
  /// In es, this message translates to:
  /// **'Preparando…'**
  String get library_importPreparing;

  /// Importación: estado leyendo metadatos.
  ///
  /// In es, this message translates to:
  /// **'Leyendo metadatos…'**
  String get library_importReadingMeta;

  /// Importación: cuerpo de enlace repetido.
  ///
  /// In es, this message translates to:
  /// **'No se busca ni se descarga nada.'**
  String get library_importRepeatedBody;

  /// Importación: título de enlace repetido.
  ///
  /// In es, this message translates to:
  /// **'Ya está en la biblioteca'**
  String get library_importRepeatedTitle;

  /// Importación: botón reintentar.
  ///
  /// In es, this message translates to:
  /// **'Reintentar'**
  String get library_importRetry;

  /// Importación: estado buscando en YouTube.
  ///
  /// In es, this message translates to:
  /// **'Buscando en YouTube…'**
  String get library_importSearchingYt;

  /// Importación: aviso de tiempo de búsqueda.
  ///
  /// In es, this message translates to:
  /// **'Suele tardar unos 9 s.'**
  String get library_importSlow;

  /// Importación: duración de referencia de Spotify.
  ///
  /// In es, this message translates to:
  /// **'Spotify: {duration}'**
  String library_importSpotifyDuration(String duration);

  /// Importación: sin resultados en Spotify.
  ///
  /// In es, this message translates to:
  /// **'Spotify no ha encontrado nada para «{query}»'**
  String library_importSpotifyNone(String query);

  /// Importación: enlaces admitidos (también detalle de «Enlace no admitido»).
  ///
  /// In es, this message translates to:
  /// **'Se admiten enlaces de un vídeo de YouTube (youtube.com/watch, youtu.be, music.youtube.com) y de una canción de Spotify (open.spotify.com/track o spotify:track), además de listas de YouTube (youtube.com/playlist) y listas o álbumes de Spotify (open.spotify.com/playlist, open.spotify.com/album). Episodios no.'**
  String get library_importSupported;

  /// Importación: título de la hoja vacía.
  ///
  /// In es, this message translates to:
  /// **'Importar tema'**
  String get library_importTitleEmpty;

  /// Importación: título de la hoja de enlace.
  ///
  /// In es, this message translates to:
  /// **'Importar desde enlace'**
  String get library_importTitleLink;

  /// Importación: título de la hoja de lista.
  ///
  /// In es, this message translates to:
  /// **'Importar lista'**
  String get library_importTitleList;

  /// Importación: botón de error.
  ///
  /// In es, this message translates to:
  /// **'Actualizar y reintentar'**
  String get library_importUpdateRetry;

  /// Importación: fase actualizando yt-dlp.
  ///
  /// In es, this message translates to:
  /// **'Actualizando yt-dlp…'**
  String get library_importUpdating;

  /// Importación: cabecera de sección (mayúsculas).
  ///
  /// In es, this message translates to:
  /// **'VÍDEO A IMPORTAR'**
  String get library_importVideoLabel;

  /// Detalle: etiqueta del dato duración.
  ///
  /// In es, this message translates to:
  /// **'Duración'**
  String get library_infoDuration;

  /// Detalle: etiqueta del dato frecuencia.
  ///
  /// In es, this message translates to:
  /// **'Frecuencia'**
  String get library_infoRate;

  /// Detalle: etiqueta del dato estado.
  ///
  /// In es, this message translates to:
  /// **'Estado'**
  String get library_infoState;

  /// Cabecera: menú contextual de la fila.
  ///
  /// In es, this message translates to:
  /// **'Cancelar separación'**
  String get library_menuCancelSeparation;

  /// Cabecera: menú contextual de la fila.
  ///
  /// In es, this message translates to:
  /// **'Limpiar…'**
  String get library_menuClean;

  /// Cabecera: menú contextual de la fila.
  ///
  /// In es, this message translates to:
  /// **'Eliminar…'**
  String get library_menuDelete;

  /// Cabecera: menú contextual de la fila (macOS).
  ///
  /// In es, this message translates to:
  /// **'Mostrar en Finder'**
  String get library_menuRevealMac;

  /// Cabecera: menú contextual de la fila (Windows).
  ///
  /// In es, this message translates to:
  /// **'Mostrar en el Explorador de archivos'**
  String get library_menuRevealWindows;

  /// Cabecera: menú contextual de la fila.
  ///
  /// In es, this message translates to:
  /// **'Separar de nuevo'**
  String get library_menuSeparate;

  /// Artistas: tema sin artista.
  ///
  /// In es, this message translates to:
  /// **'Sin artista'**
  String get library_noArtist;

  /// Cabecera: sin resultados de búsqueda.
  ///
  /// In es, this message translates to:
  /// **'Ningún tema coincide con «{query}»'**
  String library_noMatch(String query);

  /// Diálogos y avisos: botón del aviso.
  ///
  /// In es, this message translates to:
  /// **'Aceptar'**
  String get library_noticeOk;

  /// Detalle: botón abrir en backing.
  ///
  /// In es, this message translates to:
  /// **'Abrir en Backing track'**
  String get library_openInBacking;

  /// Cabecera: tooltip del indicador de lista en curso.
  ///
  /// In es, this message translates to:
  /// **'Ver la importación de la lista'**
  String get library_playlistIndicatorTooltip;

  /// Lista: botón cancelar.
  ///
  /// In es, this message translates to:
  /// **'Cancelar'**
  String get library_plCancel;

  /// Lista: título de cola cancelada.
  ///
  /// In es, this message translates to:
  /// **'Cola cancelada: lo ya importado se conserva'**
  String get library_plCancelledTitle;

  /// Lista: aviso de límite de 100 temas.
  ///
  /// In es, this message translates to:
  /// **'Spotify devuelve como máximo 100 temas por lista: puede haber cortado esta. Si faltan temas, impórtalos desde su enlace.'**
  String get library_plCap;

  /// Lista: chip de tema dudoso.
  ///
  /// In es, this message translates to:
  /// **'dudoso'**
  String get library_plChipDoubtful;

  /// Lista: chip de posible duplicado.
  ///
  /// In es, this message translates to:
  /// **'Puede que ya lo tengas'**
  String get library_plChipMaybe;

  /// Lista: opción de elección (búsqueda fallida).
  ///
  /// In es, this message translates to:
  /// **'Falló la búsqueda: {title}'**
  String library_plChoiceFailed(String title);

  /// Lista: opción de elección (sin resultados).
  ///
  /// In es, this message translates to:
  /// **'Sin resultados: omitir'**
  String get library_plChoiceNoResults;

  /// Lista: opción de elección (pendiente).
  ///
  /// In es, this message translates to:
  /// **'Sin buscar'**
  String get library_plChoicePending;

  /// Lista: opción de elección (texto inicial).
  ///
  /// In es, this message translates to:
  /// **'Elige un candidato…'**
  String get library_plChoicePick;

  /// Lista: opción de elección (omitido).
  ///
  /// In es, this message translates to:
  /// **'Omitido'**
  String get library_plChoiceSkipped;

  /// Lista: tooltip del botón cerrar.
  ///
  /// In es, this message translates to:
  /// **'La cola sigue en segundo plano'**
  String get library_plCloseTooltip;

  /// Lista: estado de fila convirtiendo.
  ///
  /// In es, this message translates to:
  /// **'Convirtiendo…'**
  String get library_plConverting;

  /// Lista: nombre por defecto de la lista.
  ///
  /// In es, this message translates to:
  /// **'Lista'**
  String get library_plDefaultName;

  /// Lista: título del resumen final.
  ///
  /// In es, this message translates to:
  /// **'Importación terminada'**
  String get library_plDoneTitle;

  /// Lista: botón descargar.
  ///
  /// In es, this message translates to:
  /// **'Descargar y procesar ({n})'**
  String library_plDownload(int n);

  /// Lista: estado de fila descargando.
  ///
  /// In es, this message translates to:
  /// **'Descargando'**
  String get library_plDownloading;

  /// Lista: estado de fila descargando con porcentaje.
  ///
  /// In es, this message translates to:
  /// **'Descargando {percent}'**
  String library_plDownloadingPercent(String percent);

  /// Lista: cabecera de sección (mayúsculas).
  ///
  /// In es, this message translates to:
  /// **'FALLIDOS'**
  String get library_plFailedHeader;

  /// Lista: indicador cancelado.
  ///
  /// In es, this message translates to:
  /// **'Importación cancelada'**
  String get library_plIndCancelled;

  /// Lista: indicador terminado.
  ///
  /// In es, this message translates to:
  /// **'Importación terminada'**
  String get library_plIndFinished;

  /// Lista: indicador importando.
  ///
  /// In es, this message translates to:
  /// **'Importando {n} de {total}'**
  String library_plIndImporting(int n, int total);

  /// Lista: indicador leyendo.
  ///
  /// In es, this message translates to:
  /// **'Leyendo la lista…'**
  String get library_plIndLoading;

  /// Lista: indicador buscando.
  ///
  /// In es, this message translates to:
  /// **'Buscando {n} de {total}'**
  String library_plIndSearching(int n, int total);

  /// Lista: indicador detenido.
  ///
  /// In es, this message translates to:
  /// **'Importación detenida'**
  String get library_plIndStopped;

  /// Lista: etiqueta de tema ya en la biblioteca.
  ///
  /// In es, this message translates to:
  /// **'{label} · En la biblioteca'**
  String library_plInLibrarySuffix(String label);

  /// Lista: botón seguir buscando.
  ///
  /// In es, this message translates to:
  /// **'Seguir buscando'**
  String get library_plKeepSearching;

  /// Lista: aviso de yt-dlp ya actualizado.
  ///
  /// In es, this message translates to:
  /// **'yt-dlp ya es la última versión: YouTube ha cambiado algo y hay que esperar a que se corrija. Lo ya importado se conserva.'**
  String get library_plLatestKept;

  /// Lista: tooltip del chip de posible duplicado.
  ///
  /// In es, this message translates to:
  /// **'Parecido a: {title}'**
  String library_plMaybeTooltip(String title);

  /// Lista: aviso antes de descargar.
  ///
  /// In es, this message translates to:
  /// **'Nada se descarga todavía: después podrás revisar los candidatos.'**
  String get library_plNothingYet;

  /// Lista: acción abrir el existente.
  ///
  /// In es, this message translates to:
  /// **'Abrir «{title}» en la biblioteca'**
  String library_plOpenExisting(String title);

  /// Lista: estado de fila importado.
  ///
  /// In es, this message translates to:
  /// **'Importado'**
  String get library_plQImported;

  /// Lista: estado de fila ya en la biblioteca.
  ///
  /// In es, this message translates to:
  /// **'En la biblioteca'**
  String get library_plQInLibrary;

  /// Lista: estado de fila en cola.
  ///
  /// In es, this message translates to:
  /// **'En cola'**
  String get library_plQQueued;

  /// Lista: estado de fila omitido.
  ///
  /// In es, this message translates to:
  /// **'Omitido'**
  String get library_plQSkipped;

  /// Lista: contador de la cola.
  ///
  /// In es, this message translates to:
  /// **'{done} de {total} temas'**
  String library_plQueueCount(int done, int total);

  /// Lista: cola detenida.
  ///
  /// In es, this message translates to:
  /// **'Cola detenida'**
  String get library_plQueueStopped;

  /// Lista: título de la cola.
  ///
  /// In es, this message translates to:
  /// **'Descargando, importando y separando'**
  String get library_plQueueTitle;

  /// Lista: pista de límite de peticiones.
  ///
  /// In es, this message translates to:
  /// **'No se reintenta sola: reanuda cuando quieras.'**
  String get library_plRateLimitedHint;

  /// Lista: botón reanudar.
  ///
  /// In es, this message translates to:
  /// **'Reanudar'**
  String get library_plResume;

  /// Lista: botón reanudar con contador.
  ///
  /// In es, this message translates to:
  /// **'Reanudar ({n})'**
  String library_plResumeN(int n);

  /// Lista: botón reintentar fallidos.
  ///
  /// In es, this message translates to:
  /// **'Reintentar fallidos ({n})'**
  String library_plRetryFailed(int n);

  /// Lista: banner de revisión.
  ///
  /// In es, this message translates to:
  /// **'Revisa lo propuesto: nada se descarga hasta que pulses «Descargar y procesar». Los «dudosos» no tienen propuesta: elige uno o se omiten.'**
  String get library_plReviewBanner;

  /// Lista: resumen de revisión.
  ///
  /// In es, this message translates to:
  /// **'{proposed} con candidato · {doubtful} dudosos · {skipped} omitidos'**
  String library_plReviewSummary(int proposed, int doubtful, int skipped);

  /// Lista: botón buscar.
  ///
  /// In es, this message translates to:
  /// **'Buscar en YouTube ({n})'**
  String library_plSearch(int n);

  /// Lista: fase de búsqueda en curso.
  ///
  /// In es, this message translates to:
  /// **'Buscando cada tema en YouTube'**
  String get library_plSearchingAll;

  /// Lista: fase de búsqueda, progreso.
  ///
  /// In es, this message translates to:
  /// **'Buscando {n} de {total}'**
  String library_plSearchingN(int n, int total);

  /// Lista: botón marcar todos.
  ///
  /// In es, this message translates to:
  /// **'Marcar todos'**
  String get library_plSelectAll;

  /// Lista: botón no marcar ninguno.
  ///
  /// In es, this message translates to:
  /// **'Ninguno'**
  String get library_plSelectNone;

  /// Lista: nota de separación.
  ///
  /// In es, this message translates to:
  /// **'Los temas importados se están separando en stems; verás el avance en la Biblioteca.'**
  String get library_plSeparatingNote;

  /// Lista: acción omitir.
  ///
  /// In es, this message translates to:
  /// **'Omitir este tema'**
  String get library_plSkipItem;

  /// Lista: estadística de fallidos.
  ///
  /// In es, this message translates to:
  /// **'Fallidos'**
  String get library_plStatFailed;

  /// Lista: estadística de importados.
  ///
  /// In es, this message translates to:
  /// **'Importados'**
  String get library_plStatImported;

  /// Lista: estadística de ya en la biblioteca.
  ///
  /// In es, this message translates to:
  /// **'Ya en la biblioteca'**
  String get library_plStatInLibrary;

  /// Lista: estadística de omitidos.
  ///
  /// In es, this message translates to:
  /// **'Omitidos'**
  String get library_plStatSkipped;

  /// Lista: resumen de temas.
  ///
  /// In es, this message translates to:
  /// **'{total} temas · {selected} marcados'**
  String library_plSummary(int total, int selected);

  /// Lista: sufijo del resumen con temas ya en la biblioteca.
  ///
  /// In es, this message translates to:
  /// **' · {n} ya en la biblioteca'**
  String library_plSummaryInLibrary(int n);

  /// Lista: botón de error.
  ///
  /// In es, this message translates to:
  /// **'Actualizar y reintentar'**
  String get library_plUpdateRetry;

  /// Lista: estado actualizando.
  ///
  /// In es, this message translates to:
  /// **'Actualizando…'**
  String get library_plUpdating;

  /// Grabaciones: lista vacía.
  ///
  /// In es, this message translates to:
  /// **'Este tema aún no tiene tomas grabadas.'**
  String get library_recordingsNone;

  /// Grabaciones: título de la pantalla de tomas.
  ///
  /// In es, this message translates to:
  /// **'Grabaciones'**
  String get library_recordingsTitle;

  /// Detalle: botón mostrar (macOS).
  ///
  /// In es, this message translates to:
  /// **'Mostrar en Finder'**
  String get library_revealButtonMac;

  /// Detalle: botón mostrar (Windows).
  ///
  /// In es, this message translates to:
  /// **'Mostrar en el Explorador de archivos'**
  String get library_revealButtonWindows;

  /// Cabecera: tooltip del botón mostrar (macOS).
  ///
  /// In es, this message translates to:
  /// **'Mostrar en Finder'**
  String get library_revealTooltipMac;

  /// Cabecera: tooltip del botón mostrar (Windows).
  ///
  /// In es, this message translates to:
  /// **'Mostrar en el Explorador de archivos'**
  String get library_revealTooltipWindows;

  /// Detalle: botón guardar el título.
  ///
  /// In es, this message translates to:
  /// **'Guardar'**
  String get library_save;

  /// Cabecera: botón que borra la búsqueda (accesibilidad).
  ///
  /// In es, this message translates to:
  /// **'Borrar búsqueda'**
  String get library_searchClear;

  /// Cabecera: pista del campo de búsqueda.
  ///
  /// In es, this message translates to:
  /// **'Buscar tema o artista'**
  String get library_searchHint;

  /// Errores de fuente: detalle.
  ///
  /// In es, this message translates to:
  /// **'Vídeo con restricción de edad: no se puede descargar sin cuenta.'**
  String get library_srcAgeRestrictedDetail;

  /// Errores de fuente: título.
  ///
  /// In es, this message translates to:
  /// **'Vídeo con restricción de edad'**
  String get library_srcAgeRestrictedTitle;

  /// Errores de fuente: título (sin detalle).
  ///
  /// In es, this message translates to:
  /// **'Cancelado'**
  String get library_srcCancelledTitle;

  /// Errores de fuente: detalle.
  ///
  /// In es, this message translates to:
  /// **'La suma SHA-256 del yt-dlp descargado no coincide. No se ha instalado nada.'**
  String get library_srcChecksumDetail;

  /// Errores de fuente: título.
  ///
  /// In es, this message translates to:
  /// **'Actualización rechazada'**
  String get library_srcChecksumTitle;

  /// Errores de fuente: detalle.
  ///
  /// In es, this message translates to:
  /// **'YouTube ha cambiado algo y yt-dlp no sabe leerlo.'**
  String get library_srcExtractorBrokenDetail;

  /// Errores de fuente: título sin versión conocida.
  ///
  /// In es, this message translates to:
  /// **'yt-dlp puede estar desactualizado'**
  String get library_srcExtractorBrokenTitle;

  /// Errores de fuente: título con versión de yt-dlp.
  ///
  /// In es, this message translates to:
  /// **'yt-dlp puede estar desactualizado (versión {version})'**
  String library_srcExtractorBrokenTitleVersion(String version);

  /// Errores de fuente: título (el detalle son las últimas líneas del proceso, dinámico).
  ///
  /// In es, this message translates to:
  /// **'Falló la conversión'**
  String get library_srcFfmpegFailedTitle;

  /// Errores de fuente: detalle.
  ///
  /// In es, this message translates to:
  /// **'No se encuentra «{name}» dentro de la app. Reinstala ToneForge.'**
  String library_srcHelperMissingDetail(String name);

  /// Errores de fuente: título.
  ///
  /// In es, this message translates to:
  /// **'Falta un componente'**
  String get library_srcHelperMissingTitle;

  /// Errores de fuente: detalle.
  ///
  /// In es, this message translates to:
  /// **'El servidor respondió con el código {code}.'**
  String library_srcHttpStatusDetail(int code);

  /// Errores de fuente: título.
  ///
  /// In es, this message translates to:
  /// **'Respuesta inesperada'**
  String get library_srcHttpStatusTitle;

  /// Errores de fuente: título (el detalle son las últimas líneas, dinámico).
  ///
  /// In es, this message translates to:
  /// **'No se pudo lanzar el proceso'**
  String get library_srcLaunchFailedTitle;

  /// Errores de fuente: detalle.
  ///
  /// In es, this message translates to:
  /// **'Este vídeo no ofrece audio descargable.'**
  String get library_srcNoAudioFormatDetail;

  /// Errores de fuente: título.
  ///
  /// In es, this message translates to:
  /// **'Sin audio descargable'**
  String get library_srcNoAudioFormatTitle;

  /// Errores de fuente: detalle.
  ///
  /// In es, this message translates to:
  /// **'yt-dlp terminó pero no dejó ningún fichero de audio.'**
  String get library_srcNoAudioProducedDetail;

  /// Errores de fuente: título.
  ///
  /// In es, this message translates to:
  /// **'Sin audio'**
  String get library_srcNoAudioProducedTitle;

  /// Errores de fuente: detalle.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido conectar. Comprueba la red y reintenta.'**
  String get library_srcOfflineDetail;

  /// Errores de fuente: título.
  ///
  /// In es, this message translates to:
  /// **'Sin conexión'**
  String get library_srcOfflineTitle;

  /// Errores de fuente: detalle.
  ///
  /// In es, this message translates to:
  /// **'Este vídeo es privado.'**
  String get library_srcPrivateDetail;

  /// Errores de fuente: título.
  ///
  /// In es, this message translates to:
  /// **'Vídeo privado'**
  String get library_srcPrivateTitle;

  /// Errores de fuente: detalle.
  ///
  /// In es, this message translates to:
  /// **'YouTube ha limitado las peticiones; espera unos minutos y reintenta.'**
  String get library_srcRateLimitedDetail;

  /// Errores de fuente: título.
  ///
  /// In es, this message translates to:
  /// **'YouTube ha limitado las peticiones'**
  String get library_srcRateLimitedTitle;

  /// Errores de fuente: detalle.
  ///
  /// In es, this message translates to:
  /// **'Este vídeo no está disponible en tu país.'**
  String get library_srcRegionDetail;

  /// Errores de fuente: título.
  ///
  /// In es, this message translates to:
  /// **'No disponible en tu región'**
  String get library_srcRegionTitle;

  /// Errores de fuente: detalle.
  ///
  /// In es, this message translates to:
  /// **'Este vídeo se ha retirado o ya no está disponible.'**
  String get library_srcRemovedDetail;

  /// Errores de fuente: título.
  ///
  /// In es, this message translates to:
  /// **'Vídeo no disponible'**
  String get library_srcRemovedTitle;

  /// Errores de fuente: detalle.
  ///
  /// In es, this message translates to:
  /// **'Pega un enlace de YouTube del tema en su lugar.'**
  String get library_srcSpotifyUnreadableDetail;

  /// Errores de fuente: título.
  ///
  /// In es, this message translates to:
  /// **'No se han podido leer los datos de Spotify'**
  String get library_srcSpotifyUnreadableTitle;

  /// Errores de fuente: detalle.
  ///
  /// In es, this message translates to:
  /// **'El servidor tarda demasiado en responder. Reintenta.'**
  String get library_srcTimedOutDetail;

  /// Errores de fuente: título.
  ///
  /// In es, this message translates to:
  /// **'Tiempo agotado'**
  String get library_srcTimedOutTitle;

  /// Errores de fuente: título (el detalle es library_importSupported).
  ///
  /// In es, this message translates to:
  /// **'Enlace no admitido'**
  String get library_srcUnsupportedTitle;

  /// Errores de fuente: título (el detalle son las últimas líneas, dinámico).
  ///
  /// In es, this message translates to:
  /// **'No se pudo actualizar yt-dlp'**
  String get library_srcUpdateFailedTitle;

  /// Detalle: estado del tema (separado).
  ///
  /// In es, this message translates to:
  /// **'Separado'**
  String get library_stateDetailDone;

  /// Detalle: estado del tema con error.
  ///
  /// In es, this message translates to:
  /// **'Error: {message}'**
  String library_stateDetailFailed(String message);

  /// Detalle: estado con error sin mensaje.
  ///
  /// In es, this message translates to:
  /// **'desconocido'**
  String get library_stateDetailFailedUnknown;

  /// Detalle: estado del tema (importado).
  ///
  /// In es, this message translates to:
  /// **'Importado'**
  String get library_stateDetailImported;

  /// Detalle: estado del tema (en cola).
  ///
  /// In es, this message translates to:
  /// **'En cola'**
  String get library_stateDetailQueued;

  /// Detalle: estado del tema (separando).
  ///
  /// In es, this message translates to:
  /// **'Separando'**
  String get library_stateDetailRunning;

  /// Cabecera: estado de la fila (separado).
  ///
  /// In es, this message translates to:
  /// **'Separado'**
  String get library_stateDone;

  /// Cabecera: estado de la fila (fallido).
  ///
  /// In es, this message translates to:
  /// **'Error'**
  String get library_stateFailed;

  /// Cabecera: estado de la fila sin motivo.
  ///
  /// In es, this message translates to:
  /// **'Error desconocido'**
  String get library_stateFailedUnknown;

  /// Cabecera: estado de la fila (importado).
  ///
  /// In es, this message translates to:
  /// **'Importado'**
  String get library_stateImported;

  /// Cabecera: estado de la fila (en cola).
  ///
  /// In es, this message translates to:
  /// **'En cola'**
  String get library_stateQueued;

  /// Cabecera: estado de la fila (separando).
  ///
  /// In es, this message translates to:
  /// **'Separando {percent}'**
  String library_stateRunning(String percent);

  /// Detalle: estado de un stem sin fichero.
  ///
  /// In es, this message translates to:
  /// **'vacío'**
  String get library_stemEmpty;

  /// Detalle: sección de stems vacía.
  ///
  /// In es, this message translates to:
  /// **'Sin stems todavía.'**
  String get library_stemsNone;

  /// Detalle: título de la sección de stems.
  ///
  /// In es, this message translates to:
  /// **'Stems'**
  String get library_stemsTitle;

  /// Cabecera: subtítulo bajo el título.
  ///
  /// In es, this message translates to:
  /// **'Tus temas.'**
  String get library_subtitle;

  /// Hoja de corrección: tooltip del botón intercambiar.
  ///
  /// In es, this message translates to:
  /// **'Intercambiar título y artista'**
  String get library_swapTooltip;

  /// Grabaciones: marca de mejor toma (accesibilidad de ★).
  ///
  /// In es, this message translates to:
  /// **'Mejor toma'**
  String get library_takeBest;

  /// Grabaciones: aviso de error al marcar mejor toma.
  ///
  /// In es, this message translates to:
  /// **'No se pudo marcar la toma como mejor ({error}).'**
  String library_takeBestError(String error);

  /// Grabaciones: acción eliminar toma.
  ///
  /// In es, this message translates to:
  /// **'Eliminar'**
  String get library_takeDelete;

  /// Grabaciones: botón del diálogo; label por defecto «toma» («take»).
  ///
  /// In es, this message translates to:
  /// **'Eliminar {label}'**
  String library_takeDeleteConfirm(String label);

  /// Grabaciones: aviso de error al eliminar toma.
  ///
  /// In es, this message translates to:
  /// **'No se pudo eliminar la toma ({error}).'**
  String library_takeDeleteError(String error);

  /// Grabaciones: cuerpo del diálogo de borrar toma.
  ///
  /// In es, this message translates to:
  /// **'Se borra su carpeta (audio y vídeo). No se puede deshacer.'**
  String get library_takeDeleteMessage;

  /// Grabaciones: título del diálogo de borrar toma.
  ///
  /// In es, this message translates to:
  /// **'¿Eliminar la toma?'**
  String get library_takeDeleteTitle;

  /// Grabaciones: rótulo de toma con su parte.
  ///
  /// In es, this message translates to:
  /// **'Toma {n} · {part}'**
  String library_takeLabel(int n, String part);

  /// Grabaciones: duración vacía (celda).
  ///
  /// In es, this message translates to:
  /// **'–'**
  String get library_takeNoDuration;

  /// Grabaciones: etiqueta de toma sin vídeo.
  ///
  /// In es, this message translates to:
  /// **'Sin vídeo'**
  String get library_takeNoVideo;

  /// Grabaciones: título de una toma.
  ///
  /// In es, this message translates to:
  /// **'Toma {n}'**
  String library_takeNumber(int n);

  /// Grabaciones: número de punches de una toma.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, one{1 punch} other{{count} punches}}'**
  String library_takePunches(int count);

  /// Cabecera: celda sin tomas.
  ///
  /// In es, this message translates to:
  /// **'—'**
  String get library_takesNone;

  /// Grabaciones: acción ver toma.
  ///
  /// In es, this message translates to:
  /// **'Ver toma'**
  String get library_takeView;

  /// Grabaciones: etiqueta de toma con vídeo.
  ///
  /// In es, this message translates to:
  /// **'Con vídeo'**
  String get library_takeWithVideo;

  /// Cabecera: título de la pantalla.
  ///
  /// In es, this message translates to:
  /// **'Biblioteca'**
  String get library_title;

  /// Diálogos y avisos: contenido del borrado (stems).
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =0{sus stems} one{1 stem} other{{count} stems}}'**
  String library_trashContentsStems(int count);

  /// Diálogos y avisos: contenido del borrado (tomas).
  ///
  /// In es, this message translates to:
  /// **'{count, plural, one{1 toma} other{{count} tomas}}'**
  String library_trashContentsTakes(int count);

  /// Diálogos y avisos: contenido del borrado (vídeos).
  ///
  /// In es, this message translates to:
  /// **'{count, plural, one{1 vídeo} other{{count} vídeos}}'**
  String library_trashContentsVideos(int count);

  /// Diálogos y avisos: botón borrar del disco.
  ///
  /// In es, this message translates to:
  /// **'Eliminar del disco'**
  String get library_trashDelete;

  /// Diálogos y avisos: cuerpo de eliminar tema (macOS).
  ///
  /// In es, this message translates to:
  /// **'Se va con el tema: {contents}. Si se está separando o está abierto en Backing, se detiene primero.\nEliminar del disco no se puede deshacer. La Papelera conserva la carpeta hasta que la vacíes.'**
  String library_trashMessageMac(String contents);

  /// Diálogos y avisos: cuerpo de eliminar tema (Windows).
  ///
  /// In es, this message translates to:
  /// **'Se va con el tema: {contents}. Si se está separando o está abierto en Backing, se detiene primero.\nEliminar del disco no se puede deshacer. La Papelera de reciclaje conserva la carpeta hasta que la vacíes.'**
  String library_trashMessageWindows(String contents);

  /// Diálogos y avisos: título de eliminar tema.
  ///
  /// In es, this message translates to:
  /// **'¿Eliminar “{title}”?'**
  String library_trashTitle(String title);

  /// Diálogos y avisos: botón mover a la papelera (macOS).
  ///
  /// In es, this message translates to:
  /// **'Mover a la Papelera'**
  String get library_trashToBinMac;

  /// Diálogos y avisos: botón mover a la papelera (Windows).
  ///
  /// In es, this message translates to:
  /// **'Mover a la Papelera de reciclaje'**
  String get library_trashToBinWindows;

  /// Cabecera: selector de vista, artistas.
  ///
  /// In es, this message translates to:
  /// **'Artistas'**
  String get library_viewArtists;

  /// Cabecera: etiqueta del selector de vista (solo accesibilidad).
  ///
  /// In es, this message translates to:
  /// **'Vista'**
  String get library_viewLabel;

  /// Cabecera: selector de vista, temas.
  ///
  /// In es, this message translates to:
  /// **'Temas'**
  String get library_viewSongs;

  /// Ancla del bloque backing: añade las claves del área debajo, en orden alfabético; no edites otros bloques.
  ///
  /// In es, this message translates to:
  /// **''**
  String get backingAnchor;

  /// No description provided for @backing_analysisFailed.
  ///
  /// In es, this message translates to:
  /// **'No se pudo analizar: {message}'**
  String backing_analysisFailed(String message);

  /// No description provided for @backing_analysisMissing.
  ///
  /// In es, this message translates to:
  /// **'Sin análisis de acordes ni pulso todavía.'**
  String get backing_analysisMissing;

  /// No description provided for @backing_analyze.
  ///
  /// In es, this message translates to:
  /// **'Analizar'**
  String get backing_analyze;

  /// No description provided for @backing_analyzing.
  ///
  /// In es, this message translates to:
  /// **'Analizando acordes y pulso… Puedes reproducir mientras tanto.'**
  String get backing_analyzing;

  /// No description provided for @backing_apply.
  ///
  /// In es, this message translates to:
  /// **'Aplicar'**
  String get backing_apply;

  /// No description provided for @backing_applyTooltip.
  ///
  /// In es, this message translates to:
  /// **'Guarda las secciones. Las pistas de guitarra se rehacen, en segundo plano, solo si cambian los solos'**
  String get backing_applyTooltip;

  /// No description provided for @backing_barLabel.
  ///
  /// In es, this message translates to:
  /// **'c. {number}'**
  String backing_barLabel(int number);

  /// No description provided for @backing_bpm.
  ///
  /// In es, this message translates to:
  /// **'{bpm} BPM'**
  String backing_bpm(int bpm);

  /// No description provided for @backing_capo.
  ///
  /// In es, this message translates to:
  /// **'Capo virtual'**
  String get backing_capo;

  /// No description provided for @backing_capoFret.
  ///
  /// In es, this message translates to:
  /// **'Traste {n}'**
  String backing_capoFret(int n);

  /// No description provided for @backing_capoNone.
  ///
  /// In es, this message translates to:
  /// **'Sin capo'**
  String get backing_capoNone;

  /// No description provided for @backing_capoShown.
  ///
  /// In es, this message translates to:
  /// **'Capo {fret}'**
  String backing_capoShown(int fret);

  /// No description provided for @backing_cents.
  ///
  /// In es, this message translates to:
  /// **'{n} cents'**
  String backing_cents(int n);

  /// No description provided for @backing_channelNameField.
  ///
  /// In es, this message translates to:
  /// **'Nombre'**
  String get backing_channelNameField;

  /// No description provided for @backing_channelRenameMenu.
  ///
  /// In es, this message translates to:
  /// **'Cambiar nombre…'**
  String get backing_channelRenameMenu;

  /// No description provided for @backing_channelRenameTooltip.
  ///
  /// In es, this message translates to:
  /// **'Doble clic para cambiar el nombre'**
  String get backing_channelRenameTooltip;

  /// No description provided for @backing_chooserEmpty.
  ///
  /// In es, this message translates to:
  /// **'Aún no hay temas separados. Importa uno y sepáralo en la biblioteca.'**
  String get backing_chooserEmpty;

  /// No description provided for @backing_chooserPick.
  ///
  /// In es, this message translates to:
  /// **'Elige un tema'**
  String get backing_chooserPick;

  /// No description provided for @backing_chordMajor.
  ///
  /// In es, this message translates to:
  /// **'mayor'**
  String get backing_chordMajor;

  /// No description provided for @backing_chordNone.
  ///
  /// In es, this message translates to:
  /// **'N (sin acorde)'**
  String get backing_chordNone;

  /// No description provided for @backing_chordRemoveOverride.
  ///
  /// In es, this message translates to:
  /// **'Quitar corrección'**
  String get backing_chordRemoveOverride;

  /// No description provided for @backing_chords.
  ///
  /// In es, this message translates to:
  /// **'Acordes'**
  String get backing_chords;

  /// No description provided for @backing_chordsAfterAnalysis.
  ///
  /// In es, this message translates to:
  /// **'Los acordes aparecerán al terminar el análisis.'**
  String get backing_chordsAfterAnalysis;

  /// No description provided for @backing_chordSheetTitle.
  ///
  /// In es, this message translates to:
  /// **'Acorde'**
  String get backing_chordSheetTitle;

  /// No description provided for @backing_chordSplit.
  ///
  /// In es, this message translates to:
  /// **'Partir aquí'**
  String get backing_chordSplit;

  /// No description provided for @backing_chordSplitTooltip.
  ///
  /// In es, this message translates to:
  /// **'Parte el tramo en el pulso más cercano al cursor de reproducción'**
  String get backing_chordSplitTooltip;

  /// No description provided for @backing_clearOverrides.
  ///
  /// In es, this message translates to:
  /// **'Quitar todas ({count})'**
  String backing_clearOverrides(int count);

  /// No description provided for @backing_clearOverridesTooltip.
  ///
  /// In es, this message translates to:
  /// **'Quita todas las correcciones de acordes de este tema'**
  String get backing_clearOverridesTooltip;

  /// No description provided for @backing_collapse.
  ///
  /// In es, this message translates to:
  /// **'Plegar'**
  String get backing_collapse;

  /// No description provided for @backing_collapseA11y.
  ///
  /// In es, this message translates to:
  /// **'Plegar acordes'**
  String get backing_collapseA11y;

  /// No description provided for @backing_dbValue.
  ///
  /// In es, this message translates to:
  /// **'{value} dB'**
  String backing_dbValue(double value);

  /// No description provided for @backing_discard.
  ///
  /// In es, this message translates to:
  /// **'Descartar'**
  String get backing_discard;

  /// No description provided for @backing_discardTooltip.
  ///
  /// In es, this message translates to:
  /// **'Vuelve a las secciones guardadas'**
  String get backing_discardTooltip;

  /// No description provided for @backing_dragHintMac.
  ///
  /// In es, this message translates to:
  /// **'Clic: saltar · arrastrar: bucle (⌥ = compases)'**
  String get backing_dragHintMac;

  /// No description provided for @backing_dragHintWin.
  ///
  /// In es, this message translates to:
  /// **'Clic: saltar · arrastrar: bucle (Alt = compases)'**
  String get backing_dragHintWin;

  /// No description provided for @backing_editChords.
  ///
  /// In es, this message translates to:
  /// **'Editar acordes'**
  String get backing_editChords;

  /// No description provided for @backing_editModeHint.
  ///
  /// In es, this message translates to:
  /// **'Modo edición: clic en un acorde para cambiarlo o partirlo. No se marcan bucles.'**
  String get backing_editModeHint;

  /// No description provided for @backing_errorLoadStems.
  ///
  /// In es, this message translates to:
  /// **'No se pudieron cargar los stems ({error}).'**
  String backing_errorLoadStems(String error);

  /// No description provided for @backing_errorPlay.
  ///
  /// In es, this message translates to:
  /// **'No se pudo reproducir ({error}).'**
  String backing_errorPlay(String error);

  /// No description provided for @backing_errorSaveGuitarNames.
  ///
  /// In es, this message translates to:
  /// **'No se pudieron guardar los nombres: {error}'**
  String backing_errorSaveGuitarNames(String error);

  /// No description provided for @backing_errorSaveGuitarOptions.
  ///
  /// In es, this message translates to:
  /// **'No se pudieron guardar las opciones: {error}'**
  String backing_errorSaveGuitarOptions(String error);

  /// No description provided for @backing_errorSaveSections.
  ///
  /// In es, this message translates to:
  /// **'No se pudieron guardar las secciones: {error}'**
  String backing_errorSaveSections(String error);

  /// No description provided for @backing_errorSaveStudy.
  ///
  /// In es, this message translates to:
  /// **'No se pudo guardar el estudio: {error}'**
  String backing_errorSaveStudy(String error);

  /// No description provided for @backing_expand.
  ///
  /// In es, this message translates to:
  /// **'Expandir'**
  String get backing_expand;

  /// No description provided for @backing_expandA11y.
  ///
  /// In es, this message translates to:
  /// **'Expandir acordes'**
  String get backing_expandA11y;

  /// No description provided for @backing_faderA11y.
  ///
  /// In es, this message translates to:
  /// **'Volumen'**
  String get backing_faderA11y;

  /// No description provided for @backing_fineTune.
  ///
  /// In es, this message translates to:
  /// **'Afinación fina'**
  String get backing_fineTune;

  /// No description provided for @backing_goToLibrary.
  ///
  /// In es, this message translates to:
  /// **'Ir a la biblioteca'**
  String get backing_goToLibrary;

  /// No description provided for @backing_guitarsProcessing.
  ///
  /// In es, this message translates to:
  /// **'Procesando guitarras…'**
  String get backing_guitarsProcessing;

  /// No description provided for @backing_handleEndA11y.
  ///
  /// In es, this message translates to:
  /// **'Borde de fin'**
  String get backing_handleEndA11y;

  /// No description provided for @backing_handleStartA11y.
  ///
  /// In es, this message translates to:
  /// **'Borde de inicio'**
  String get backing_handleStartA11y;

  /// No description provided for @backing_key.
  ///
  /// In es, this message translates to:
  /// **'Tonalidad:'**
  String get backing_key;

  /// No description provided for @backing_keyBackToDetected.
  ///
  /// In es, this message translates to:
  /// **'Volver a la detectada'**
  String get backing_keyBackToDetected;

  /// No description provided for @backing_keyCorrected.
  ///
  /// In es, this message translates to:
  /// **'(corregida)'**
  String get backing_keyCorrected;

  /// No description provided for @backing_keyMajor.
  ///
  /// In es, this message translates to:
  /// **'{note} mayor'**
  String backing_keyMajor(String note);

  /// No description provided for @backing_keyMinor.
  ///
  /// In es, this message translates to:
  /// **'{note} menor'**
  String backing_keyMinor(String note);

  /// No description provided for @backing_loopClearA11y.
  ///
  /// In es, this message translates to:
  /// **'Quitar bucle'**
  String get backing_loopClearA11y;

  /// No description provided for @backing_loopEnd.
  ///
  /// In es, this message translates to:
  /// **'Fin'**
  String get backing_loopEnd;

  /// No description provided for @backing_loopEndTooltip.
  ///
  /// In es, this message translates to:
  /// **'Marca el final del bucle en la posición actual'**
  String get backing_loopEndTooltip;

  /// No description provided for @backing_loopFree.
  ///
  /// In es, this message translates to:
  /// **'libre'**
  String get backing_loopFree;

  /// No description provided for @backing_loopLabel.
  ///
  /// In es, this message translates to:
  /// **'Bucle: {name} · {from}–{to}'**
  String backing_loopLabel(String name, String from, String to);

  /// No description provided for @backing_loopNameBars.
  ///
  /// In es, this message translates to:
  /// **'compases'**
  String get backing_loopNameBars;

  /// No description provided for @backing_loopNameChords.
  ///
  /// In es, this message translates to:
  /// **'acordes'**
  String get backing_loopNameChords;

  /// No description provided for @backing_loopStartButton.
  ///
  /// In es, this message translates to:
  /// **'Inicio {time}'**
  String backing_loopStartButton(String time);

  /// No description provided for @backing_loopStartTooltip.
  ///
  /// In es, this message translates to:
  /// **'Marca el inicio del bucle en la posición actual'**
  String get backing_loopStartTooltip;

  /// No description provided for @backing_markSection.
  ///
  /// In es, this message translates to:
  /// **'Marcar sección'**
  String get backing_markSection;

  /// No description provided for @backing_markSectionTooltip.
  ///
  /// In es, this message translates to:
  /// **'Marca el bucle como una sección'**
  String get backing_markSectionTooltip;

  /// No description provided for @backing_markSolo.
  ///
  /// In es, this message translates to:
  /// **'Marcar como solo'**
  String get backing_markSolo;

  /// No description provided for @backing_markSoloTooltip.
  ///
  /// In es, this message translates to:
  /// **'Marca el bucle como un solo: sus guitarras se separan al aplicar'**
  String get backing_markSoloTooltip;

  /// No description provided for @backing_master.
  ///
  /// In es, this message translates to:
  /// **'Master'**
  String get backing_master;

  /// No description provided for @backing_menuDeleteSection.
  ///
  /// In es, this message translates to:
  /// **'Eliminar sección'**
  String get backing_menuDeleteSection;

  /// No description provided for @backing_menuMarkSolo.
  ///
  /// In es, this message translates to:
  /// **'Marcar como solo'**
  String get backing_menuMarkSolo;

  /// No description provided for @backing_menuRenameAdjust.
  ///
  /// In es, this message translates to:
  /// **'Renombrar y ajustar…'**
  String get backing_menuRenameAdjust;

  /// No description provided for @backing_menuUnmarkSolo.
  ///
  /// In es, this message translates to:
  /// **'Quitar marca de solo'**
  String get backing_menuUnmarkSolo;

  /// No description provided for @backing_metronome.
  ///
  /// In es, this message translates to:
  /// **'Metrónomo'**
  String get backing_metronome;

  /// No description provided for @backing_mixer.
  ///
  /// In es, this message translates to:
  /// **'Mezclador'**
  String get backing_mixer;

  /// No description provided for @backing_mixerOutput.
  ///
  /// In es, this message translates to:
  /// **'Salida: {device} (— si vacío)'**
  String backing_mixerOutput(String device);

  /// No description provided for @backing_muteA11y.
  ///
  /// In es, this message translates to:
  /// **'Silenciar {name}'**
  String backing_muteA11y(String name);

  /// No description provided for @backing_muted.
  ///
  /// In es, this message translates to:
  /// **'Silenciado'**
  String get backing_muted;

  /// No description provided for @backing_muteLetter.
  ///
  /// In es, this message translates to:
  /// **'M'**
  String get backing_muteLetter;

  /// No description provided for @backing_nextChord.
  ///
  /// In es, this message translates to:
  /// **'Siguiente: {name}'**
  String backing_nextChord(String name);

  /// No description provided for @backing_noChords.
  ///
  /// In es, this message translates to:
  /// **'Sin acordes detectados.'**
  String get backing_noChords;

  /// No description provided for @backing_noGrid.
  ///
  /// In es, this message translates to:
  /// **'Sin rejilla de compases todavía.'**
  String get backing_noGrid;

  /// No description provided for @backing_notSeparatedBody.
  ///
  /// In es, this message translates to:
  /// **'Backing track necesita los stems. Sepáralo desde la biblioteca y vuelve.'**
  String get backing_notSeparatedBody;

  /// No description provided for @backing_notSeparatedTitle.
  ///
  /// In es, this message translates to:
  /// **'Este tema aún no está separado'**
  String get backing_notSeparatedTitle;

  /// No description provided for @backing_pause.
  ///
  /// In es, this message translates to:
  /// **'Pausar'**
  String get backing_pause;

  /// No description provided for @backing_play.
  ///
  /// In es, this message translates to:
  /// **'Reproducir'**
  String get backing_play;

  /// No description provided for @backing_positionA11y.
  ///
  /// In es, this message translates to:
  /// **'Posición'**
  String get backing_positionA11y;

  /// No description provided for @backing_positionValueA11y.
  ///
  /// In es, this message translates to:
  /// **'{time} de {duration}'**
  String backing_positionValueA11y(String time, String duration);

  /// No description provided for @backing_retry.
  ///
  /// In es, this message translates to:
  /// **'Reintentar'**
  String get backing_retry;

  /// kind: 'solo' o 'section'.
  ///
  /// In es, this message translates to:
  /// **'{kind, select, solo{Solo} other{Sección}} {name}, {from} a {to}'**
  String backing_sectionA11y(String kind, String name, String from, String to);

  /// No description provided for @backing_sectionA11yHint.
  ///
  /// In es, this message translates to:
  /// **'Clic para editarla; mantener pulsado para repetirla en bucle'**
  String get backing_sectionA11yHint;

  /// solo: 'yes' o 'no'.
  ///
  /// In es, this message translates to:
  /// **'{name}{solo, select, yes{ (solo)} other{}} · {from}–{to} · clic: editar, mantener: bucle'**
  String backing_sectionBoxTooltip(
    String name,
    String solo,
    String from,
    String to,
  );

  /// No description provided for @backing_sectionColor.
  ///
  /// In es, this message translates to:
  /// **'Color'**
  String get backing_sectionColor;

  /// No description provided for @backing_sectionColorN.
  ///
  /// In es, this message translates to:
  /// **'Color {n}'**
  String backing_sectionColorN(int n);

  /// No description provided for @backing_sectionDelete.
  ///
  /// In es, this message translates to:
  /// **'Eliminar'**
  String get backing_sectionDelete;

  /// No description provided for @backing_sectionDone.
  ///
  /// In es, this message translates to:
  /// **'Hecho'**
  String get backing_sectionDone;

  /// No description provided for @backing_sectionEnd.
  ///
  /// In es, this message translates to:
  /// **'Fin'**
  String get backing_sectionEnd;

  /// No description provided for @backing_sectionListen.
  ///
  /// In es, this message translates to:
  /// **'Escuchar en bucle'**
  String get backing_sectionListen;

  /// No description provided for @backing_sectionName.
  ///
  /// In es, this message translates to:
  /// **'Nombre'**
  String get backing_sectionName;

  /// edge: 'start' o 'end'. direction: 'after' o 'before'.
  ///
  /// In es, this message translates to:
  /// **'{edge, select, start{Inicio} other{Fin}} {direction, select, after{después} other{antes}}'**
  String backing_sectionNudgeA11y(String edge, String direction);

  /// No description provided for @backing_sectionNudgeHintMac.
  ///
  /// In es, this message translates to:
  /// **'◀ ▶ mueven por acorde · ⌥ por compás'**
  String get backing_sectionNudgeHintMac;

  /// No description provided for @backing_sectionNudgeHintWin.
  ///
  /// In es, this message translates to:
  /// **'◀ ▶ mueven por acorde · Alt por compás'**
  String get backing_sectionNudgeHintWin;

  /// No description provided for @backing_sectionSheetSection.
  ///
  /// In es, this message translates to:
  /// **'Sección'**
  String get backing_sectionSheetSection;

  /// No description provided for @backing_sectionSheetSolo.
  ///
  /// In es, this message translates to:
  /// **'Solo'**
  String get backing_sectionSheetSolo;

  /// No description provided for @backing_sectionSolo.
  ///
  /// In es, this message translates to:
  /// **'Solo'**
  String get backing_sectionSolo;

  /// No description provided for @backing_sectionSoloOrange.
  ///
  /// In es, this message translates to:
  /// **'Los solos van en naranja'**
  String get backing_sectionSoloOrange;

  /// No description provided for @backing_sectionStart.
  ///
  /// In es, this message translates to:
  /// **'Inicio'**
  String get backing_sectionStart;

  /// No description provided for @backing_sectionSuggestBridge.
  ///
  /// In es, this message translates to:
  /// **'Puente'**
  String get backing_sectionSuggestBridge;

  /// No description provided for @backing_sectionSuggestChorus.
  ///
  /// In es, this message translates to:
  /// **'Estribillo'**
  String get backing_sectionSuggestChorus;

  /// No description provided for @backing_sectionSuggestEnd.
  ///
  /// In es, this message translates to:
  /// **'Final'**
  String get backing_sectionSuggestEnd;

  /// No description provided for @backing_sectionSuggestIntro.
  ///
  /// In es, this message translates to:
  /// **'Intro'**
  String get backing_sectionSuggestIntro;

  /// No description provided for @backing_sectionSuggestVerse.
  ///
  /// In es, this message translates to:
  /// **'Estrofa'**
  String get backing_sectionSuggestVerse;

  /// No description provided for @backing_soloA11y.
  ///
  /// In es, this message translates to:
  /// **'Solo {name}'**
  String backing_soloA11y(String name);

  /// No description provided for @backing_soloLetter.
  ///
  /// In es, this message translates to:
  /// **'S'**
  String get backing_soloLetter;

  /// No description provided for @backing_stemBass.
  ///
  /// In es, this message translates to:
  /// **'Bajo'**
  String get backing_stemBass;

  /// No description provided for @backing_stemDrums.
  ///
  /// In es, this message translates to:
  /// **'Batería'**
  String get backing_stemDrums;

  /// No description provided for @backing_stemGuitar.
  ///
  /// In es, this message translates to:
  /// **'Guitarra'**
  String get backing_stemGuitar;

  /// No description provided for @backing_stemOther.
  ///
  /// In es, this message translates to:
  /// **'Resto'**
  String get backing_stemOther;

  /// No description provided for @backing_stemPiano.
  ///
  /// In es, this message translates to:
  /// **'Piano'**
  String get backing_stemPiano;

  /// No description provided for @backing_stemVocals.
  ///
  /// In es, this message translates to:
  /// **'Voz'**
  String get backing_stemVocals;

  /// No description provided for @backing_stereoSplit.
  ///
  /// In es, this message translates to:
  /// **'Guitarras en L y R'**
  String get backing_stereoSplit;

  /// No description provided for @backing_stereoSplitTooltip.
  ///
  /// In es, this message translates to:
  /// **'L = canal izquierdo, R = canal derecho de la pista de guitarras'**
  String get backing_stereoSplitTooltip;

  /// No description provided for @backing_tabButton.
  ///
  /// In es, this message translates to:
  /// **'Tablatura'**
  String get backing_tabButton;

  /// No description provided for @backing_tabButtonTooltip.
  ///
  /// In es, this message translates to:
  /// **'Abrir la tablatura de este tema'**
  String get backing_tabButtonTooltip;

  /// No description provided for @backing_tempo.
  ///
  /// In es, this message translates to:
  /// **'Tempo'**
  String get backing_tempo;

  /// No description provided for @backing_tempoDetected.
  ///
  /// In es, this message translates to:
  /// **'Tempo detectado'**
  String get backing_tempoDetected;

  /// No description provided for @backing_title.
  ///
  /// In es, this message translates to:
  /// **'Backing track'**
  String get backing_title;

  /// No description provided for @backing_transpose.
  ///
  /// In es, this message translates to:
  /// **'Transponer'**
  String get backing_transpose;

  /// No description provided for @backing_transposeZero.
  ///
  /// In es, this message translates to:
  /// **'0 semitonos'**
  String get backing_transposeZero;

  /// No description provided for @backing_unmuteA11y.
  ///
  /// In es, this message translates to:
  /// **'Activar {name}'**
  String backing_unmuteA11y(String name);

  /// No description provided for @backing_withoutGuitars.
  ///
  /// In es, this message translates to:
  /// **'Sin guitarras'**
  String get backing_withoutGuitars;

  /// Ancla del bloque tab: añade las claves del área debajo, en orden alfabético; no edites otros bloques.
  ///
  /// In es, this message translates to:
  /// **''**
  String get tabAnchor;

  /// No description provided for @tab_a11yCloseNotice.
  ///
  /// In es, this message translates to:
  /// **'Cerrar aviso'**
  String get tab_a11yCloseNotice;

  /// No description provided for @tab_a11yLengthenNote.
  ///
  /// In es, this message translates to:
  /// **'Alargar nota'**
  String get tab_a11yLengthenNote;

  /// No description provided for @tab_a11yMute.
  ///
  /// In es, this message translates to:
  /// **'Silenciar {track}'**
  String tab_a11yMute(String track);

  /// No description provided for @tab_a11yPause.
  ///
  /// In es, this message translates to:
  /// **'Pausar'**
  String get tab_a11yPause;

  /// No description provided for @tab_a11yPlay.
  ///
  /// In es, this message translates to:
  /// **'Reproducir'**
  String get tab_a11yPlay;

  /// No description provided for @tab_a11yRewind.
  ///
  /// In es, this message translates to:
  /// **'Volver al inicio'**
  String get tab_a11yRewind;

  /// No description provided for @tab_a11yShortenNote.
  ///
  /// In es, this message translates to:
  /// **'Acortar nota'**
  String get tab_a11yShortenNote;

  /// No description provided for @tab_a11ySolo.
  ///
  /// In es, this message translates to:
  /// **'Solo {track}'**
  String tab_a11ySolo(String track);

  /// No description provided for @tab_a11yUnmute.
  ///
  /// In es, this message translates to:
  /// **'Activar {track}'**
  String tab_a11yUnmute(String track);

  /// No description provided for @tab_addNote.
  ///
  /// In es, this message translates to:
  /// **'Añadir nota'**
  String get tab_addNote;

  /// No description provided for @tab_chooserEmpty.
  ///
  /// In es, this message translates to:
  /// **'Aún no hay temas separados. Importa uno y sepáralo en la biblioteca.'**
  String get tab_chooserEmpty;

  /// No description provided for @tab_chooserPick.
  ///
  /// In es, this message translates to:
  /// **'Elige un tema'**
  String get tab_chooserPick;

  /// No description provided for @tab_choosingAutomatic.
  ///
  /// In es, this message translates to:
  /// **'Transcribir automáticamente'**
  String get tab_choosingAutomatic;

  /// No description provided for @tab_choosingBody.
  ///
  /// In es, this message translates to:
  /// **'Songsterr trae la tablatura hecha por la comunidad; la transcripción automática sale del audio.'**
  String get tab_choosingBody;

  /// No description provided for @tab_choosingSongsterr.
  ///
  /// In es, this message translates to:
  /// **'Buscar en Songsterr'**
  String get tab_choosingSongsterr;

  /// No description provided for @tab_choosingTitle.
  ///
  /// In es, this message translates to:
  /// **'Elige la fuente de la tablatura'**
  String get tab_choosingTitle;

  /// No description provided for @tab_confirmAutoAction.
  ///
  /// In es, this message translates to:
  /// **'Pasar a automática'**
  String get tab_confirmAutoAction;

  /// No description provided for @tab_confirmAutoBody.
  ///
  /// In es, this message translates to:
  /// **'Se quitan las pistas de Songsterr y sus ediciones; las demás se transcriben del audio.'**
  String get tab_confirmAutoBody;

  /// No description provided for @tab_confirmAutoCancel.
  ///
  /// In es, this message translates to:
  /// **'Cancelar'**
  String get tab_confirmAutoCancel;

  /// No description provided for @tab_confirmAutoTitle.
  ///
  /// In es, this message translates to:
  /// **'¿Pasar a transcripción automática?'**
  String get tab_confirmAutoTitle;

  /// No description provided for @tab_delete.
  ///
  /// In es, this message translates to:
  /// **'Borrar'**
  String get tab_delete;

  /// No description provided for @tab_drumKeysHint.
  ///
  /// In es, this message translates to:
  /// **'B bombo · C caja · H charles · T tom · P platos'**
  String get tab_drumKeysHint;

  /// No description provided for @tab_editFretRange.
  ///
  /// In es, this message translates to:
  /// **'El traste saldría de 0–24.'**
  String get tab_editFretRange;

  /// No description provided for @tab_editInvalidDuration.
  ///
  /// In es, this message translates to:
  /// **'Esa duración no cabe.'**
  String get tab_editInvalidDuration;

  /// No description provided for @tab_editInvalidPosition.
  ///
  /// In es, this message translates to:
  /// **'Esa posición no está en la rejilla de la pista.'**
  String get tab_editInvalidPosition;

  /// No description provided for @tab_editNoOtherString.
  ///
  /// In es, this message translates to:
  /// **'No hay otra cuerda en esa dirección.'**
  String get tab_editNoOtherString;

  /// No description provided for @tab_editNotes.
  ///
  /// In es, this message translates to:
  /// **'Editar notas'**
  String get tab_editNotes;

  /// No description provided for @tab_editNothingSelected.
  ///
  /// In es, this message translates to:
  /// **'No hay nada seleccionado.'**
  String get tab_editNothingSelected;

  /// No description provided for @tab_editNoTieOrigin.
  ///
  /// In es, this message translates to:
  /// **'No hay una nota anterior igual en esa cuerda a la que ligarla.'**
  String get tab_editNoTieOrigin;

  /// No description provided for @tab_editStringOccupied.
  ///
  /// In es, this message translates to:
  /// **'Ya hay una nota en esa cuerda en ese punto.'**
  String get tab_editStringOccupied;

  /// No description provided for @tab_editWrongKind.
  ///
  /// In es, this message translates to:
  /// **'Esa edición no vale para esta pista.'**
  String get tab_editWrongKind;

  /// No description provided for @tab_emptyBody.
  ///
  /// In es, this message translates to:
  /// **'Este tema no tiene stems de guitarra, bajo o batería con audio.'**
  String get tab_emptyBody;

  /// No description provided for @tab_emptyTitle.
  ///
  /// In es, this message translates to:
  /// **'No hay pistas que transcribir'**
  String get tab_emptyTitle;

  /// No description provided for @tab_exportGuitarPro.
  ///
  /// In es, this message translates to:
  /// **'Exportar a Guitar Pro'**
  String get tab_exportGuitarPro;

  /// No description provided for @tab_failedTitle.
  ///
  /// In es, this message translates to:
  /// **'No se pudo transcribir'**
  String get tab_failedTitle;

  /// No description provided for @tab_flashExportFailed.
  ///
  /// In es, this message translates to:
  /// **'No se pudo exportar: {error}'**
  String tab_flashExportFailed(String error);

  /// No description provided for @tab_flashNoHits.
  ///
  /// In es, this message translates to:
  /// **'No hay golpes seleccionados.'**
  String get tab_flashNoHits;

  /// No description provided for @tab_flashNoNote.
  ///
  /// In es, this message translates to:
  /// **'No hay ninguna nota seleccionada.'**
  String get tab_flashNoNote;

  /// No description provided for @tab_flashNoSoundfont.
  ///
  /// In es, this message translates to:
  /// **'Falta el soundfont de alphaTab en la app.'**
  String get tab_flashNoSoundfont;

  /// No description provided for @tab_flashRetuned.
  ///
  /// In es, this message translates to:
  /// **'{n, plural, =1{1 nota se movió una octava} other{{n} notas se movieron una octava}} y {dropped} se quitaron por no caber en la afinación.'**
  String tab_flashRetuned(int n, String dropped);

  /// No description provided for @tab_flashSaveFailed.
  ///
  /// In es, this message translates to:
  /// **'No se pudo guardar la tablatura: {error}'**
  String tab_flashSaveFailed(String error);

  /// No description provided for @tab_flashSaved.
  ///
  /// In es, this message translates to:
  /// **'Guardado {file}.'**
  String tab_flashSaved(String file);

  /// No description provided for @tab_flashSynthFailed.
  ///
  /// In es, this message translates to:
  /// **'No se pudo sintetizar la pista: {error}'**
  String tab_flashSynthFailed(String error);

  /// No description provided for @tab_footerAutomatic.
  ///
  /// In es, this message translates to:
  /// **'Transcripción automática · revisa y corrige si hace falta'**
  String get tab_footerAutomatic;

  /// No description provided for @tab_footerSongsterr.
  ///
  /// In es, this message translates to:
  /// **'Tablatura de Songsterr · revisa y corrige si hace falta'**
  String get tab_footerSongsterr;

  /// No description provided for @tab_headerSummary.
  ///
  /// In es, this message translates to:
  /// **'{bar} · {bpm} BPM'**
  String tab_headerSummary(String bar, int bpm);

  /// No description provided for @tab_issueFormatChanged.
  ///
  /// In es, this message translates to:
  /// **'Songsterr ha cambiado su formato.'**
  String get tab_issueFormatChanged;

  /// No description provided for @tab_issueHttp.
  ///
  /// In es, this message translates to:
  /// **'Songsterr respondió con el error {code}.'**
  String tab_issueHttp(int code);

  /// No description provided for @tab_issueInvalidLink.
  ///
  /// In es, this message translates to:
  /// **'Ese enlace no es de Songsterr.'**
  String get tab_issueInvalidLink;

  /// No description provided for @tab_issueNoResults.
  ///
  /// In es, this message translates to:
  /// **'No está en Songsterr.'**
  String get tab_issueNoResults;

  /// No description provided for @tab_issueOffline.
  ///
  /// In es, this message translates to:
  /// **'No se pudo conectar con Songsterr. Comprueba la conexión.'**
  String get tab_issueOffline;

  /// No description provided for @tab_issueRateLimited.
  ///
  /// In es, this message translates to:
  /// **'Songsterr está limitando las peticiones. Espera un poco y vuelve a intentarlo.'**
  String get tab_issueRateLimited;

  /// No description provided for @tab_keysHintMac.
  ///
  /// In es, this message translates to:
  /// **'Dígitos: traste · ↑ ↓: cuerda · ← →: mover · +/−: duración · ⌘Z deshacer'**
  String get tab_keysHintMac;

  /// No description provided for @tab_keysHintWin.
  ///
  /// In es, this message translates to:
  /// **'Dígitos: traste · ↑ ↓: cuerda · ← →: mover · +/−: duración · Ctrl+Z deshacer'**
  String get tab_keysHintWin;

  /// No description provided for @tab_listenLabel.
  ///
  /// In es, this message translates to:
  /// **'Oír'**
  String get tab_listenLabel;

  /// No description provided for @tab_listenMixed.
  ///
  /// In es, this message translates to:
  /// **'Mixto'**
  String get tab_listenMixed;

  /// No description provided for @tab_listenStems.
  ///
  /// In es, this message translates to:
  /// **'Stems'**
  String get tab_listenStems;

  /// No description provided for @tab_listenTrack.
  ///
  /// In es, this message translates to:
  /// **'Oír transcripción'**
  String get tab_listenTrack;

  /// No description provided for @tab_listenTranscription.
  ///
  /// In es, this message translates to:
  /// **'Transcripción'**
  String get tab_listenTranscription;

  /// No description provided for @tab_loop.
  ///
  /// In es, this message translates to:
  /// **'Bucle'**
  String get tab_loop;

  /// No description provided for @tab_loopActive.
  ///
  /// In es, this message translates to:
  /// **'Bucle: {name} · {from}–{to}'**
  String tab_loopActive(String name, String from, String to);

  /// No description provided for @tab_loopBar.
  ///
  /// In es, this message translates to:
  /// **'Compás {n}'**
  String tab_loopBar(int n);

  /// Nombre del bucle creado por arrastre; va en minúscula.
  ///
  /// In es, this message translates to:
  /// **'compás {n}'**
  String tab_loopBarName(int n);

  /// No description provided for @tab_loopFree.
  ///
  /// In es, this message translates to:
  /// **'libre'**
  String get tab_loopFree;

  /// No description provided for @tab_loopNone.
  ///
  /// In es, this message translates to:
  /// **'Sin bucle'**
  String get tab_loopNone;

  /// No description provided for @tab_loopSelection.
  ///
  /// In es, this message translates to:
  /// **'Selección'**
  String get tab_loopSelection;

  /// No description provided for @tab_metronome.
  ///
  /// In es, this message translates to:
  /// **'Metrónomo'**
  String get tab_metronome;

  /// No description provided for @tab_noticeAnd.
  ///
  /// In es, this message translates to:
  /// **'{a} y {b}'**
  String tab_noticeAnd(String a, String b);

  /// El texto de dropped incluye la cantidad y el sustantivo.
  ///
  /// In es, this message translates to:
  /// **'{dropped} se quitaron por no caber en las cuerdas'**
  String tab_noticeDropped(String dropped);

  /// No description provided for @tab_noticeRedone.
  ///
  /// In es, this message translates to:
  /// **'Se han rehecho: {tracks}. Su audio cambió, así que se perdieron las ediciones de esas pistas.'**
  String tab_noticeRedone(String tracks);

  /// No description provided for @tab_noticeShifted.
  ///
  /// In es, this message translates to:
  /// **'{n, plural, =1{1 nota fuera del registro de la afinación se subió o bajó una octava} other{{n} notas fuera del registro de la afinación se subieron o bajaron una octava}}'**
  String tab_noticeShifted(int n);

  /// No description provided for @tab_noticeTranscription.
  ///
  /// In es, this message translates to:
  /// **'Transcripción: {parts}.'**
  String tab_noticeTranscription(String parts);

  /// No description provided for @tab_pieceCrash.
  ///
  /// In es, this message translates to:
  /// **'platos'**
  String get tab_pieceCrash;

  /// No description provided for @tab_pieceHiHat.
  ///
  /// In es, this message translates to:
  /// **'charles'**
  String get tab_pieceHiHat;

  /// No description provided for @tab_pieceKick.
  ///
  /// In es, this message translates to:
  /// **'bombo'**
  String get tab_pieceKick;

  /// No description provided for @tab_pieceOpenHiHat.
  ///
  /// In es, this message translates to:
  /// **'charles abierto'**
  String get tab_pieceOpenHiHat;

  /// No description provided for @tab_pieceSnare.
  ///
  /// In es, this message translates to:
  /// **'caja'**
  String get tab_pieceSnare;

  /// No description provided for @tab_pieceTom.
  ///
  /// In es, this message translates to:
  /// **'tom'**
  String get tab_pieceTom;

  /// No description provided for @tab_redo.
  ///
  /// In es, this message translates to:
  /// **'Rehacer'**
  String get tab_redo;

  /// No description provided for @tab_selectionDrums.
  ///
  /// In es, this message translates to:
  /// **'{place} · {pieces}'**
  String tab_selectionDrums(String place, String pieces);

  /// No description provided for @tab_selectionNoHits.
  ///
  /// In es, this message translates to:
  /// **'sin golpes'**
  String get tab_selectionNoHits;

  /// No description provided for @tab_selectionNote.
  ///
  /// In es, this message translates to:
  /// **'{place} · cuerda {string}, traste {fret}'**
  String tab_selectionNote(String place, int string, int fret);

  /// No description provided for @tab_selectionNoNote.
  ///
  /// In es, this message translates to:
  /// **'{place} · cuerda {string}, sin nota'**
  String tab_selectionNoNote(String place, int string);

  /// No description provided for @tab_selectionPlace.
  ///
  /// In es, this message translates to:
  /// **'Compás {bar}, pulso {beat}'**
  String tab_selectionPlace(int bar, int beat);

  /// No description provided for @tab_sheetAccept.
  ///
  /// In es, this message translates to:
  /// **'Aceptar'**
  String get tab_sheetAccept;

  /// No description provided for @tab_sheetAllAutomatic.
  ///
  /// In es, this message translates to:
  /// **'Todo automático'**
  String get tab_sheetAllAutomatic;

  /// No description provided for @tab_sheetAutomatic.
  ///
  /// In es, this message translates to:
  /// **'Transcribir automáticamente'**
  String get tab_sheetAutomatic;

  /// No description provided for @tab_sheetBack.
  ///
  /// In es, this message translates to:
  /// **'Volver'**
  String get tab_sheetBack;

  /// No description provided for @tab_sheetBackShort.
  ///
  /// In es, this message translates to:
  /// **'Atrás'**
  String get tab_sheetBackShort;

  /// No description provided for @tab_sheetCancel.
  ///
  /// In es, this message translates to:
  /// **'Cancelar'**
  String get tab_sheetCancel;

  /// No description provided for @tab_sheetClose.
  ///
  /// In es, this message translates to:
  /// **'Cerrar'**
  String get tab_sheetClose;

  /// No description provided for @tab_sheetConfidenceUnmeasured.
  ///
  /// In es, this message translates to:
  /// **'sin medir'**
  String get tab_sheetConfidenceUnmeasured;

  /// No description provided for @tab_sheetExtraTracks.
  ///
  /// In es, this message translates to:
  /// **'Pistas extra, sin stem: {names}. Entran en la tablatura y en el .gp y solo suenan con «Oír transcripción».'**
  String tab_sheetExtraTracks(String names);

  /// No description provided for @tab_sheetLinkHint.
  ///
  /// In es, this message translates to:
  /// **'O pega un enlace de Songsterr'**
  String get tab_sheetLinkHint;

  /// No description provided for @tab_sheetNoSolos.
  ///
  /// In es, this message translates to:
  /// **'Transcripción automática (el tema no tiene secciones de solo)'**
  String get tab_sheetNoSolos;

  /// No description provided for @tab_sheetOtherResults.
  ///
  /// In es, this message translates to:
  /// **'Otros resultados'**
  String get tab_sheetOtherResults;

  /// No description provided for @tab_sheetPairingHelp.
  ///
  /// In es, this message translates to:
  /// **'Qué pista de Songsterr va con cada stem. La confianza es el parecido medido con el audio.'**
  String get tab_sheetPairingHelp;

  /// No description provided for @tab_sheetPickAutomatic.
  ///
  /// In es, this message translates to:
  /// **'Transcripción automática'**
  String get tab_sheetPickAutomatic;

  /// No description provided for @tab_sheetPreview.
  ///
  /// In es, this message translates to:
  /// **'Vista previa'**
  String get tab_sheetPreview;

  /// No description provided for @tab_sheetReadingTracks.
  ///
  /// In es, this message translates to:
  /// **'Leyendo las pistas…'**
  String get tab_sheetReadingTracks;

  /// No description provided for @tab_sheetRetry.
  ///
  /// In es, this message translates to:
  /// **'Reintentar'**
  String get tab_sheetRetry;

  /// No description provided for @tab_sheetSearch.
  ///
  /// In es, this message translates to:
  /// **'Búsqueda: {query}'**
  String tab_sheetSearch(String query);

  /// No description provided for @tab_sheetSearching.
  ///
  /// In es, this message translates to:
  /// **'Buscando en Songsterr…'**
  String get tab_sheetSearching;

  /// No description provided for @tab_sheetSoloNone.
  ///
  /// In es, this message translates to:
  /// **'Ninguna'**
  String get tab_sheetSoloNone;

  /// No description provided for @tab_sheetSoloRow.
  ///
  /// In es, this message translates to:
  /// **'Solo {n} ({time})'**
  String tab_sheetSoloRow(int n, String time);

  /// No description provided for @tab_sheetSuggestAuto.
  ///
  /// In es, this message translates to:
  /// **'Puedes transcribir el tema automáticamente.'**
  String get tab_sheetSuggestAuto;

  /// No description provided for @tab_sheetTitle.
  ///
  /// In es, this message translates to:
  /// **'Tablatura de Songsterr'**
  String get tab_sheetTitle;

  /// No description provided for @tab_sheetUseLink.
  ///
  /// In es, this message translates to:
  /// **'Usar enlace'**
  String get tab_sheetUseLink;

  /// No description provided for @tab_sheetUseThis.
  ///
  /// In es, this message translates to:
  /// **'Usar esta'**
  String get tab_sheetUseThis;

  /// No description provided for @tab_sheetWorkingDownload.
  ///
  /// In es, this message translates to:
  /// **'Descargando pistas de Songsterr…'**
  String get tab_sheetWorkingDownload;

  /// No description provided for @tab_sheetWorkingRead.
  ///
  /// In es, this message translates to:
  /// **'Leyendo Songsterr…'**
  String get tab_sheetWorkingRead;

  /// No description provided for @tab_sourceAutomatic.
  ///
  /// In es, this message translates to:
  /// **'Transcripción automática'**
  String get tab_sourceAutomatic;

  /// No description provided for @tab_sourceChangePairing.
  ///
  /// In es, this message translates to:
  /// **'Cambiar emparejamiento…'**
  String get tab_sourceChangePairing;

  /// No description provided for @tab_sourceMenu.
  ///
  /// In es, this message translates to:
  /// **'Fuente: {source}'**
  String tab_sourceMenu(String source);

  /// No description provided for @tab_sourceNone.
  ///
  /// In es, this message translates to:
  /// **'Sin elegir'**
  String get tab_sourceNone;

  /// No description provided for @tab_sourceSongsterr.
  ///
  /// In es, this message translates to:
  /// **'Songsterr'**
  String get tab_sourceSongsterr;

  /// No description provided for @tab_sourceSongsterrSearch.
  ///
  /// In es, this message translates to:
  /// **'Buscar en Songsterr…'**
  String get tab_sourceSongsterrSearch;

  /// No description provided for @tab_synthFailedSoundfont.
  ///
  /// In es, this message translates to:
  /// **'Falta el soundfont en la app'**
  String get tab_synthFailedSoundfont;

  /// No description provided for @tab_synthProgress.
  ///
  /// In es, this message translates to:
  /// **'Sintetizando {done}/{total}…'**
  String tab_synthProgress(int done, int total);

  /// No description provided for @tab_synthRendering.
  ///
  /// In es, this message translates to:
  /// **'Sintetizando…'**
  String get tab_synthRendering;

  /// No description provided for @tab_tempo.
  ///
  /// In es, this message translates to:
  /// **'Tempo'**
  String get tab_tempo;

  /// No description provided for @tab_title.
  ///
  /// In es, this message translates to:
  /// **'Tablatura'**
  String get tab_title;

  /// No description provided for @tab_trackMuteLetter.
  ///
  /// In es, this message translates to:
  /// **'M'**
  String get tab_trackMuteLetter;

  /// No description provided for @tab_trackSoloLetter.
  ///
  /// In es, this message translates to:
  /// **'S'**
  String get tab_trackSoloLetter;

  /// No description provided for @tab_tuning.
  ///
  /// In es, this message translates to:
  /// **'Afinación'**
  String get tab_tuning;

  /// No description provided for @tab_tuningCustom.
  ///
  /// In es, this message translates to:
  /// **'Personalizada'**
  String get tab_tuningCustom;

  /// No description provided for @tab_tuningDropD.
  ///
  /// In es, this message translates to:
  /// **'Drop D'**
  String get tab_tuningDropD;

  /// No description provided for @tab_tuningHalfDown.
  ///
  /// In es, this message translates to:
  /// **'Medio tono abajo'**
  String get tab_tuningHalfDown;

  /// No description provided for @tab_tuningStandard.
  ///
  /// In es, this message translates to:
  /// **'Estándar'**
  String get tab_tuningStandard;

  /// No description provided for @tab_tuningWholeDown.
  ///
  /// In es, this message translates to:
  /// **'Un tono abajo'**
  String get tab_tuningWholeDown;

  /// No description provided for @tab_undo.
  ///
  /// In es, this message translates to:
  /// **'Deshacer'**
  String get tab_undo;

  /// No description provided for @tab_waitingAction.
  ///
  /// In es, this message translates to:
  /// **'Analizar'**
  String get tab_waitingAction;

  /// No description provided for @tab_waitingBody.
  ///
  /// In es, this message translates to:
  /// **'La tablatura necesita los compases y pulsos del análisis. Puedes lanzarlo desde Backing track.'**
  String get tab_waitingBody;

  /// No description provided for @tab_waitingTitle.
  ///
  /// In es, this message translates to:
  /// **'Esperando el análisis del tema'**
  String get tab_waitingTitle;

  /// No description provided for @tab_workingBody.
  ///
  /// In es, this message translates to:
  /// **'La primera vez tarda un poco. Lo hecho se guarda pista a pista.'**
  String get tab_workingBody;

  /// No description provided for @tab_workingTitle.
  ///
  /// In es, this message translates to:
  /// **'Transcribiendo…'**
  String get tab_workingTitle;

  /// Ancla del bloque record: añade las claves del área debajo, en orden alfabético; no edites otros bloques.
  ///
  /// In es, this message translates to:
  /// **''**
  String get recordAnchor;

  /// Ancla del bloque montage: añade las claves del área debajo, en orden alfabético; no edites otros bloques.
  ///
  /// In es, this message translates to:
  /// **''**
  String get montageAnchor;

  /// Ancla del bloque settings: añade las claves del área debajo, en orden alfabético; no edites otros bloques.
  ///
  /// In es, this message translates to:
  /// **''**
  String get settingsAnchor;

  /// Ajustes Idioma: nombre del idioma, no se traduce.
  ///
  /// In es, this message translates to:
  /// **'English'**
  String get settings_lang_en;

  /// Ajustes Idioma: nombre del idioma, no se traduce.
  ///
  /// In es, this message translates to:
  /// **'Español'**
  String get settings_lang_es;

  /// Ajustes Idioma: etiqueta del selector.
  ///
  /// In es, this message translates to:
  /// **'Idioma'**
  String get settings_lang_label;

  /// Ajustes Idioma: opción del selector.
  ///
  /// In es, this message translates to:
  /// **'Sistema'**
  String get settings_lang_system;

  /// Ajustes Idioma: título del grupo.
  ///
  /// In es, this message translates to:
  /// **'Idioma'**
  String get settings_lang_title;

  /// Ajustes Biblioteca: diálogo de carpeta, cancelar.
  ///
  /// In es, this message translates to:
  /// **'Cancelar'**
  String get settings_lib_cancel;

  /// Ajustes Biblioteca: botón cambiar carpeta.
  ///
  /// In es, this message translates to:
  /// **'Cambiar carpeta'**
  String get settings_lib_change;

  /// Ajustes Biblioteca: botón limpiar.
  ///
  /// In es, this message translates to:
  /// **'Limpiar tomas descartadas y stems'**
  String get settings_lib_clean;

  /// Ajustes Biblioteca: título del diálogo limpiar.
  ///
  /// In es, this message translates to:
  /// **'Limpiar toda la biblioteca'**
  String get settings_lib_cleanTitle;

  /// Ajustes Biblioteca: fila carpeta.
  ///
  /// In es, this message translates to:
  /// **'Carpeta de proyectos'**
  String get settings_lib_folder;

  /// Ajustes Biblioteca: diálogo de carpeta, opción mover.
  ///
  /// In es, this message translates to:
  /// **'Mover los temas aquí'**
  String get settings_lib_moveHere;

  /// Ajustes Biblioteca: estado de mover la carpeta.
  ///
  /// In es, this message translates to:
  /// **'Moviendo {percent}'**
  String settings_lib_moving(String percent);

  /// Ajustes Biblioteca: nota del grupo.
  ///
  /// In es, this message translates to:
  /// **'Una carpeta por tema, con sus stems, tomas y vídeo.'**
  String get settings_lib_note;

  /// Ajustes Biblioteca: diálogo de carpeta, opción apuntar.
  ///
  /// In es, this message translates to:
  /// **'Solo apuntar a esta carpeta'**
  String get settings_lib_pointOnly;

  /// Ajustes Biblioteca: diálogo de carpeta, pregunta.
  ///
  /// In es, this message translates to:
  /// **'«{path}»: ¿mover los temas existentes a la carpeta nueva o solo apuntar a ella?'**
  String settings_lib_relocateMessage(String path);

  /// Ajustes Biblioteca: título del grupo.
  ///
  /// In es, this message translates to:
  /// **'Biblioteca'**
  String get settings_lib_title;

  /// Ajustes Biblioteca: fila espacio.
  ///
  /// In es, this message translates to:
  /// **'Espacio usado'**
  String get settings_lib_usage;

  /// Ajustes Biblioteca: aviso con trabajo en curso.
  ///
  /// In es, this message translates to:
  /// **'Hay trabajo en curso. Espera a que terminen las separaciones y vuelve a cambiar la carpeta.'**
  String get settings_lib_workInProgress;

  /// Ajustes Modelos: botón borrar.
  ///
  /// In es, this message translates to:
  /// **'Borrar'**
  String get settings_models_delete;

  /// Ajustes Modelos: cuerpo del diálogo borrar.
  ///
  /// In es, this message translates to:
  /// **'Se volverá a descargar la próxima vez que separes un tema.'**
  String get settings_models_deleteMessage;

  /// Ajustes Modelos: título del diálogo borrar.
  ///
  /// In es, this message translates to:
  /// **'Borrar el modelo'**
  String get settings_models_deleteTitle;

  /// Ajustes Modelos: botón descargar.
  ///
  /// In es, this message translates to:
  /// **'Descargar'**
  String get settings_models_download;

  /// Ajustes Modelos: estado descargando.
  ///
  /// In es, this message translates to:
  /// **'Descargando {percent}'**
  String settings_models_downloading(String percent);

  /// Ajustes Modelos: estado de error.
  ///
  /// In es, this message translates to:
  /// **'Error'**
  String get settings_models_error;

  /// Ajustes Modelos: estado descargado.
  ///
  /// In es, this message translates to:
  /// **'Descargado · {size}'**
  String settings_models_installed(String size);

  /// Ajustes Modelos: estado instalando.
  ///
  /// In es, this message translates to:
  /// **'Instalando…'**
  String get settings_models_installing;

  /// Ajustes Modelos: nota del grupo.
  ///
  /// In es, this message translates to:
  /// **'Se descargan la primera vez que se usan.'**
  String get settings_models_note;

  /// Ajustes Modelos: estado pendiente.
  ///
  /// In es, this message translates to:
  /// **'Pendiente · {size}'**
  String settings_models_pending(String size);

  /// Ajustes Modelos: título del grupo.
  ///
  /// In es, this message translates to:
  /// **'Modelos'**
  String get settings_models_title;

  /// Ajustes Modelos: estado verificando.
  ///
  /// In es, this message translates to:
  /// **'Verificando…'**
  String get settings_models_verifying;

  /// Ajustes: subtítulo de la pantalla.
  ///
  /// In es, this message translates to:
  /// **'Se configura una vez y lo usan todas las pantallas. Se guarda en tu perfil de equipo.'**
  String get settings_subtitle;

  /// Ajustes: pestaña Audio.
  ///
  /// In es, this message translates to:
  /// **'Audio'**
  String get settings_tabAudio;

  /// Ajustes: pestaña Biblioteca.
  ///
  /// In es, this message translates to:
  /// **'Biblioteca'**
  String get settings_tabLibrary;

  /// Ajustes: pestaña Cámara y vídeo.
  ///
  /// In es, this message translates to:
  /// **'Cámara y vídeo'**
  String get settings_tabVideo;

  /// Ajustes Fuentes externas: estado comprobando.
  ///
  /// In es, this message translates to:
  /// **'comprobando…'**
  String get settings_tools_checking;

  /// Ajustes Fuentes externas: estado embebida.
  ///
  /// In es, this message translates to:
  /// **'embebida'**
  String get settings_tools_embedded;

  /// Ajustes Fuentes externas: nota del grupo.
  ///
  /// In es, this message translates to:
  /// **'Importar desde enlace usa yt-dlp, Deno y ffmpeg, que van dentro de la app. Si YouTube cambia y las descargas fallan, actualiza yt-dlp.'**
  String get settings_tools_note;

  /// Ajustes Fuentes externas: botón volver a la embebida.
  ///
  /// In es, this message translates to:
  /// **'Volver a la embebida'**
  String get settings_tools_revert;

  /// Ajustes Fuentes externas: título del grupo.
  ///
  /// In es, this message translates to:
  /// **'Fuentes externas'**
  String get settings_tools_title;

  /// Ajustes Fuentes externas: estado no disponible.
  ///
  /// In es, this message translates to:
  /// **'no disponible'**
  String get settings_tools_unavailable;

  /// Ajustes Fuentes externas: botón actualizar.
  ///
  /// In es, this message translates to:
  /// **'Actualizar yt-dlp'**
  String get settings_tools_update;

  /// Ajustes Fuentes externas: estado actualizada.
  ///
  /// In es, this message translates to:
  /// **'actualizada'**
  String get settings_tools_updated;

  /// Ancla del bloque error: añade las claves del área debajo, en orden alfabético; no edites otros bloques.
  ///
  /// In es, this message translates to:
  /// **''**
  String get errorAnchor;

  /// No description provided for @error_unknown.
  ///
  /// In es, this message translates to:
  /// **'Error desconocido'**
  String get error_unknown;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
