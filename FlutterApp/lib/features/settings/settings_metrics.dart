/// Medidas propias de la pestaña Biblioteca de Ajustes (sin equivalente en los tokens del tema).
abstract final class SettingsMetrics {
  /// Ancho del selector segmentado de Idioma («Sistema», «Español», «English»): la ficha pide 260-300.
  static const double languageSegmentWidth = 280;

  /// Alto mínimo del campo de la carpeta de proyectos (SettingsView.swift:114).
  static const double folderFieldMinHeight = 44;

  /// Separación entre el rótulo y el campo de la carpeta (SettingsView.swift:110).
  static const double folderLabelGap = 6;

  /// Separación entre barra y «Moviendo N %» (SettingsView.swift:122).
  static const double progressGap = 12;

  /// Separación entre botones de una fila (SettingsView.swift:127).
  static const double buttonGap = 8;
}
