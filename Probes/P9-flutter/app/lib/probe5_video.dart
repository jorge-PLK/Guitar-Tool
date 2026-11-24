import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'ffi/tf_core.dart';
import 'probe2_steps.dart';
import 'probe2_util.dart';
import 'probe3_measure.dart';
import 'probe5_measure.dart';

String? _opt(List<String> a, String n) {
  final i = a.indexOf(n);
  return (i >= 0 && i + 1 < a.length) ? a[i + 1] : null;
}

const _enc = JsonEncoder.withIndent('  ');
const _ch = 0;
String _phase = 'init';

/// Textura + giro por metadato (info.rotationDegrees) a tamaño de pantalla.
class _Surf {
  _Surf(this.id, this.w, this.h, this.dw, this.dh, this.quarter);
  final int id;
  final double w, h, dw, dh;
  final int quarter;
}

class _View extends StatelessWidget {
  const _View(this.surf);
  final ValueNotifier<_Surf?> surf;

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: const Color(0xFF000000),
          child: Center(
            child: ValueListenableBuilder<_Surf?>(
              valueListenable: surf,
              builder: (_, s, _) => s == null
                  ? const SizedBox.shrink()
                  : AspectRatio(
                      aspectRatio: s.dw / s.dh,
                      child: RotatedBox(
                        quarterTurns: s.quarter,
                        child: AspectRatio(
                          aspectRatio: s.w / s.h,
                          // Magenta detrás (diagnóstico 7h): si la captura lo muestra, el widget existe pero la textura no pinta.
                          child: ColoredBox(
                            color: const Color(0xFFFF00FF),
                            child: Texture(textureId: s.id),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      );
}

/// Prueba 5 de P9, candidata nativa. Salida: 0 pasa, 1 incumple, 3 error.
void startProbe5(List<String> args) {
  final surf = ValueNotifier<_Surf?>(null);
  final wd = Watchdog()..start();
  final ft = FrameTimings()..start();
  runApp(_View(surf));
  WidgetsBinding.instance.addPostFrameCallback((_) => _run(args, surf, wd, ft));
}

Future<void> _run(List<String> args, ValueNotifier<_Surf?> surf, Watchdog wd,
    FrameTimings ft) async {
  final kase = _opt(args, '--case') ?? 'steady';
  final failed = <String>[];
  final report = <String, Object?>{
    'probe': 'video',
    'candidate': 'native',
    'case': kase,
    'file': _opt(args, '--file'),
    'startedAt': DateTime.now().toIso8601String(),
    'failed': failed,
  };
  final path = _opt(args, '--report');
  // Los NaN/infinitos (p. ej. mediana sin muestras) hacen fallar jsonEncode: se vuelcan como null.
  Object? clean(Object? o) => o is double && !o.isFinite
      ? null
      : o is Map
          ? {for (final e in o.entries) '${e.key}': clean(e.value)}
          : o is List
              ? [for (final e in o) clean(e)]
              : o;
  void write() {
    if (path == null) return;
    try {
      File(path).writeAsStringSync(_enc.convert(clean(report)));
    } catch (e) {
      File(path).writeAsStringSync('{"writeError":"$e","case":"$kase","aborted":${report['aborted'] == true}}');
    }
  }

  final limit = double.tryParse(_opt(args, '--exit-after') ?? '') ?? 120;
  Timer(Duration(milliseconds: (limit * 1000).round()), () {
    report['aborted'] = true;
    report['phase'] = _phase;
    failed.add('aborted');
    try {
      write();
    } finally {
      exit(3);
    }
  });
  try {
    await _measure(args, surf, wd, ft, kase, report);
  } catch (e, st) {
    report['exception'] = '$e\n$st';
    failed.add('exception');
    write();
    exit(3);
  }
  write();
  exit(failed.isEmpty ? 0 : 1);
}

Future<void> _wait(double s) =>
    Future<void>.delayed(Duration(milliseconds: (s * 1000).round()));

Future<void> _measure(List<String> args, ValueNotifier<_Surf?> surf, Watchdog wd,
    FrameTimings ft, String kase, Map<String, Object?> report) async {
  final failed = report['failed'] as List<String>;
  final libPath = _opt(args, '--core-lib')!;
  final core = TfCore.open(libPath, 'port');
  final rc = core.start(jsonEncode({
    'args': [
      '--projects-folder', _opt(args, '--projects-folder')!,
      '--support-dir', _opt(args, '--support-dir')!,
      '--audio', 'simulated',
    ],
  }));
  report['startRc'] = rc;
  if (rc != 0) {
    failed.add('startRc=$rc');
    return;
  }
  _phase = 'open';
  final v = TfVideo.open(libPath); // lookups perezosos: solo en este modo
  final sw = Stopwatch()..start();
  final file = _opt(args, '--file')!;
  final orc = v.openFile(_ch, file);
  report['openRc'] = orc;
  report['fileExists'] = File(file).existsSync();
  if (orc != 0) {
    failed.add('videoOpen');
    core.shutdown(5000);
    return;
  }
  // Apertura asíncrona: sondeo sin bloquear el isolate (tope 5 s).
  var st = v.state(_ch);
  while (st == 0 && sw.elapsedMilliseconds < 5000) {
    await _wait(0.01);
    st = v.state(_ch);
  }
  report['openMs'] = sw.elapsedMilliseconds;
  report['openState'] = st;
  if (st != 1) {
    report['openInfo'] = v.info(_ch);
    failed.add('videoOpen state=$st');
    v.close(_ch);
    core.shutdown(5000);
    return;
  }
  _phase = 'case';
  final info = v.info(_ch);
  report['info'] = info;
  final id = v.textureCreate(_ch);
  report['textureId'] = id;
  if (id < 0) {
    failed.add('textureCreate=$id');
    v.close(_ch);
    core.shutdown(5000);
    return;
  }
  double num_(String k) => (info[k] as num?)?.toDouble() ?? 0;
  final rot = (num_('rotationDegrees') ~/ 90) % 4;
  surf.value = _Surf(id, num_('width'), num_('height'), num_('displayWidth'),
      num_('displayHeight'), rot);
  report['quarterTurns'] = rot;
  await _wait(0.2);
  final duration = num_('duration');

  // Reloj conducido por Dart: posición = base + rate * (ahora - t0).
  var pos0 = 0.0, rate = 1.0, t0 = sw.elapsedMicroseconds;
  double now() => pos0 + rate * (sw.elapsedMicroseconds - t0) / 1e6;
  void setClock(double p, double r, {bool jump = false}) {
    pos0 = p;
    rate = r;
    t0 = sw.elapsedMicroseconds;
    v.clock(_ch, p, r, true, jump);
  }

  void changeRate(double r) => setClock(now(), r);
  final rss = <String, double>{};
  Timer(const Duration(seconds: 5), () => rss['5s'] = rssMb());
  final cpu0 = cpuSeconds();
  final wall0 = sw.elapsedMicroseconds / 1e6;
  wd.reset();
  ft.active = true;

  final res = <String, Object?>{};
  report['result'] = res;
  switch (kase) {
    case 'steady':
      v.stats(_ch, reset: true);
      setClock(0, 1.0, jump: true);
      var worst = 0.0;
      for (final r in [1.0, 0.7, 0.5]) {
        if (r != 1.0) changeRate(r);
        v.stats(_ch, reset: true);
        await _wait(10);
        final st = v.stats(_ch);
        final reg = regime(Sample.parse(st['samples']));
        reg['resyncs'] = st['resyncs'];
        reg['driftResyncs'] = st['driftResyncs'];
        reg['unreadable'] = st['unreadable'];
        reg['deliveries'] = st['deliveries'];
        if (st['win'] != null) reg['win'] = st['win']; // solo Windows (tf_mfvideo.c)
        res['rate_$r'] = reg;
        final pct = (reg['outOfTolPct'] as num?)?.toDouble() ?? 100;
        if (pct > worst) worst = pct;
      }
      if (worst > 1) failed.add('fuera=$worst%');
    case 'seek':
      final jumps = <Map<String, Object?>>[];
      for (final t in [20.0, 8.0, 0.0, 25.0, 2.0, duration - 2]) {
        v.stats(_ch, reset: true);
        setClock(t, 1.0, jump: true);
        await _wait(2.5);
        final st = v.stats(_ch);
        final xs = Sample.parse(st['samples']);
        final rec = recovery(xs, 0);
        jumps.add({'target': t, ...rec, 'events': st['events'], if (st['win'] != null) 'win': st['win']});
        final stay = (rec['stayOkMs'] as num?)?.toDouble();
        if (stay == null || stay >= 300) failed.add('seek@$t=${stay ?? 'nunca'}');
      }
      res['jumps'] = jumps;
    case 'loop':
      v.stats(_ch, reset: true);
      v.loop(_ch, 10, 12, true);
      setClock(10, 1.0, jump: true);
      await _wait(13.5);
      final st = v.stats(_ch);
      final xs = Sample.parse(st['samples']);
      final laps = <double>[];
      for (var i = 1; i < xs.length; i++) {
        if (xs[i].epoch != xs[i - 1].epoch && xs[i].t > 1500) laps.add(xs[i].t);
      }
      final lapRec = [for (final t in laps) recovery(xs, t, t + 1500)];
      res['lapStartsMs'] = laps;
      res['recovery'] = lapRec;
      res['events'] = st['events'];
      if (st['win'] != null) res['win'] = st['win'];
      final ok = xs.where((s) {
        if (s.t < 1000) return false;
        return !laps.any((t) => s.t >= t && s.t < t + 300);
      }).toList();
      res['inLoop'] = regime(ok, fromMs: 0);
      final pct = ((res['inLoop'] as Map)['outOfTolPct'] as num?)?.toDouble() ?? 100;
      if (pct > 1) failed.add('fueraBucle=$pct%');
      if (laps.length < 5) failed.add('vueltas=${laps.length}');
      for (final r in lapRec) {
        final s = (r['stayOkMs'] as num?)?.toDouble();
        if (s == null || s >= 300) failed.add('vuelta=${s ?? 'nunca'}');
      }
      v.loop(_ch, 10, 12, false);
    default: // rotation, start-pts
      v.stats(_ch, reset: true);
      final tCall = sw.elapsedMicroseconds;
      setClock(0, 1.0, jump: true);
      await _wait(3);
      res['midSecondAt'] = 'captura del script a ~3 s';
      await _wait(3);
      final st = v.stats(_ch);
      final xs = Sample.parse(st['samples']);
      res['info'] = info;
      res['firstDeliveryMsAfterClock'] = xs.isEmpty ? null : xs.first.t;
      res['clockCallAtMs'] = round3((tCall - 0) / 1000);
      res['events'] = st['events'];
      res['regime'] = regime(xs);
      if (st['win'] != null) res['win'] = st['win'];
      if (xs.isEmpty) failed.add('sinEntregas');
  }

  final cpu = cpuSeconds() - cpu0;
  final wall = sw.elapsedMicroseconds / 1e6 - wall0;
  rss['end'] = rssMb();
  report['cpu'] = {
    'percentOfCore': round3(cpu / wall * 100),
    'cpuSeconds': round3(cpu),
    'wallSeconds': round3(wall),
  };
  report['rssMb'] = rss;
  report['watchdogMaxMs'] = round3(wd.maxDelayMs);
  await _wait(1.5); // FrameTiming llega por lotes
  ft.active = false;
  report['frameTiming'] = ft.toJson();

  _phase = 'shutdown';
  surf.value = null;
  await _wait(0.1);
  v.textureDispose(_ch);
  v.close(_ch);
  report['h_shutdown'] = await shutdownCore(core, wd);
}
