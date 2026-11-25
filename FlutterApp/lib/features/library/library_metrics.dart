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

  // --- E2: hoja de importación, candidatos y trabajando (LinkImportSheet.swift:597-757) ---

  /// Portada de la cabecera de candidatos (LinkImportSheet.swift:643).
  static const double importCoverSize = 104;

  /// Alto máximo de la lista de candidatos con scroll (LinkImportSheet.swift:682).
  static const double candidateListMaxHeight = 280;

  /// Alto del botón «Abrir» de la banda de posible repetido y de la fila en biblioteca (LinkImportSheet.swift:620,712).
  static const double importOpenHeight = 28;

  /// Radio de la portada y de la tarjeta de confirmación (LinkImportSheet.swift:644,660).
  static const double importCoverRadius = 10;

  // --- G: hojas pequeñas (ArtistGrid.swift:164, RootView.swift:133) ---

  /// Ancho de la hoja «Corregir título y artista» (ArtistGrid.swift:164).
  static const double songInfoSheetWidth = 520;

  /// Alto del botón «Cancelar» de esa hoja (ArtistGrid.swift:159).
  static const double songInfoButtonHeight = 36;

  /// Ancho de la hoja de primer arranque (RootView.swift:133).
  static const double firstRunSheetWidth = 480;

  /// Lado de la estrella de «mejor toma» (Text("★") en ProjectRecordingsView.swift:67, sin glifo en la fuente).
  static const double bestStarSize = 14;

  // --- F1: hoja de lista (PlaylistImport.swift:287,314,328) ---

  /// Alto de «Marcar todos» y «Ninguno» (SecondaryButton(height: 34), PI:287).
  static const double plActionHeight = 34;

  /// Hueco de la casilla en un tema ya en la biblioteca (PI:314).
  static const double plCheckSlot = 20;

  /// Ancho de la columna de duración (PI:328).
  static const double plDurationWidth = 48;

  // --- F2: hoja de lista, fases Revisar, Cola y Resumen (PlaylistImport.swift:355-575) ---

  /// Ancho del título en Revisar (PI:381).
  static const double reviewTitleWidth = 250;

  /// Ancho de la duración en Revisar (PI:382).
  static const double reviewDurationWidth = 40;

  /// Chevron del selector de candidato (PI:423).
  static const double candidateChevron = 10;

  /// Ancho de la barra de progreso de una fila de la cola (PI:500).
  static const double queueBarWidth = 140;

  /// Alto de esa barra (PI:500).
  static const double queueBarHeight = 5;

  /// Ancho del título en las filas de fallidos (PI:561).
  static const double failedTitleWidth = 280;
}
