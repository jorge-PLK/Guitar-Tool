import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

double _r(num v, [int d = 3]) => double.parse(v.toStringAsFixed(d));

/// mediana, p99, máx, media (misma unidad que la entrada).
Map<String, Object> stats(List<num> xs, [int d = 3]) {
  if (xs.isEmpty) return {'n': 0};
  final s = xs.map((e) => e.toDouble()).toList()..sort();
  double q(double p) => s[math.min(s.length - 1, (p * (s.length - 1)).round())];
  return {
    'n': s.length,
    'median': _r(q(0.5), d),
    'p99': _r(q(0.99), d),
    'max': _r(s.last, d),
    'mean': _r(s.fold(0.0, (a, b) => a + b) / s.length, d),
  };
}

double stddev(List<double> xs) {
  if (xs.length < 2) return 0;
  final m = xs.reduce((a, b) => a + b) / xs.length;
  return math.sqrt(xs.fold(0.0, (a, b) => a + (b - m) * (b - m)) / xs.length);
}

double round3(num v) => _r(v);

/// Vigilante del hilo de UI: Timer.periodic(5 ms), retraso máx sobre lo esperado.
class Watchdog {
  final _sw = Stopwatch()..start();
  int _last = 0;
  double maxDelayMs = 0;
  int ticks = 0;
  Timer? _t;

  void start() {
    _last = _sw.elapsedMicroseconds;
    _t = Timer.periodic(const Duration(milliseconds: 5), (_) {
      final now = _sw.elapsedMicroseconds;
      final d = (now - _last) / 1000 - 5;
      _last = now;
      ticks++;
      if (d > maxDelayMs) maxDelayMs = d;
    });
  }

  void reset() {
    maxDelayMs = 0;
    ticks = 0;
    _last = _sw.elapsedMicroseconds;
  }

  void stop() => _t?.cancel();
}

/// Tiempos de fotograma del motor (llegan por lotes, con retraso).
class FrameStats {
  int frames = 0;
  double maxBuildMs = 0;
  double maxRasterMs = 0;
  double maxTotalMs = 0;
  int over16 = 0;

  void reset() {
    frames = 0;
    over16 = 0;
    maxBuildMs = maxRasterMs = maxTotalMs = 0;
  }

  void start() => SchedulerBinding.instance.addTimingsCallback((ts) {
        for (final t in ts) {
          frames++;
          final b = t.buildDuration.inMicroseconds / 1000;
          final r = t.rasterDuration.inMicroseconds / 1000;
          final tot = t.totalSpan.inMicroseconds / 1000;
          if (b > maxBuildMs) maxBuildMs = b;
          if (r > maxRasterMs) maxRasterMs = r;
          if (tot > maxTotalMs) maxTotalMs = tot;
          if (tot > 16) over16++;
        }
      });

  Map<String, Object> toJson() => {
        'frames': frames,
        'maxBuildMs': round3(maxBuildMs),
        'maxRasterMs': round3(maxRasterMs),
        'maxTotalSpanMs': round3(maxTotalMs),
        'framesOver16ms': over16,
        if (frames == 0) 'note': 'sin fotogramas (ventana tapada o sin cambios)',
      };
}

/// Quema ~8 ms de CPU cada 16 ms en el isolate de UI.
class BusyLoad {
  Timer? _t;
  void start() {
    _t = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final sw = Stopwatch()..start();
      var x = 0.0;
      while (sw.elapsedMicroseconds < 8000) {
        x += math.sqrt(x + 1);
      }
      if (x < 0) debugPrint('$x');
    });
  }

  void stop() => _t?.cancel();
}

/// Animación simple para que la ventana pinte durante la prueba.
class ProbeAnim extends StatefulWidget {
  const ProbeAnim({super.key, required this.label});
  final String label;
  @override
  State<ProbeAnim> createState() => _ProbeAnimState();
}

class _ProbeAnimState extends State<ProbeAnim>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF14161A),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RotationTransition(
                turns: _c,
                child: const SizedBox(
                  width: 80,
                  height: 80,
                  child: ColoredBox(color: Color(0xFF3FA7D6)),
                ),
              ),
              const SizedBox(height: 16),
              DefaultTextStyle(
                style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 14),
                child: Text(widget.label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
