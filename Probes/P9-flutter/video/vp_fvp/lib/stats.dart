import 'dart:math' as math;

const double kT = 1001 / 30000; // s por fotograma
const double kTolLo = -kT / 2, kTolHi = 1.5 * kT;

class Sample {
  Sample(this.t, this.n, this.width, this.pos);
  final double t; // instante medio de la lectura (s, reloj de pared)
  final int n; // índice leído (-1 = inválido)
  final double width; // t1-t0 de toImage (s): incertidumbre = ±width/2
  final double pos; // pos(t) del reloj
  double get e => pos - n * kT;
  bool get ok => n >= 0 && e >= kTolLo && e < kTolHi;
}

double pct(List<double> sorted, double p) {
  if (sorted.isEmpty) return double.nan;
  final i = (p * (sorted.length - 1)).clamp(0, sorted.length - 1).toDouble();
  final lo = i.floor(), hi = i.ceil();
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (i - lo);
}

Map<String, Object?> dist(List<double> v, {double scale = 1e3}) {
  final s = (List<double>.of(v)..sort()).map((x) => x * scale).toList();
  double r(double x) => x.isNaN ? x : (x * 100).round() / 100;
  return {
    'n': s.length,
    'median': r(pct(s, .5)),
    'p95': r(pct(s, .95)),
    'p99': r(pct(s, .99)),
    'min': s.isEmpty ? null : r(s.first),
    'max': s.isEmpty ? null : r(s.last),
  };
}

/// Estadísticas de régimen sobre las muestras en [t0,t1).
Map<String, Object?> regime(List<Sample> all, double t0, double t1, double rate) {
  final s = all.where((x) => x.t >= t0 && x.t < t1).toList();
  final valid = s.where((x) => x.n >= 0).toList();
  final out = valid.where((x) => !x.ok).length;
  // fotogramas distintos: tiempo de permanencia, saltos y retrocesos.
  var skipped = 0, back = 0, longDwell = 0, shown = 0;
  var lastN = -1;
  double firstT = 0;
  for (final x in valid) {
    if (x.n == lastN) continue;
    if (lastN >= 0) {
      final gap = x.n - lastN;
      if (gap < 0) back++;
      if (gap > 1) skipped += gap - 1;
      if (x.t - firstT > kT / rate + 0.025) longDwell++;
    }
    shown++;
    lastN = x.n;
    firstT = x.t;
  }
  return {
    'rate': rate,
    'samples': s.length,
    'invalid': s.length - valid.length,
    'e_ms': dist(valid.map((x) => x.e).toList()),
    'outOfTolPct': valid.isEmpty ? null : (out * 10000 / valid.length).round() / 100,
    'framesShown': shown,
    'skipped': skipped,
    'backSteps': back,
    'longDwell': longDwell,
    'toImageMs': dist(s.map((x) => x.width).toList()),
  };
}

/// Recuperación tras un salto en tj: ms hasta primera muestra OK, y hasta OK permanente (hasta tEnd).
Map<String, Object?> recovery(List<Sample> all, double tj, double tEnd) {
  final s = all.where((x) => x.t >= tj && x.t < tEnd).toList();
  double? first;
  double? stay;
  for (var i = 0; i < s.length; i++) {
    if (s[i].ok) first ??= s[i].t - tj;
  }
  for (var i = s.length - 1; i >= -1; i--) {
    if (i >= 0 && s[i].ok) continue;
    if (i + 1 < s.length) stay = s[i + 1].t - tj;
    break;
  }
  double? ms(double? x) => x == null ? null : (x * 1e4).round() / 10;
  return {'firstOkMs': ms(first), 'stayOkMs': ms(stay), 'samples': s.length};
}

double meanOf(List<double> v) => v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;
double maxOf(List<double> v) => v.isEmpty ? 0 : v.reduce(math.max);
