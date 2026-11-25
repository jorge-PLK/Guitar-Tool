import 'package:toneforge/contract/tab.dart';

/// Segundos de canción -> {compás, fracción} con los tiempos reales de pulso del núcleo
/// (misma regla que `TabGrid.position(at:)`). Puro.
final class TabTimingMap {
  TabTimingMap(TabTiming timing)
      : _beats = timing.beats,
        _perBar = timing.beatsPerBar,
        _end = timing.end,
        _first = _firstBeats(timing.beatsPerBar);

  final List<double> _beats;
  final List<int> _perBar;
  final double _end;
  final List<int> _first;

  static List<int> _firstBeats(List<int> perBar) {
    final out = <int>[];
    var acc = 0;
    for (final n in perBar) {
      out.add(acc);
      acc += n;
    }
    return out;
  }

  ({int bar, double fraction}) at(double seconds) {
    final n = _beats.length;
    if (n == 0 || _perBar.isEmpty) return (bar: 0, fraction: 0);
    // último índice con beats[i] <= seconds (0 si ninguno)
    var lo = 0, hi = n - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_beats[mid] <= seconds) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    final b = lo;
    final t0 = _beats[b];
    final t1 = b + 1 < n ? _beats[b + 1] : _end;
    final f = t1 == t0 ? 0.0 : ((seconds - t0) / (t1 - t0)).clamp(0.0, 1.0);
    // compás: último con first[bar] <= b
    var bl = 0, bh = _first.length - 1;
    while (bl < bh) {
      final mid = (bl + bh + 1) >> 1;
      if (_first[mid] <= b) {
        bl = mid;
      } else {
        bh = mid - 1;
      }
    }
    final per = _perBar[bl] <= 0 ? 1 : _perBar[bl];
    return (bar: bl, fraction: ((b - _first[bl]) + f) / per);
  }
}
