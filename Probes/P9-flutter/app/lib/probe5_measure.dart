import 'probe2_util.dart';

/// T = 1/(30000/1001) en ms. Tolerancia: -T/2 <= e < 1,5 T.
const frameMs = 33.3667;
bool inTol(double e) => e >= -frameMs / 2 && e < 1.5 * frameMs;

/// Windows (decisión de Jorge, P9 7h): criterio simétrico sobre el error visible e_vb (primer vblank tras la copia),
/// |e_vb| ≤ 16,7 ms (p05 ≥ −16,7 y p95 ≤ 16,7 en régimen). El Mac (sin e_vb) sigue con [inTol].
const evbTolMs = 16.7;
bool _ok(Sample s) => s.evb != null ? s.evb!.abs() <= evbTolMs : inTol(s.e!);

/// Muestra de `stats.samples`: [t_ms, e_ms|null, n, itemTime_s, epoch, e_vb_ms?] (e_vb solo en Windows).
class Sample {
  Sample(this.t, this.e, this.n, this.item, this.epoch, [this.evb]);
  final double t;
  final double? e;
  final int n;
  final double item;
  final int epoch;
  final double? evb;

  static List<Sample> parse(Object? raw) {
    final out = <Sample>[];
    if (raw is! List) return out;
    for (final r in raw) {
      if (r is! List || r.length < 5) continue;
      out.add(Sample((r[0] as num).toDouble(), (r[1] as num?)?.toDouble(),
          (r[2] as num).toInt(), (r[3] as num).toDouble(), (r[4] as num).toInt(),
          r.length > 5 ? (r[5] as num?)?.toDouble() : null));
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
  final evs = [for (final s in xs) if (s.e != null && s.evb != null) s.evb!]..sort();
  // Windows: veredicto sobre e_vb (p05 ≥ −16,7 y p95 ≤ 16,7 → fuera = 0, si no el % fuera de ±16,7).
  final useEvb = evs.isNotEmpty && evs.length == es.length;
  var out = 0, skipped = 0, repeated = 0, back = 0;
  if (useEvb) {
    if (_pct(evs, .05) < -evbTolMs || _pct(evs, .95) > evbTolMs) {
      out = evs.where((v) => v.abs() > evbTolMs).length;
      if (out == 0) out = 1;
    }
  } else {
    for (final e in es) {
      if (!inTol(e)) out++;
    }
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
    'outOfTolPct': es.isEmpty
        ? null
        : useEvb && out > 0
            ? 100.0 // percentil fuera de ±16,7: incumple siempre (el veredicto es > 1 %)
            : round3(out * 100 / es.length),
    if (useEvb) 'criterion': 'evb±16.7',
    if (useEvb)
      'evb_ms': {'p05': round3(_pct(evs, .05)), 'median': round3(_pct(evs, .5)), 'p95': round3(_pct(evs, .95))},
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
    if (_ok(s)) {
      first ??= s.t - fromMs;
    }
  }
  var lastBad = -1;
  for (var i = 0; i < xs.length; i++) {
    if (!_ok(xs[i])) lastBad = i;
  }
  if (lastBad + 1 < xs.length) stay = xs[lastBad + 1].t - fromMs;
  return {
    'firstOkMs': first == null ? null : round3(first),
    'stayOkMs': stay == null ? null : round3(stay),
    ...badTrace(all, fromMs, toMs, stay == null ? null : stay + fromMs),
  };
}

/// Máximo de muestras fuera de umbral que se vuelcan por salto (P9 7h, observabilidad).
const traceMax = 40;

/// Observabilidad de [recovery] (no cambia first/stay): muestras fuera de umbral entre [fromMs] y el stay
/// (o el final de la ventana si no hay stay), con ms desde el salto, PTS leído de la tira (n·T), PTS esperado
/// (leído + e), e y e_vb, `readFailed` (n < 0: sin lectura; `recovery` las ignora, no cuentan como fallo) y
/// el índice de fotograma n. `seq` de la textura no se exporta por stats: va a null.
/// Campos: badTotal (todas las fuera de umbral con lectura), unreadable (muestras sin lectura válida en la ventana),
/// badTrace (≤ [traceMax]), badTraceTruncated.
Map<String, Object?> badTrace(List<Sample> all, double fromMs, double? toMs, double? stayAbsMs) {
  final win = all.where((s) => s.t >= fromMs && (toMs == null || s.t < toMs)).toList();
  final end = stayAbsMs ?? double.infinity;
  final rows = <Map<String, Object?>>[];
  var bad = 0, unread = 0;
  for (final s in win) {
    final readFailed = s.e == null;
    if (readFailed) unread++;
    final isBad = readFailed || !_ok(s);
    if (!isBad) continue;
    if (!readFailed) bad++;
    if (s.t >= end) continue;
    rows.add({
      'tMs': round3(s.t - fromMs),
      'readPtsMs': readFailed ? null : round3(s.n * frameMs),
      'expectedPtsMs': readFailed ? null : round3(s.n * frameMs + s.e!),
      'eMs': s.e == null ? null : round3(s.e!),
      'evbMs': s.evb == null ? null : round3(s.evb!),
      'readFailed': readFailed,
      'frameIndex': s.n,
      'itemTimeS': s.item,
      'epoch': s.epoch,
      'texSeq': null,
    });
  }
  return {
    'badTotal': bad,
    'unreadable': unread,
    'badTraceTruncated': rows.length > traceMax,
    'badTrace': rows.take(traceMax).toList(),
  };
}
