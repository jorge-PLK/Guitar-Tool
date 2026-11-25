/// Medidas propias de la Biblioteca que no son tokens del tema (anchos de hoja, altos de botón sueltos).
/// Colores, tipografía, radios y espaciados siguen saliendo de `lib/theme/`.
abstract final class LibraryMetrics {
  /// Hoja de importación vacía (LinkImportSheet.swift:449).
  static const double importSheetEmptyWidth = 620;

  /// Hoja de importación en el resto de pantallas (LinkImportSheet.swift:449).
  static const double importSheetWidth = 560;

  /// Hoja de importación de una lista (`playlistSize`, LinkImportSheet.swift:472).
  static const double playlistSheetWidth = 880;
  static const double playlistSheetHeight = 700;

  /// Botón «Elegir» de un resultado de Spotify (LinkImportSheet.swift).
  static const double spotifyChooseHeight = 30;

  /// Miniatura de un resultado de Spotify (LinkImportSheet.swift:530).
  static const double spotifyThumb = 36;

  /// Campo de enlace de la hoja (LinkImportSheet.swift:479-499).
  static const double linkFieldHeight = 40;
}
