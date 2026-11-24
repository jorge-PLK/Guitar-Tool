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
      'Se configura una vez y lo usan todas las pantallas. Se guarda en tu perfil de equipo.';

  @override
  String get settings_tabAudio => 'Audio';

  @override
  String get settings_tabLibrary => 'Biblioteca';

  @override
  String get settings_tabVideo => 'Cámara y vídeo';

  @override
  String get errorAnchor => '';

  @override
  String get error_unknown => 'Error desconocido';
}
