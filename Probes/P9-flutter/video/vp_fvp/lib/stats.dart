import 'dart:async';
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
  // Repetidos: fotogramas que permanecieron >= 2 periodos (el muestreo tiene ~25 ms de holgura).
  var repeated = 0;
  {
    final per = kT / rate;
    int? ln;
    double ft = 0;
    for (final x in valid) {
      if (x.n == ln) continue;
      if (ln != null && x.t - ft > 1.5 * per + 0.025) repeated += ((x.t - ft) / per).round() - 1;
      ln = x.n;
      ft = x.t;
    }
  }
  final spanS = valid.length < 2 ? 0.0 : valid.last.t - valid.first.t;
  return {
    'repeated': repeated,
    'framesPerSec': spanS > 0 ? (shown * 100 / spanS).round() / 100 : null,
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

/// Vigilante del hilo de UI: temporizador de 5 ms; retraso = llegada - prevista.
class Watchdog {
  final Stopwatch _sw = Stopwatch();
  Timer? _t;
  int ticks = 0, over16 = 0, over50 = 0, over100 = 0;
  double maxMs = 0;
  int _expectedUs = 0;

  void start() {
    _sw.start();
    _expectedUs = 5000;
    _t = Timer.periodic(const Duration(milliseconds: 5), (_) {
      final late = (_sw.elapsedMicroseconds - _expectedUs) / 1000;
      ticks++;
      if (late > maxMs) maxMs = late;
      if (late > 16) over16++;
      if (late > 50) over50++;
      if (late > 100) over100++;
      // Si el hilo se atasca, el siguiente tick esperado es el real + 5 ms (no acumula el retraso).
      _expectedUs = _sw.elapsedMicroseconds + 5000;
    });
  }

  void stop() => _t?.cancel();

  Map<String, Object?> toJson() =>
      {'ticks': ticks, 'maxMs': (maxMs * 100).round() / 100, 'over16ms': over16, 'over50ms': over50, 'over100ms': over100};
}

/// NaN/Infinity -> null y claves a String, para que el informe sea JSON válido.
Object? clean(Object? v) {
  if (v is double) return v.isFinite ? v : null;
  if (v is Map) return {for (final e in v.entries) '${e.key}': clean(e.value)};
  if (v is Iterable) return [for (final e in v) clean(e)];
  if (v == null || v is num || v is bool || v is String) return v;
  return '$v';
}

double meanOf(List<double> v) => v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;
double maxOf(List<double> v) => v.isEmpty ? 0 : v.reduce(math.max);
