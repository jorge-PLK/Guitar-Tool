// P9.7h.2: caso capture. Pagina con contador animado por rAF que manda {t:'raf', n, now} en cada frame.
// Mide: fps de rAF (JS), fps y p99 de build/raster de Flutter, latencia JS->Dart (desfase de relojes por ping de ida y vuelta,
// al inicio y al final, con la deriva), perdidos/duplicados/desordenados por n, y los devicePixelRatio de ambos lados.
// Duracion de la medida: --capture-secs (por defecto 20).
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'case_tab.dart';
import 'ctx.dart';

double _ms(Ctx c) => c.clock.elapsedMicroseconds / 1000.0;

/// Ida y vuelta de [k] pings; devuelve {offset, rtt} de la muestra con menor rtt (offset = reloj Dart - reloj JS).
Future<Json> _sync(Ctx c, int k) async {
  Completer<(double, double)>? pend;
  c.handlers['pong'] = (m) {
    final p = pend;
    if (p != null && !p.isCompleted) p.complete((_ms(c), (m['now'] as num).toDouble()));
  };
  double bestRtt = double.infinity, bestOff = 0;
  for (var i = 0; i < k; i++) {
    pend = Completer();
    final t0 = _ms(c);
    await c.web.run('cap.ping($i)');
    try {
      final (t1, now) = await pend.future.timeout(const Duration(seconds: 2));
      final rtt = t1 - t0;
      if (rtt < bestRtt) {
        bestRtt = rtt;
        bestOff = (t0 + t1) / 2 - now;
      }
    } on TimeoutException {
      // muestra perdida
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  c.handlers.remove('pong');
  return {'offsetMs': bestOff, 'rttMs': bestRtt, 'atMs': _ms(c)};
}

Future<void> runCapture(Ctx c) async {
  if (!await loadPage(c, 'capture.html')) return;
  final secs = c.args.intOr('--capture-secs', 20);
  final recvAt = <double>[], jsNow = <double>[], ns = <int>[];
  c.handlers['raf'] = (m) {
    recvAt.add(_ms(c));
    jsNow.add((m['now'] as num).toDouble());
    ns.add(m['n'] as int);
  };
  final build = <double>[], raster = <double>[];
  void timings(List<ui.FrameTiming> l) {
    for (final t in l) {
      build.add(t.buildDuration.inMicroseconds / 1000.0);
      raster.add(t.rasterDuration.inMicroseconds / 1000.0);
    }
  }

  final s0 = await _sync(c, 20);
  c.st.status = 'capturando $secs s';
  c.st.changed();
  WidgetsBinding.instance.addTimingsCallback(timings);
  final sw = Stopwatch()..start();
  await c.web.run('cap.start()');
  await Future<void>.delayed(Duration(seconds: secs));
  final elapsedS = sw.elapsedMicroseconds / 1e6;
  WidgetsBinding.instance.removeTimingsCallback(timings);
  await c.web.run('cap.stop()');
  await Future<void>.delayed(const Duration(milliseconds: 500));
  final s1 = await _sync(c, 20);
  final info = await c.evalJson('cap.info()') as Json;

  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  c.report['devicePixelRatios'] = {
    'flutter': view.devicePixelRatio,
    'js': info['dpr'],
    'jsInnerWidth': info['iw'],
    'jsInnerHeight': info['ih'],
  };
  final drift = (s1['offsetMs'] as double) - (s0['offsetMs'] as double);
  c.report['clockSync'] = {'start': s0, 'end': s1, 'driftMs': drift};

  // Latencia con el desfase interpolado entre las dos sincronias.
  final span = (s1['atMs'] as double) - (s0['atMs'] as double);
  final lat = <double>[];
  for (var i = 0; i < recvAt.length; i++) {
    final f = span > 0 ? (recvAt[i] - (s0['atMs'] as double)) / span : 0.0;
    final off = (s0['offsetMs'] as double) + drift * f;
    lat.add(recvAt[i] - (jsNow[i] + off));
  }
  final st = stats(lat);
  c.report['msgLatencyMs'] = {'median': st['median'], 'p99': st['p99'], 'max': st['max'], 'min': st['min'], 'n': st['n']};

  final sent = info['n'] as int;
  final uniq = ns.toSet().length;
  var ooo = 0;
  for (var i = 1; i < ns.length; i++) {
    if (ns[i] < ns[i - 1]) ooo++;
  }
  c.report['sequence'] = {
    'sent': sent,
    'received': ns.length,
    'lost': sent - uniq,
    'duplicated': ns.length - uniq,
    'outOfOrder': ooo,
  };
  if (ns.length >= 2) {
    final dt = (jsNow.last - jsNow.first) / 1000.0;
    c.report['rafFps'] = (ns.last - ns.first) / dt;
  } else {
    c.fail('menos de 2 mensajes raf recibidos');
  }
  c.report['measureSecs'] = elapsedS;
  c.report['flutterFrames'] = build.length;
  c.report['flutterFps'] = build.length / elapsedS;
  c.report['buildMs'] = {'p99': stats(build)['p99'], 'max': stats(build)['max'], 'median': stats(build)['median']};
  c.report['rasterMs'] = {'p99': stats(raster)['p99'], 'max': stats(raster)['max'], 'median': stats(raster)['median']};
}
