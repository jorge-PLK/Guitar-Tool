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

  /// Ancla del bloque tab: añade las claves del área debajo, en orden alfabético; no edites otros bloques.
  ///
  /// In es, this message translates to:
  /// **''**
  String get tabAnchor;

  /// Ancla del bloque record: añade las claves del área debajo, en orden alfabético; no edites otros bloques.
  ///
  /// In es, this message translates to:
  /// **''**
  String get recordAnchor;

  /// Grabar, partes: botón añadir parte (RV:200).
  ///
  /// In es, this message translates to:
  /// **'Añadir parte'**
  String get record_addPart;

  /// Grabar, añadir parte: botón confirmar (RV:349).
  ///
  /// In es, this message translates to:
  /// **'Añadir'**
  String get record_addPartAdd;

  /// Grabar, añadir parte: campo del nombre (RV:341).
  ///
  /// In es, this message translates to:
  /// **'Nombre de la parte'**
  String get record_addPartName;

  /// Grabar, añadir parte: opción sin guitarra sustituida (RV:343).
  ///
  /// In es, this message translates to:
  /// **'Ninguna (parte añadida)'**
  String get record_addPartNone;

  /// Grabar, añadir parte: selector de guitarra sustituida (RV:342).
  ///
  /// In es, this message translates to:
  /// **'Guitarra que sustituye'**
  String get record_addPartReplaces;

  /// Grabar, añadir parte: título del diálogo (RV:340).
  ///
  /// In es, this message translates to:
  /// **'Añadir parte'**
  String get record_addPartTitle;

  /// Grabar, bloqueo: punch sin marcas (RC:505).
  ///
  /// In es, this message translates to:
  /// **'Marca la entrada y la salida del punch-in en la línea de tiempo.'**
  String get record_blockMarkPunch;

  /// Grabar, bloqueo: falta la parte (RC:502).
  ///
  /// In es, this message translates to:
  /// **'Elige una parte.'**
  String get record_blockPickPart;

  /// Grabar, bloqueo: falta la toma (RC:504).
  ///
  /// In es, this message translates to:
  /// **'Elige la toma sobre la que hacer el punch-in.'**
  String get record_blockPickTake;

  /// Grabar, aviso: cámara sin vídeo (RV:174, 176).
  ///
  /// In es, this message translates to:
  /// **'{message} Se grabará solo el audio.'**
  String record_cameraAudioOnly(String message);

  /// Grabar, aviso: permiso de cámara denegado (RV:175; decisión 16).
  ///
  /// In es, this message translates to:
  /// **'Sin permiso de cámara: se grabará solo el audio. Concédelo en Ajustes del Sistema > Privacidad > Cámara.'**
  String get record_cameraDenied;

  /// Grabar, aviso: la cámara elegida no está conectada (RC:430).
  ///
  /// In es, this message translates to:
  /// **'La cámara elegida en Ajustes no está conectada.'**
  String get record_cameraMissing;

  /// Grabar, aviso: no hay cámara (RC:430).
  ///
  /// In es, this message translates to:
  /// **'No hay ninguna cámara conectada.'**
  String get record_cameraNone;

  /// Grabar, error: no se pudo abrir la cámara (RC:443, 468).
  ///
  /// In es, this message translates to:
  /// **'No se pudo abrir la cámara ({error}).'**
  String record_cameraOpenFailed(String error);

  /// Grabar, aviso: cámara desconectada durante la grabación (RC:492).
  ///
  /// In es, this message translates to:
  /// **'Se desconectó la cámara: se grabará solo el audio.'**
  String get record_cameraUnplugged;

  /// Grabar, botón cancelar (RV:137, 348; OS:74).
  ///
  /// In es, this message translates to:
  /// **'Cancelar'**
  String get record_cancel;

  /// Grabar, selector vacío (RV:31).
  ///
  /// In es, this message translates to:
  /// **'Aún no hay temas separados. Importa uno y sepáralo en la biblioteca.'**
  String get record_chooserEmpty;

  /// Grabar, selector: instrucción (RV:33).
  ///
  /// In es, this message translates to:
  /// **'Elige un tema'**
  String get record_chooserPick;

  /// Grabar, arranque: opción cuenta de 1 compás (RV:506).
  ///
  /// In es, this message translates to:
  /// **'Cuenta de 1 compás'**
  String get record_countIn;

  /// Grabar, borrar toma: cuerpo del diálogo (RV:139).
  ///
  /// In es, this message translates to:
  /// **'Se borra su carpeta (audio y vídeo). No se puede deshacer.'**
  String get record_deleteBody;

  /// Grabar, borrar toma: botón confirmar (RV:136).
  ///
  /// In es, this message translates to:
  /// **'Borrar toma'**
  String get record_deleteConfirm;

  /// Grabar, borrar toma: título del diálogo (RV:134).
  ///
  /// In es, this message translates to:
  /// **'¿Borrar la toma?'**
  String get record_deleteTitle;

  /// Grabar, duración: ayuda del modo automático (RV:493).
  ///
  /// In es, this message translates to:
  /// **'Para sola al acabar la sección más el margen'**
  String get record_durationHelpAuto;

  /// Grabar, duración: ayuda del tema (RV:493).
  ///
  /// In es, this message translates to:
  /// **'Duración del tema'**
  String get record_durationHelpTheme;

  /// Grabar, error: borrar toma (RC:801).
  ///
  /// In es, this message translates to:
  /// **'No se pudo borrar la toma ({error}).'**
  String record_errDelete(String error);

  /// Grabar, error: dispositivo cerrado (RC:557).
  ///
  /// In es, this message translates to:
  /// **'El dispositivo no está abierto.'**
  String get record_errDeviceClosed;

  /// Grabar, error: cargar tomas anteriores (RC:388).
  ///
  /// In es, this message translates to:
  /// **'No se pudieron cargar tus tomas anteriores ({error}).'**
  String record_errPriorTakes(String error);

  /// Grabar, error: toma del punch no encontrada (RC:814).
  ///
  /// In es, this message translates to:
  /// **'No se encontró la toma del punch.'**
  String get record_errPunchTake;

  /// Grabar, error: guardar toma (RC:596).
  ///
  /// In es, this message translates to:
  /// **'No se pudo guardar la toma.'**
  String get record_errSave;

  /// Grabar, error: empezar a grabar (RC:583).
  ///
  /// In es, this message translates to:
  /// **'No se pudo empezar a grabar.'**
  String get record_errStart;

  /// Grabar, error: cargar stems (RC:335).
  ///
  /// In es, this message translates to:
  /// **'No se pudieron cargar los stems ({error}).'**
  String record_errStems(String error);

  /// Grabar, error: grabar toma (RC:632).
  ///
  /// In es, this message translates to:
  /// **'No se pudo grabar la toma ({error}).'**
  String record_errTake(String error);

  /// Grabar, mezclador: etiqueta de accesibilidad del fader (BM:307).
  ///
  /// In es, this message translates to:
  /// **'Volumen'**
  String get record_faderA11y;

  /// Grabar, sin separar: botón ir a la biblioteca (RV:62).
  ///
  /// In es, this message translates to:
  /// **'Ir a la biblioteca'**
  String get record_goLibrary;

  /// Grabar, cabecera: botón ir al montaje (RV:155).
  ///
  /// In es, this message translates to:
  /// **'Ir al montaje'**
  String get record_goMontage;

  /// Grabar, cabecera: ayuda del botón montaje (RV:162).
  ///
  /// In es, this message translates to:
  /// **'Monta las mejores tomas en un vídeo'**
  String get record_goMontageHelp;

  /// Grabar, cabecera: indicador de multitoma (RV:149).
  ///
  /// In es, this message translates to:
  /// **'Multitoma'**
  String get record_headerMulti;

  /// Grabar, mezclador: nivel de entrada, accesibilidad (RM:86, 214).
  ///
  /// In es, this message translates to:
  /// **'Nivel de la entrada de guitarra'**
  String get record_inputLevelA11y;

  /// Grabar, mezclador: etiqueta de la entrada (RM:208).
  ///
  /// In es, this message translates to:
  /// **'Entrada'**
  String get record_inputWord;

  /// Grabar, mezclador: canal master (RM:70, 178).
  ///
  /// In es, this message translates to:
  /// **'Master'**
  String get record_master;

  /// Grabar, menú de toma: marcar como mejor (RV:274).
  ///
  /// In es, this message translates to:
  /// **'Marcar como mejor'**
  String get record_menuBest;

  /// Grabar, menú de toma: borrar (RV:278).
  ///
  /// In es, this message translates to:
  /// **'Borrar…'**
  String get record_menuDelete;

  /// Grabar, menú de toma: ajustar desfase (RV:275).
  ///
  /// In es, this message translates to:
  /// **'Ajustar desfase…'**
  String get record_menuOffset;

  /// Grabar, menú de toma: punch-in (RV:276).
  ///
  /// In es, this message translates to:
  /// **'Punch-in'**
  String get record_menuPunch;

  /// Grabar, mezclador: expandir (RM:29).
  ///
  /// In es, this message translates to:
  /// **'Expandir'**
  String get record_mixerExpand;

  /// Grabar, mezclador: expandir, accesibilidad (RM:34).
  ///
  /// In es, this message translates to:
  /// **'Expandir el mezclador'**
  String get record_mixerExpandA11y;

  /// Grabar, mezclador: plegar (RM:29).
  ///
  /// In es, this message translates to:
  /// **'Plegar'**
  String get record_mixerFold;

  /// Grabar, mezclador: plegar, accesibilidad (RM:34).
  ///
  /// In es, this message translates to:
  /// **'Plegar el mezclador'**
  String get record_mixerFoldA11y;

  /// Grabar, mezclador: salida; «—» si vacío lo resuelve el código (RM:26).
  ///
  /// In es, this message translates to:
  /// **'Salida: {device}'**
  String record_mixerOutput(String device);

  /// Grabar, mezclador: título (RM:24).
  ///
  /// In es, this message translates to:
  /// **'Mezclador'**
  String get record_mixerTitle;

  /// Grabar, mezclador: botón M, accesibilidad (BM:181; RM:129).
  ///
  /// In es, this message translates to:
  /// **'Silenciar {name}'**
  String record_muteA11y(String name);

  /// Grabar, mezclador: estado silenciado (BM:178).
  ///
  /// In es, this message translates to:
  /// **'Silenciado'**
  String get record_muted;

  /// Grabar, sin separar: cuerpo (RV:61).
  ///
  /// In es, this message translates to:
  /// **'Grabar necesita los stems. Sepáralo desde la biblioteca y vuelve.'**
  String get record_notSeparatedBody;

  /// Grabar, sin separar: título (RV:60).
  ///
  /// In es, this message translates to:
  /// **'Este tema aún no está separado'**
  String get record_notSeparatedTitle;

  /// Grabar, aviso: sin fotogramas (RC:614).
  ///
  /// In es, this message translates to:
  /// **'No llegaron fotogramas de la cámara: la toma es solo de audio.'**
  String get record_noticeNoFrames;

  /// Grabar, aviso: toma detenida (RC:598).
  ///
  /// In es, this message translates to:
  /// **'La toma se detuvo y se guardó lo grabado.'**
  String get record_noticeStopped;

  /// Ajustar desfase: botón descartar (OS:74).
  ///
  /// In es, this message translates to:
  /// **'Descartar toma'**
  String get record_offsetDiscard;

  /// Ajustar desfase: nota del fotograma (OS:67).
  ///
  /// In es, this message translates to:
  /// **'Fotograma = {ms} ms'**
  String record_offsetFrameNote(int ms);

  /// Ajustar desfase: ayuda (OS:31).
  ///
  /// In es, this message translates to:
  /// **'Dale al play y mueve el desfase hasta que imagen y sonido coincidan (un golpe seco en las cuerdas ayuda). Positivo = la imagen llega tarde.'**
  String get record_offsetHelp;

  /// Ajustar desfase: error al abrir la toma (OS:119).
  ///
  /// In es, this message translates to:
  /// **'No se pudo abrir la toma ({error}).'**
  String record_offsetLoadError(String error);

  /// Ajustar desfase: casilla de desfase por defecto (OS:70).
  ///
  /// In es, this message translates to:
  /// **'Guardar como desfase por defecto de esta cámara ({camera})'**
  String record_offsetMakeDefault(String camera);

  /// Ajustar desfase: botón −1 fotograma (OS:55).
  ///
  /// In es, this message translates to:
  /// **'−1 fotograma'**
  String get record_offsetMinusFrame;

  /// Ajustar desfase: botón −1 ms (OS:56).
  ///
  /// In es, this message translates to:
  /// **'−1 ms'**
  String get record_offsetMinusMs;

  /// Ajustar desfase: campo, accesibilidad (OS:61).
  ///
  /// In es, this message translates to:
  /// **'Desfase en milisegundos'**
  String get record_offsetMsA11y;

  /// Ajustar desfase: botón reproducir o pausa (OS:48).
  ///
  /// In es, this message translates to:
  /// **'Reproducir / pausa'**
  String get record_offsetPlayPause;

  /// Ajustar desfase: botón +1 fotograma (OS:65).
  ///
  /// In es, this message translates to:
  /// **'+1 fotograma'**
  String get record_offsetPlusFrame;

  /// Ajustar desfase: botón +1 ms (OS:64).
  ///
  /// In es, this message translates to:
  /// **'+1 ms'**
  String get record_offsetPlusMs;

  /// Ajustar desfase: volver al principio (OS:50).
  ///
  /// In es, this message translates to:
  /// **'Al principio'**
  String get record_offsetRestart;

  /// Ajustar desfase: botón guardar (OS:79).
  ///
  /// In es, this message translates to:
  /// **'Guardar'**
  String get record_offsetSave;

  /// Ajustar desfase: botón guardar toma (OS:79).
  ///
  /// In es, this message translates to:
  /// **'Guardar toma'**
  String get record_offsetSaveTake;

  /// Ajustar desfase: título (OS:30).
  ///
  /// In es, this message translates to:
  /// **'Ajustar desfase'**
  String get record_offsetTitle;

  /// Ajustar desfase: unidad (OS:62).
  ///
  /// In es, this message translates to:
  /// **'ms'**
  String get record_offsetUnit;

  /// Cabecera de grabación: desfase sin ajustar (RV:533).
  ///
  /// In es, this message translates to:
  /// **'Desfase de la cámara: sin ajustar'**
  String get record_offsetUnset;

  /// Cabecera de grabación: desfase con valor; el signo «+» lo pone el código (RV:533).
  ///
  /// In es, this message translates to:
  /// **'Desfase de la cámara: {ms} ms'**
  String record_offsetValue(String ms);

  /// Grabar, partes: estado de parte añadida (RV:218).
  ///
  /// In es, this message translates to:
  /// **'Parte añadida'**
  String get record_partAdded;

  /// Grabar, partes: guitarra sustituida (RV:218).
  ///
  /// In es, this message translates to:
  /// **'Sustituye: {guitar}'**
  String record_partReplaces(String guitar);

  /// Grabar, partes: título (RV:195).
  ///
  /// In es, this message translates to:
  /// **'Partes'**
  String get record_parts;

  /// Grabar, partes: ayuda (RV:196).
  ///
  /// In es, this message translates to:
  /// **'En cada toma suena el backing sin esa parte y con tus tomas anteriores.'**
  String get record_partsHelp;

  /// Grabar, arranque: etiqueta del margen (RV:509).
  ///
  /// In es, this message translates to:
  /// **'Margen'**
  String get record_preRoll;

  /// Grabar, arranque: margen de 0 compases (RV:512).
  ///
  /// In es, this message translates to:
  /// **'Sin margen'**
  String get record_preRoll0;

  /// Grabar, arranque: margen de 1 compás (RV:511).
  ///
  /// In es, this message translates to:
  /// **'1 compás'**
  String get record_preRoll1;

  /// Grabar, arranque: margen de 2 compases (RV:510).
  ///
  /// In es, this message translates to:
  /// **'2 compases'**
  String get record_preRoll2;

  /// Grabar, vista previa: sin vídeo (RV:400).
  ///
  /// In es, this message translates to:
  /// **'Sin vídeo: se grabará solo el audio'**
  String get record_previewNoVideo;

  /// Grabar, vista previa de la cámara (RV:398); camera por defecto «simulada».
  ///
  /// In es, this message translates to:
  /// **'Vista previa de la cámara · {camera} (simulada)'**
  String record_previewSimulated(String camera);

  /// Grabar, punch-in: marca de entrada, accesibilidad (PT:64).
  ///
  /// In es, this message translates to:
  /// **'Entrada del punch-in'**
  String get record_punchEntryA11y;

  /// Grabar, punch-in: marca de salida, accesibilidad (PT:64).
  ///
  /// In es, this message translates to:
  /// **'Salida del punch-in'**
  String get record_punchExitA11y;

  /// Grabar, punch-in: ayuda, versión macOS (PT:54).
  ///
  /// In es, this message translates to:
  /// **'Haz clic para marcar la entrada y después la salida; arrastra las marcas para moverlas (⌥ = libre, sin imán al compás).'**
  String get record_punchHelp_mac;

  /// Grabar, punch-in: ayuda, versión Windows (PT:54; web punch.js:73).
  ///
  /// In es, this message translates to:
  /// **'Haz clic para marcar la entrada y después la salida; arrastra las marcas para moverlas (Alt = libre, sin imán al compás).'**
  String get record_punchHelp_win;

  /// Grabar, punch-in: resumen de marcas; «—» sin marca y formato m:ss,d lo resuelve el código (PT:67-69).
  ///
  /// In es, this message translates to:
  /// **'Entrada {entry} · Salida {exit}'**
  String record_punchSummary(String entry, String exit);

  /// Grabar, punch-in: título (PT:20).
  ///
  /// In es, this message translates to:
  /// **'Punch-in'**
  String get record_punchTitle;

  /// Grabar, arranque: interruptor de punch-in (RV:516).
  ///
  /// In es, this message translates to:
  /// **'Punch-in'**
  String get record_punchToggle;

  /// Grabar, arranque: ayuda del punch-in (RV:521).
  ///
  /// In es, this message translates to:
  /// **'Vuelve a grabar un tramo de una toma'**
  String get record_punchToggleHelp;

  /// Grabar, cabecera de toma: prefijo de la píldora REC (RV:434).
  ///
  /// In es, this message translates to:
  /// **'REC · '**
  String get record_recPrefix;

  /// Grabar, cámara: botón rotar (RV:444).
  ///
  /// In es, this message translates to:
  /// **'Rotar'**
  String get record_rotate;

  /// Grabar, cámara: rotar, accesibilidad (RV:450).
  ///
  /// In es, this message translates to:
  /// **'Rotar cámara, ahora {degrees} grados'**
  String record_rotateA11y(int degrees);

  /// Grabar, cámara: botón rotar con grados (RV:444).
  ///
  /// In es, this message translates to:
  /// **'Rotar · {degrees}°'**
  String record_rotateDegrees(int degrees);

  /// Grabar, cámara: ayuda de rotar (RV:449).
  ///
  /// In es, this message translates to:
  /// **'Gira la imagen de esta cámara 90° en sentido horario (no se recodifica; se aplica al ver y montar)'**
  String get record_rotateHelp;

  /// Grabar, mezclador: botón S, accesibilidad (BM:182; RM:130).
  ///
  /// In es, this message translates to:
  /// **'Solo {name}'**
  String record_soloA11y(String name);

  /// Grabar, controles: botón empezar (RV:480, 489).
  ///
  /// In es, this message translates to:
  /// **'Grabar'**
  String get record_start;

  /// Grabar, arranque: etiqueta (RV:500).
  ///
  /// In es, this message translates to:
  /// **'Empezar en'**
  String get record_startAt;

  /// Grabar, arranque: opción principio (RV:501).
  ///
  /// In es, this message translates to:
  /// **'Principio'**
  String get record_startBeginning;

  /// Grabar, partes: estado hecha (RV:235).
  ///
  /// In es, this message translates to:
  /// **'Hecha'**
  String get record_statusDone;

  /// Grabar, partes: estado pendiente (RV:237).
  ///
  /// In es, this message translates to:
  /// **'Pendiente'**
  String get record_statusPending;

  /// Grabar, partes: estado grabando (RV:236).
  ///
  /// In es, this message translates to:
  /// **'Grabando'**
  String get record_statusRecording;

  /// Grabar, mezclador: stem bajo (RM:16).
  ///
  /// In es, this message translates to:
  /// **'Bajo'**
  String get record_stemBass;

  /// Grabar, mezclador: stem batería (RM:16).
  ///
  /// In es, this message translates to:
  /// **'Batería'**
  String get record_stemDrums;

  /// Grabar, mezclador: stem guitarra (RM:16).
  ///
  /// In es, this message translates to:
  /// **'Guitarra'**
  String get record_stemGuitar;

  /// Grabar, mezclador: stem resto (RM:16).
  ///
  /// In es, this message translates to:
  /// **'Resto'**
  String get record_stemOther;

  /// Grabar, mezclador: stem piano (RM:16).
  ///
  /// In es, this message translates to:
  /// **'Piano'**
  String get record_stemPiano;

  /// Grabar, mezclador: stem voz (RM:16).
  ///
  /// In es, this message translates to:
  /// **'Voz'**
  String get record_stemVocals;

  /// Grabar, controles: botón parar (RV:480).
  ///
  /// In es, this message translates to:
  /// **'Parar'**
  String get record_stop;

  /// Grabar, controles: parar, accesibilidad (RV:489).
  ///
  /// In es, this message translates to:
  /// **'Parar la grabación'**
  String get record_stopA11y;

  /// Grabar, tomas: nombre de la toma (RV:280).
  ///
  /// In es, this message translates to:
  /// **'Toma {n}'**
  String record_take(int n);

  /// Grabar, tomas: toma, accesibilidad (RV:291).
  ///
  /// In es, this message translates to:
  /// **'Toma {n}'**
  String record_takeA11y(int n);

  /// Grabar, tomas: toma marcada como mejor, accesibilidad (RV:291; variante creada).
  ///
  /// In es, this message translates to:
  /// **'Toma {n}, mejor'**
  String record_takeA11yBest(int n);

  /// Grabar, tomas: toma marcada como mejor (RV:280).
  ///
  /// In es, this message translates to:
  /// **'Toma {n} · mejor'**
  String record_takeBest(int n);

  /// Grabar, cabecera de toma: píldora con parte (RV:434).
  ///
  /// In es, this message translates to:
  /// **'Toma {n} · {part}'**
  String record_takePill(int n, String part);

  /// Grabar: título de la pantalla (RV:29, 151).
  ///
  /// In es, this message translates to:
  /// **'Grabar'**
  String get record_title;

  /// Grabar, aviso: toma sin calibrar (BackingRecord.swift:46; RV:172).
  ///
  /// In es, this message translates to:
  /// **'Sin calibrar: la toma puede ir desfasada decenas de ms; se corregirá al calibrar.'**
  String get record_uncalibrated;

  /// Grabar, mezclador: botón M activo, accesibilidad (BM:181; RM:129).
  ///
  /// In es, this message translates to:
  /// **'Activar {name}'**
  String record_unmuteA11y(String name);

  /// Grabar, tomas: ayuda de ver toma (RV:267).
  ///
  /// In es, this message translates to:
  /// **'Ver toma'**
  String get record_viewTake;

  /// Grabar, tomas: ver toma, accesibilidad (RV:267).
  ///
  /// In es, this message translates to:
  /// **'Ver toma {n}'**
  String record_viewTakeA11y(int n);

  /// Visor de toma: título (RV:254).
  ///
  /// In es, this message translates to:
  /// **'Toma {n} · {part}'**
  String record_viewerTitle(int n, String part);

  /// Grabar, mezclador: canal de tu guitarra (RM:77, 197).
  ///
  /// In es, this message translates to:
  /// **'Tu guitarra'**
  String get record_yourGuitar;

  /// Visor de toma: botón backing (TV:349).
  ///
  /// In es, this message translates to:
  /// **'Backing'**
  String get takeview_backing;

  /// Visor de toma: ayuda de silenciar backing (TV:357).
  ///
  /// In es, this message translates to:
  /// **'Silenciar el backing'**
  String get takeview_backingMuteHelp;

  /// Visor de toma: backing silenciado (TV:349).
  ///
  /// In es, this message translates to:
  /// **'Backing mudo'**
  String get takeview_backingMuted;

  /// Visor de toma: ayuda de oír backing (TV:357).
  ///
  /// In es, this message translates to:
  /// **'Oír el backing'**
  String get takeview_backingUnmuteHelp;

  /// Visor de toma: chip de mejor (TV:307).
  ///
  /// In es, this message translates to:
  /// **'★ mejor'**
  String get takeview_bestChip;

  /// Visor de toma: cerrar, ayuda y etiqueta (TV:312-313).
  ///
  /// In es, this message translates to:
  /// **'Cerrar'**
  String get takeview_close;

  /// Visor de toma: eliminar (TV:365).
  ///
  /// In es, this message translates to:
  /// **'Eliminar…'**
  String get takeview_delete;

  /// Visor de toma: cuerpo de eliminar (TV:299).
  ///
  /// In es, this message translates to:
  /// **'Se borra su carpeta (audio y vídeo). No se puede deshacer.'**
  String get takeview_deleteBody;

  /// Visor de toma: botón confirmar eliminar (TV:296).
  ///
  /// In es, this message translates to:
  /// **'Eliminar toma'**
  String get takeview_deleteConfirm;

  /// Visor de toma: título de eliminar (TV:295).
  ///
  /// In es, this message translates to:
  /// **'¿Eliminar la toma?'**
  String get takeview_deleteTitle;

  /// Visor de toma: fragmento de error dentro de {error} (TV:136).
  ///
  /// In es, this message translates to:
  /// **'no se pudo leer el audio {file}'**
  String takeview_errInnerAudio(String file);

  /// Visor de toma: fragmento de error dentro de {error} (TV:135).
  ///
  /// In es, this message translates to:
  /// **'la toma no tiene audio procesado'**
  String get takeview_errInnerNoAudio;

  /// Visor de toma: sin audio (TV:205).
  ///
  /// In es, this message translates to:
  /// **'Esta toma no tiene audio que reproducir.'**
  String get takeview_errNoAudio;

  /// Visor de toma: error al preparar (TV:235).
  ///
  /// In es, this message translates to:
  /// **'No se pudo preparar la toma ({error}).'**
  String takeview_errPrepare(String error);

  /// Visor de toma: marcar como mejor (TV:363).
  ///
  /// In es, this message translates to:
  /// **'Marcar como mejor'**
  String get takeview_markBest;

  /// Visor de toma: sin vídeo (TV:324).
  ///
  /// In es, this message translates to:
  /// **'Sin vídeo: solo audio'**
  String get takeview_noVideo;

  /// Visor de toma: etiqueta de accesibilidad de pausa (TV:341).
  ///
  /// In es, this message translates to:
  /// **'Pausa'**
  String get takeview_pause;

  /// Visor de toma: etiqueta de accesibilidad de reproducir (TV:341).
  ///
  /// In es, this message translates to:
  /// **'Reproducir'**
  String get takeview_play;

  /// Visor de toma: etiqueta del deslizador de posición (solo web, viewer.js:38; no hay en Swift).
  ///
  /// In es, this message translates to:
  /// **'Posición'**
  String get takeview_position;

  /// Bloqueo de Grabar: busy (record-block-busy).
  ///
  /// In es, this message translates to:
  /// **'Hay una calibración o una grabación en marcha.'**
  String get record_block_busy;

  /// Bloqueo de Grabar: canales repetidos.
  ///
  /// In es, this message translates to:
  /// **'Los canales elegidos se repiten: revisa Ajustes · Audio.'**
  String get record_block_invalidChannels;

  /// Bloqueo de Grabar: entrada desconectada.
  ///
  /// In es, this message translates to:
  /// **'El dispositivo de entrada no está conectado.'**
  String get record_block_inputDisconnected;

  /// Bloqueo de Grabar: bucle activo.
  ///
  /// In es, this message translates to:
  /// **'Solo se graba sin bucle: quita el bucle.'**
  String get record_block_loop;

  /// Bloqueo de Grabar: sin entrada de guitarra.
  ///
  /// In es, this message translates to:
  /// **'Asigna la entrada de guitarra en Ajustes · Audio.'**
  String get record_block_noGuitarInput;

  /// Bloqueo de Grabar: sin dispositivo de entrada.
  ///
  /// In es, this message translates to:
  /// **'Elige un dispositivo de entrada en Ajustes · Audio.'**
  String get record_block_noInputDevice;

  /// Bloqueo de Grabar: sin parte.
  ///
  /// In es, this message translates to:
  /// **'Elige una parte.'**
  String get record_block_noPart;

  /// Bloqueo de Grabar: salida desconectada.
  ///
  /// In es, this message translates to:
  /// **'El dispositivo de salida no está conectado.'**
  String get record_block_outputDisconnected;

  /// Bloqueo de Grabar: punch-in sin marcas.
  ///
  /// In es, this message translates to:
  /// **'Marca la entrada y la salida del punch-in en la línea de tiempo.'**
  String get record_block_punchNoMarks;

  /// Bloqueo de Grabar: punch-in sin toma.
  ///
  /// In es, this message translates to:
  /// **'Elige la toma sobre la que hacer el punch-in.'**
  String get record_block_punchNoTake;

  /// Bloqueo de Grabar: frecuencias distintas.
  ///
  /// In es, this message translates to:
  /// **'El dispositivo está a {deviceHz} kHz y la frecuencia de trabajo es {workingHz} kHz'**
  String record_block_rateMismatch(num deviceHz, num workingHz);

  /// Bloqueo de Grabar: error del sistema; el texto es el propio error.
  ///
  /// In es, this message translates to:
  /// **'{detail}'**
  String record_block_sessionUnavailable(String detail);

  /// Bloqueo de Grabar: velocidad distinta de 100 %.
  ///
  /// In es, this message translates to:
  /// **'Solo se graba a velocidad 100 %: pon el tempo al 100 %.'**
  String record_block_speed(num rate);

  /// Ancla del bloque settings_audio: añade las claves del área debajo, en orden alfabético; no edites otros bloques.
  ///
  /// In es, this message translates to:
  /// **''**
  String get settingsAudioAnchor;

  /// Ajustes Audio: elección de salidas del backing.
  ///
  /// In es, this message translates to:
  /// **'Salidas {l} y {r} · estéreo'**
  String settings_audio_backingChoice(String l, String r);

  /// Ajustes Audio: canales de salida del backing.
  ///
  /// In es, this message translates to:
  /// **'Salida del backing'**
  String get settings_audio_backingOut;

  /// Bloqueo de calibrar: busy (audio-block-busy).
  ///
  /// In es, this message translates to:
  /// **'Hay una calibración o una grabación en marcha.'**
  String get settings_audio_block_busy;

  /// Bloqueo de calibrar: canales repetidos.
  ///
  /// In es, this message translates to:
  /// **'Los canales elegidos se repiten: revisa Ajustes · Audio.'**
  String get settings_audio_block_invalidChannels;

  /// Bloqueo de calibrar: entrada desconectada.
  ///
  /// In es, this message translates to:
  /// **'El dispositivo de entrada no está conectado.'**
  String get settings_audio_block_inputDisconnected;

  /// Bloqueo de calibrar: bucle activo.
  ///
  /// In es, this message translates to:
  /// **'Solo se graba sin bucle: quita el bucle.'**
  String get settings_audio_block_loop;

  /// Bloqueo de calibrar: sin entrada de guitarra.
  ///
  /// In es, this message translates to:
  /// **'Asigna la entrada de guitarra en Ajustes · Audio.'**
  String get settings_audio_block_noGuitarInput;

  /// Bloqueo de calibrar: sin dispositivo de entrada.
  ///
  /// In es, this message translates to:
  /// **'Elige un dispositivo de entrada en Ajustes · Audio.'**
  String get settings_audio_block_noInputDevice;

  /// Bloqueo de calibrar: salida desconectada.
  ///
  /// In es, this message translates to:
  /// **'El dispositivo de salida no está conectado.'**
  String get settings_audio_block_outputDisconnected;

  /// Bloqueo de calibrar: frecuencias distintas.
  ///
  /// In es, this message translates to:
  /// **'El dispositivo está a {deviceHz} kHz y la frecuencia de trabajo es {workingHz} kHz'**
  String settings_audio_block_rateMismatch(num deviceHz, num workingHz);

  /// Bloqueo de calibrar: error del sistema; el texto es el propio error.
  ///
  /// In es, this message translates to:
  /// **'{detail}'**
  String settings_audio_block_sessionUnavailable(String detail);

  /// Bloqueo de calibrar: velocidad distinta de 100 %.
  ///
  /// In es, this message translates to:
  /// **'Solo se graba a velocidad 100 %: pon el tempo al 100 %.'**
  String settings_audio_block_speed(num rate);

  /// Ajustes Audio: botón calibrar.
  ///
  /// In es, this message translates to:
  /// **'Calibrar latencia'**
  String get settings_audio_calibrate;

  /// Ajustes Audio: latencia calibrada.
  ///
  /// In es, this message translates to:
  /// **'Calibrada · {ms} ms · {date}'**
  String settings_audio_calibrated(num ms, String date);

  /// Ajustes Audio: nota de calibración (AS:209).
  ///
  /// In es, this message translates to:
  /// **'Un pulso de prueba mide el retardo de ida y vuelta del dispositivo.'**
  String get settings_audio_calNote;

  /// Ajustes Audio: título de calibración (AS:208).
  ///
  /// In es, this message translates to:
  /// **'Calibración'**
  String get settings_audio_calTitle;

  /// Ajustes Audio: nota de canales (AS:184).
  ///
  /// In es, this message translates to:
  /// **'Qué entra y qué sale por cada canal del dispositivo.'**
  String get settings_audio_channelsNote;

  /// Ajustes Audio: título de canales (AS:184).
  ///
  /// In es, this message translates to:
  /// **'Canales'**
  String get settings_audio_channelsTitle;

  /// Ajustes Audio: dispositivo elegido desconectado (AS:154).
  ///
  /// In es, this message translates to:
  /// **'Dispositivo elegido'**
  String get settings_audio_chosenFallback;

  /// Ajustes Audio: dispositivo desconectado (AS:154).
  ///
  /// In es, this message translates to:
  /// **'{name} · desconectado'**
  String settings_audio_deviceDisconnected(String name);

  /// Ajustes Audio: nota de dispositivo (AS:115).
  ///
  /// In es, this message translates to:
  /// **'Por dónde suena el backing y por dónde entra tu guitarra.'**
  String get settings_audio_deviceNote;

  /// Ajustes Audio: opción de dispositivo (AS:152).
  ///
  /// In es, this message translates to:
  /// **'{name} · {channels} can.'**
  String settings_audio_deviceOption(String name, int channels);

  /// Ajustes Audio: título de dispositivo (AS:115).
  ///
  /// In es, this message translates to:
  /// **'Dispositivo'**
  String get settings_audio_deviceTitle;

  /// Ajustes Audio: entrada de guitarra (AS:185-192).
  ///
  /// In es, this message translates to:
  /// **'Entrada de guitarra'**
  String get settings_audio_guitarIn;

  /// Ajustes Audio: etiqueta de entrada (AS:116-136).
  ///
  /// In es, this message translates to:
  /// **'Dispositivo de entrada'**
  String get settings_audio_input;

  /// Ajustes Audio: una entrada (AS:59-60).
  ///
  /// In es, this message translates to:
  /// **'Entrada {n}'**
  String settings_audio_inputN(int n);

  /// Ajustes Audio: dos entradas (AS:59-60).
  ///
  /// In es, this message translates to:
  /// **'Entradas {n} y {m}'**
  String settings_audio_inputsNM(int n, int m);

  /// Ajustes Audio: etiqueta de latencia (AS:210).
  ///
  /// In es, this message translates to:
  /// **'Latencia'**
  String get settings_audio_latency;

  /// Ajustes Audio: sin entrada (AS:129).
  ///
  /// In es, this message translates to:
  /// **'Ninguna'**
  String get settings_audio_noInput;

  /// Ajustes Audio: etiqueta de salida (AS:116-136).
  ///
  /// In es, this message translates to:
  /// **'Dispositivo de salida'**
  String get settings_audio_output;

  /// Ajustes Audio: etiqueta de frecuencia (AS:116-136).
  ///
  /// In es, this message translates to:
  /// **'Frecuencia de trabajo'**
  String get settings_audio_rate;

  /// Ajustes Audio: frecuencias distintas (AS:166).
  ///
  /// In es, this message translates to:
  /// **'El dispositivo está a {device} y la frecuencia de trabajo es {working}'**
  String settings_audio_rateMismatch(String device, String working);

  /// Ajustes Audio: pista de frecuencias distintas (AS:168).
  ///
  /// In es, this message translates to:
  /// **'Grabar y calibrar quedan bloqueados; el backing suena igual.'**
  String get settings_audio_rateMismatchHint;

  /// Ajustes Audio: salida del sistema (AS:119).
  ///
  /// In es, this message translates to:
  /// **'Salida del sistema'**
  String get settings_audio_systemOutput;

  /// Ajustes Audio: canal sin asignar (AS:59-60).
  ///
  /// In es, this message translates to:
  /// **'Sin asignar'**
  String get settings_audio_unassigned;

  /// Ajustes Audio: latencia sin calibrar (AS:227).
  ///
  /// In es, this message translates to:
  /// **'Sin calibrar'**
  String get settings_audio_uncalibrated;

  /// Ajustes Audio: aplicar la frecuencia del dispositivo (AS:171).
  ///
  /// In es, this message translates to:
  /// **'Usar {rate} como frecuencia de trabajo'**
  String settings_audio_useRate(String rate);

  /// Calibrar latencia: cancelar (CS:51-85).
  ///
  /// In es, this message translates to:
  /// **'Cancelar'**
  String get settings_cal_cancel;

  /// Calibrar latencia: cerrar (CS:51-85).
  ///
  /// In es, this message translates to:
  /// **'Cerrar'**
  String get settings_cal_close;

  /// Calibrar latencia: tomas sin corregir (CS:102).
  ///
  /// In es, this message translates to:
  /// **'{n} de este tema, hechas sin calibrar'**
  String settings_cal_correctedNote(int n);

  /// Calibrar latencia: resultado (CS:92).
  ///
  /// In es, this message translates to:
  /// **'Calibrada'**
  String get settings_cal_done;

  /// Calibrar latencia: título de error (CS:77).
  ///
  /// In es, this message translates to:
  /// **'No se pudo calibrar'**
  String get settings_cal_errorTitle;

  /// Calibrar latencia: pista sin señal (CS:121).
  ///
  /// In es, this message translates to:
  /// **'Comprueba el cable de una salida del dispositivo a la entrada de guitarra, y que la entrada elegida sea esa. Después repite.'**
  String get settings_cal_noSignalHint;

  /// Calibrar latencia: título sin señal (CS:120).
  ///
  /// In es, this message translates to:
  /// **'No llegó la señal de prueba'**
  String get settings_cal_noSignalTitle;

  /// Calibrar latencia: repetir (CS:51-85).
  ///
  /// In es, this message translates to:
  /// **'Repetir'**
  String get settings_cal_retry;

  /// Calibrar latencia: sin canal de referencia (CS:99).
  ///
  /// In es, this message translates to:
  /// **'sin canal de referencia: la latencia calibrada vale tal cual'**
  String get settings_cal_rigNone;

  /// Calibrar latencia: retardo del rig (CS:97).
  ///
  /// In es, this message translates to:
  /// **'{ms} ms · se corregirá en cada toma'**
  String settings_cal_rigNote(num ms);

  /// Calibrar latencia: fila de tomas corregidas (CS:94-102).
  ///
  /// In es, this message translates to:
  /// **'Tomas corregidas'**
  String get settings_cal_rowCorrected;

  /// Calibrar latencia: fila de latencia (CS:94-102).
  ///
  /// In es, this message translates to:
  /// **'Latencia'**
  String get settings_cal_rowLatency;

  /// Calibrar latencia: fila de retardo del rig (CS:94-102).
  ///
  /// In es, this message translates to:
  /// **'Retardo del rig'**
  String get settings_cal_rowRig;

  /// Calibrar latencia: fila de dispersión (CS:94-102).
  ///
  /// In es, this message translates to:
  /// **'Dispersión'**
  String get settings_cal_rowSpread;

  /// Calibrar latencia: medición en curso (CS:62).
  ///
  /// In es, this message translates to:
  /// **'Midiendo… no toques la guitarra ni muevas el cable.'**
  String get settings_cal_running;

  /// Calibrar latencia: pista de señal saturada (CS:124).
  ///
  /// In es, this message translates to:
  /// **'Baja el volumen de salida del dispositivo (con una pedalera, el del rig o el de la salida) y repite.'**
  String get settings_cal_saturatedHint;

  /// Calibrar latencia: título de señal saturada (CS:123).
  ///
  /// In es, this message translates to:
  /// **'La señal llegó saturada'**
  String get settings_cal_saturatedTitle;

  /// Calibrar latencia: empezar (CS:51-85).
  ///
  /// In es, this message translates to:
  /// **'Empezar'**
  String get settings_cal_start;

  /// Calibrar latencia: título de la hoja (CS:21).
  ///
  /// In es, this message translates to:
  /// **'Calibrar latencia'**
  String get settings_cal_title;

  /// Calibrar latencia: pista de medidas inestables (CS:127).
  ///
  /// In es, this message translates to:
  /// **'Carga un rig vacío o sin delay ni reverb, cierra otras apps de audio y repite.'**
  String get settings_cal_unstableHint;

  /// Calibrar latencia: título de medidas inestables (CS:126).
  ///
  /// In es, this message translates to:
  /// **'Las medidas no coinciden entre sí (dispersión de {ms} ms)'**
  String settings_cal_unstableTitle(num ms);

  /// Ancla del bloque settings_video: añade las claves del área debajo, en orden alfabético; no edites otros bloques.
  ///
  /// In es, this message translates to:
  /// **''**
  String get settingsVideoAnchor;

  /// Ajustes Cámara y vídeo: etiqueta de cámara (VS:255-271).
  ///
  /// In es, this message translates to:
  /// **'Cámara'**
  String get settings_video_camera;

  /// Ajustes Cámara y vídeo: cámara desconectada (VS:239).
  ///
  /// In es, this message translates to:
  /// **'{name} · desconectada'**
  String settings_video_cameraDisconnected(String name);

  /// Ajustes Cámara y vídeo: título de cámara (VS:252).
  ///
  /// In es, this message translates to:
  /// **'Cámara'**
  String get settings_video_cameraTitle;

  /// Ajustes Cámara y vídeo: cámara elegida desconectada (VS:239).
  ///
  /// In es, this message translates to:
  /// **'Cámara elegida'**
  String get settings_video_chosenFallback;

  /// Ajustes Cámara y vídeo: aviso de cámara elegida desconectada (VS:249-251).
  ///
  /// In es, this message translates to:
  /// **'La cámara elegida está desconectada.'**
  String get settings_video_chosenOff;

  /// Ajustes Cámara y vídeo: sin permiso de cámara (VS:300-301, CP:59).
  ///
  /// In es, this message translates to:
  /// **'ToneForge no tiene permiso para usar la cámara.'**
  String get settings_video_denied;

  /// Ajustes Cámara y vídeo: nota de exportación (VS:355).
  ///
  /// In es, this message translates to:
  /// **'Se puede cambiar en cada montaje.'**
  String get settings_video_exportNote;

  /// Ajustes Cámara y vídeo: título de exportación (VS:355).
  ///
  /// In es, this message translates to:
  /// **'Exportación por defecto'**
  String get settings_video_exportTitle;

  /// Ajustes Cámara y vídeo: formato (VS:356-370).
  ///
  /// In es, this message translates to:
  /// **'Formato de vídeo'**
  String get settings_video_format;

  /// Ajustes Cámara y vídeo: fotogramas por segundo (VS:255-271).
  ///
  /// In es, this message translates to:
  /// **'Fotogramas por segundo'**
  String get settings_video_fps;

  /// Ajustes Cámara y vídeo: cámara en uso (VS:249-251).
  ///
  /// In es, this message translates to:
  /// **'En uso: {name}.'**
  String settings_video_inUse(String name);

  /// Ajustes Cámara y vídeo: sin cámaras (VS:249-251).
  ///
  /// In es, this message translates to:
  /// **'No hay ninguna cámara conectada.'**
  String get settings_video_none;

  /// Ajustes Cámara y vídeo: desfase por defecto (VS:340-342).
  ///
  /// In es, this message translates to:
  /// **'Desfase por defecto de esta cámara'**
  String get settings_video_offset;

  /// Ajustes Cámara y vídeo: error al abrir (VS:117, CP:153).
  ///
  /// In es, this message translates to:
  /// **'No se pudo abrir la cámara ({error}).'**
  String settings_video_openFailed(String error);

  /// Ajustes Cámara y vídeo: abrir ajustes del sistema en macOS (VS:300-301, CP:59).
  ///
  /// In es, this message translates to:
  /// **'Abrir Ajustes del Sistema'**
  String get settings_video_openSystem_mac;

  /// Ajustes Cámara y vídeo: abrir configuración en Windows (VS:300-301, CP:59).
  ///
  /// In es, this message translates to:
  /// **'Abrir Configuración'**
  String get settings_video_openSystem_win;

  /// Ajustes Cámara y vídeo: resolución (VS:255-271).
  ///
  /// In es, this message translates to:
  /// **'Resolución'**
  String get settings_video_resolution;

  /// Ajustes Cámara y vídeo: vista previa simulada (VS:294).
  ///
  /// In es, this message translates to:
  /// **'Vista previa simulada'**
  String get settings_video_simulated;

  /// Ajustes Cámara y vídeo: exportar stems (VS:372-377).
  ///
  /// In es, this message translates to:
  /// **'WAV de cada pista'**
  String get settings_video_stemWavs;

  /// Ajustes Cámara y vídeo: nota de sincronía (VS:340-342).
  ///
  /// In es, this message translates to:
  /// **'Se ajusta al terminar cada toma; este es el valor con el que empieza la siguiente.'**
  String get settings_video_syncNote;

  /// Ajustes Cámara y vídeo: título de sincronía (VS:340-342).
  ///
  /// In es, this message translates to:
  /// **'Sincronía'**
  String get settings_video_syncTitle;

  /// Ajustes Cámara y vídeo: cámara por defecto del sistema (VS:258).
  ///
  /// In es, this message translates to:
  /// **'Por defecto del sistema'**
  String get settings_video_systemDefault;

  /// Ajustes Cámara y vídeo: rótulo con el título (VS:372-377).
  ///
  /// In es, this message translates to:
  /// **'Rótulo con el título del tema'**
  String get settings_video_titleOverlay;

  /// Ajustes Cámara y vídeo: volumen (VS:356-370).
  ///
  /// In es, this message translates to:
  /// **'Volumen'**
  String get settings_video_volume;

  /// Ajustes Cámara y vídeo: normalización del volumen (VS:356-370).
  ///
  /// In es, this message translates to:
  /// **'normalizado a −14 LUFS'**
  String get settings_video_volumeValue;

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
