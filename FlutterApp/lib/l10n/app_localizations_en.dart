// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get commonAnchor => '';

  @override
  String get common_accept => 'OK';

  @override
  String get common_cancel => 'Cancel';

  @override
  String get common_delete => 'Delete';

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
  String get shell_navLibrary => 'Library';

  @override
  String get shell_navMontage => 'Montage';

  @override
  String get shell_navRecord => 'Record';

  @override
  String get shell_navSettings => 'Settings';

  @override
  String get shell_navTab => 'Tabs';

  @override
  String get shell_selectedThemeHelp => 'Open the theme page';

  @override
  String shell_selectedThemeLabel(String title) {
    return 'Selected theme: $title';
  }

  @override
  String get libraryAnchor => '';

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
  String get settings_subtitle =>
      'Set it up once and every screen uses it. It is saved in your machine profile.';

  @override
  String get settings_tabAudio => 'Audio';

  @override
  String get settings_tabLibrary => 'Library';

  @override
  String get settings_tabVideo => 'Camera & video';

  @override
  String get errorAnchor => '';

  @override
  String get error_unknown => 'Unknown error';
}
