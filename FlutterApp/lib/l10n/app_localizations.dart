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

  /// No description provided for @settings_subtitle.
  ///
  /// In es, this message translates to:
  /// **'Se configura una vez y lo usan todas las pantallas. Se guarda en tu perfil de equipo.'**
  String get settings_subtitle;

  /// No description provided for @settings_tabAudio.
  ///
  /// In es, this message translates to:
  /// **'Audio'**
  String get settings_tabAudio;

  /// No description provided for @settings_tabLibrary.
  ///
  /// In es, this message translates to:
  /// **'Biblioteca'**
  String get settings_tabLibrary;

  /// No description provided for @settings_tabVideo.
  ///
  /// In es, this message translates to:
  /// **'Cámara y vídeo'**
  String get settings_tabVideo;

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
