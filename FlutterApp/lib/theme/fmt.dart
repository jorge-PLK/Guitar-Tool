import 'package:intl/intl.dart';

/// Escalas de formato de `Fmt` (App/Sources/Theme.swift:138-147 y extensiones).
///
/// El separador decimal sigue el locale (intl): «,» en es, «.» en en.
/// El resto del formato (unidades, signo, redondeo, duraciones m:ss) es el de SwiftUI.
abstract final class TfFmt {
  /// Separador decimal del locale.
  static String _sep(String locale) => NumberFormat.decimalPattern(locale).symbols.DECIMAL_SEP;

  /// `ByteCountFormatter` (estilo archivo, unidades decimales): «500 bytes», «2 KB», «1,2 MB».
  /// Cero: «Zero KB». KB sin decimales; MB y superiores con un decimal, sin «,0».
  static String bytes(int n, String locale) {
    if (n == 0) return 'Zero KB';
    if (n.abs() < 1000) return n == 1 ? '1 byte' : '$n bytes';
    const units = ['KB', 'MB', 'GB', 'TB', 'PB', 'EB'];
    var v = n / 1000;
    var u = 0;
    while (true) {
      final r = u == 0 ? v.roundToDouble() : (v * 10).roundToDouble() / 10;
      if (r < 1000 || u == units.length - 1) {
        final String mantissa;
        if (u == 0 || r == r.truncateToDouble()) {
          mantissa = r.toInt().toString();
        } else {
          mantissa = r.toStringAsFixed(1).replaceFirst('.', _sep(locale));
        }
        return '$mantissa ${units[u]}';
      }
      v /= 1000;
      u++;
    }
  }

  /// `Fmt.percent`: «NN %» (con espacio), entero redondeado con la mitad lejos de cero.
  static String percent(double f) => '${(f * 100).round()} %';

  /// `Fmt.duration`: m:ss con segundos redondeados (mitad lejos de cero).
  static String duration(double s) {
    final t = s.roundToDouble().toInt();
    return '${t ~/ 60}:${(t.remainder(60)).toString().padLeft(2, '0')}';
  }

  /// `Fmt.rate`: «44,1 kHz» / «48 kHz» / «N Hz».
  static String rate(double hz, String locale) {
    if (hz == 44100) return '44${_sep(locale)}1 kHz';
    if (hz == 48000) return '48 kHz';
    return '${hz.toInt()} Hz';
  }

  /// `Fmt.db` (BackingMixer.swift:277): «-6,0 dB», un decimal.
  static String db(double v, String locale) =>
      '${_printfFixed(v, 1).replaceFirst('.', _sep(locale))} dB';

  /// `Fmt.clock` (BackingTimeline.swift:473): m:ss truncando, nunca negativo.
  static String clock(double s) {
    final t = s > 0 ? s.toInt() : 0;
    return '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
  }

  /// `Fmt.number` (CalibrationSheet.swift:6): decimales fijos con agrupación del locale.
  static String number(double v, int digits, String locale) =>
      NumberFormat.decimalPatternDigits(locale: locale, decimalDigits: digits).format(v);

  /// Como `String(format: "%.Nf")`: en un empate exacto redondea al par.
  /// Dart redondea esos empates hacia arriba, así que solo se corrige ese caso.
  static String _printfFixed(double v, int digits) {
    final rounded = v.toStringAsFixed(digits);
    final exact = v.abs().toStringAsFixed(20);
    final dot = exact.indexOf('.');
    final tail = exact.substring(dot + 1 + digits);
    final isTie = tail.startsWith('5') && tail.substring(1).replaceAll('0', '').isEmpty;
    if (!isTie) return rounded;
    final kept = exact.substring(0, digits == 0 ? dot : dot + 1 + digits);
    final lastDigit = int.parse(kept[kept.length - 1]);
    if (lastDigit.isOdd) return rounded;
    return '${v < 0 ? '-' : ''}$kept';
  }
}
