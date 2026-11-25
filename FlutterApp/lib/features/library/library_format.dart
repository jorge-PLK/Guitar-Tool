/// Formatos de la Biblioteca, equivalentes a `Fmt` de SwiftUI (`App/Sources`). Provisional: los rellena la parte D.
/// Si ya existe un equivalente en `lib/`, estas funciones lo envuelven.
library;

/// `Fmt.bytes`: tamaño legible («1,2 MB»).
String formatBytes(int bytes, String locale) => '';

/// `Fmt.rate`: frecuencia de muestreo («48 kHz»).
String formatRate(int hz, String locale) => '';

/// `Fmt.duration`: duración de un tema.
String formatDuration(double seconds, String locale) => '';

/// `Fmt.clock`: duración de una toma en reloj; null → «–».
String formatClock(double? seconds) => '';

/// Fecha corta de una toma.
String formatShortDate(DateTime date, String locale) => '';
