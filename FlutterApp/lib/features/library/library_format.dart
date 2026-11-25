/// Formatos de la Biblioteca, equivalentes a `Fmt` de SwiftUI (`App/Sources`): envuelven `TfFmt`.
library;

import '../../theme/fmt.dart';

/// `Fmt.bytes`: tamaño legible («1,2 MB»; en inglés «1.2 MB»).
String formatBytes(int bytes, String locale) => TfFmt.bytes(bytes, locale);

/// `Fmt.rate`: frecuencia de muestreo («44,1 kHz», «48 kHz», «N Hz»).
String formatRate(int hz, String locale) => TfFmt.rate(hz.toDouble(), locale);

/// `Fmt.duration`: duración de un tema (`m:ss`).
String formatDuration(double seconds, String locale) => TfFmt.duration(seconds);

/// `Fmt.clock`: duración de una toma en reloj (`m:ss`); null → «–».
String formatClock(double? seconds) => seconds == null ? '–' : TfFmt.clock(seconds);

const _monthsEs = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sept', 'oct', 'nov', 'dic'];
const _monthsEn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Fecha corta de una toma (`date: .abbreviated, time: .shortened`): «1 ene 2026, 0:00» / «Jan 1, 2026, 12:00 AM».
/// Hecha a mano para no depender de `initializeDateFormatting`.
String formatShortDate(DateTime date, String locale) {
  final d = date.toLocal();
  final mm = d.minute.toString().padLeft(2, '0');
  if (locale == 'es') {
    return '${d.day} ${_monthsEs[d.month - 1]} ${d.year}, ${d.hour}:$mm';
  }
  final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ampm = d.hour < 12 ? 'AM' : 'PM';
  return '${_monthsEn[d.month - 1]} ${d.day}, ${d.year}, $h12:$mm $ampm';
}
