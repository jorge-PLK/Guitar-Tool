import 'probe2_util.dart';

/// T = 1/(30000/1001) en ms. Tolerancia: -T/2 <= e < 1,5 T.
const frameMs = 33.3667;
bool inTol(double e) => e >= -frameMs / 2 && e < 1.5 * frameMs;

/// Muestra de `stats.samples`: [t_ms, e_ms|null, n, itemTime_s, epoch].
class Sample {
  Sample(this.t, this.e, this.n, this.item, this.epoch);
  final double t;
  final double? e;
  final int n;
  final double item;
  final int epoch;

  static List<Sample> parse(Object? raw) {
    final out = <Sample>[];
    if (raw is! List) return out;
    for (final r in raw) {
      if (r is! List || r.length < 5) continue;
      out.add(Sample((r[0] as num).toDouble(), (r[1] as num?)?.toDouble(),
          (r[2] as num).toInt(), (r[3] as num).toDouble(), (r[4] as num).toInt()));
    }
    return out;
  }
}

double _pct(List<double> s, double p) =>
    s.isEmpty ? double.nan : s[((s.length - 1) * p).round()];

/// Medianas, percentiles, fuera de tolerancia y saltos de n.
Map<String, Object?> regime(List<Sample> all, {double fromMs = 1000, double? toMs}) {
  final xs = all.where((s) => s.t >= fromMs && (toMs == null || s.t < toMs)).toList();
  final es = [for (final s in xs) if (s.e != null) s.e!]..sort();
  var out = 0, skipped = 0, repeated = 0, back = 0;
  for (final e in es) {
    if (!inTol(e)) out++;
  }
  for (var i = 1; i < xs.length; i++) {
    final d = xs[i].n - xs[i - 1].n;
    if (xs[i].epoch != xs[i - 1].epoch) continue;
    if (d == 0) {
      repeated++;
    } else if (d < 0) {
      back++;
    } else if (d > 1) {
      skipped += d - 1;
    }
  }
  final dur = xs.length < 2 ? 0.0 : (xs.last.t - xs.first.t) / 1000;
  return {
    'samples': xs.length,
    'withE': es.length,
    'e_ms': {
      'median': round3(_pct(es, .5)),
      'p95': round3(_pct(es, .95)),
      'p99': round3(_pct(es, .99)),
      'min': es.isEmpty ? null : round3(es.first),
      'max': es.isEmpty ? null : round3(es.last),
    },
    'outOfTolPct': es.isEmpty ? null : round3(out * 100 / es.length),
    'repeated': repeated,
    'skipped': skipped,
    'backSteps': back,
    'deliveriesPerSec': dur > 0 ? round3((xs.length - 1) / dur) : null,
  };
}

/// Desde [fromMs]: ms hasta la primera muestra en tolerancia (first) y hasta
/// la primera tras la cual ya no hay ninguna fuera (stay). null = no ocurre.
Map<String, Object?> recovery(List<Sample> all, double fromMs, [double? toMs]) {
  final xs = all
      .where((s) => s.t >= fromMs && (toMs == null || s.t < toMs) && s.e != null)
      .toList();
  double? first, stay;
  for (final s in xs) {
    if (inTol(s.e!)) {
      first ??= s.t - fromMs;
    }
  }
  var lastBad = -1;
  for (var i = 0; i < xs.length; i++) {
    if (!inTol(xs[i].e!)) lastBad = i;
  }
  if (lastBad + 1 < xs.length) stay = xs[lastBad + 1].t - fromMs;
  return {
    'firstOkMs': first == null ? null : round3(first),
    'stayOkMs': stay == null ? null : round3(stay),
  };
}
