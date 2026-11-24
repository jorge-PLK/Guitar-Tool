import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/icons.dart';

/// Rutas de la barra lateral. El orden de [values] es el de `Sidebar` en RootView.swift
/// (Ajustes va aparte, abajo).
enum ShellRoute {
  library(TfIcon.musicNoteList),
  backing(TfIcon.sliderVertical3),
  tab(TfIcon.musicQuarternote3),
  record(TfIcon.recordCircle),
  montage(TfIcon.film),
  settings(TfIcon.gearshape);

  const ShellRoute(this.icon);

  final TfIcon icon;

  /// Etiqueta de navegación (clave `shell_nav*`).
  String label(AppLocalizations l) => switch (this) {
        ShellRoute.library => l.shell_navLibrary,
        ShellRoute.backing => l.shell_navBacking,
        ShellRoute.tab => l.shell_navTab,
        ShellRoute.record => l.shell_navRecord,
        ShellRoute.montage => l.shell_navMontage,
        ShellRoute.settings => l.shell_navSettings,
      };

  /// Ruta de `--screen` (nombres de `AppModel.swift:425-469`); lo desconocido abre Biblioteca.
  static ShellRoute fromScreen(String? screen) {
    final s = screen ?? '';
    if (s.startsWith('settings') || s == 'calibration-sheet') return ShellRoute.settings;
    if (s.startsWith('backing')) return ShellRoute.backing;
    if (s.startsWith('record')) return ShellRoute.record;
    if (s.startsWith('montage')) return ShellRoute.montage;
    if (s == 'tab') return ShellRoute.tab;
    return ShellRoute.library;
  }
}

/// Pestañas de Ajustes (`SettingsTab`, SettingsView.swift:18).
enum SettingsTab {
  audio,
  video,
  library;

  String label(AppLocalizations l) => switch (this) {
        SettingsTab.audio => l.settings_tabAudio,
        SettingsTab.video => l.settings_tabVideo,
        SettingsTab.library => l.settings_tabLibrary,
      };

  /// Pestaña inicial de `--screen` (`settings-audio`, `settings-video`, `settings-library`).
  static SettingsTab fromScreen(String? screen) => switch (screen) {
        'settings-library' => SettingsTab.library,
        'settings-video' => SettingsTab.video,
        _ => SettingsTab.audio,
      };
}
