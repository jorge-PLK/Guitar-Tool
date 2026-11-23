// P9.4: casos que parten de la tablatura cargada: tab, overlay, resize, occluded.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'ctx.dart';

/// Carga una pagina de assets/web/ y espera 'ready'. Devuelve false (y marca fallo) si no llega.
Future<bool> loadPage(Ctx c, String page) async {
  await c.newWeb();
  c.st.showWeb = true;
  c.st.status = 'cargando $page';
  c.st.changed();
  await WidgetsBinding.instance.endOfFrame;
  final sw = Stopwatch()..start();
  try {
    await c.web.loadAsset('assets/web/$page');
  } catch (e) {
    c.report['serving'] = c.web.serving;
    c.fail('loadAsset fallo: $e');
    return false;
  }
  c.report['serving'] = c.web.serving;
  try {
    await c.waitEvent('ready', timeout: const Duration(seconds: 15));
  } on TimeoutException {
    c.fail('el evento ready de $page no llego en 15 s (recursos locales no cargaron)');
    return false;
  }
  c.report['timeToReadyMs'] = sw.elapsedMilliseconds;
  c.report['readyAfterAppStartMs'] = c.ms;
  c.st.status = 'listo';
  c.st.changed();
  return true;
}

/// tab.html + partitura de ejemplo. Devuelve false si alphaTab no termina de renderizar.
Future<bool> loadTab(Ctx c) async {
  if (!await loadPage(c, 'tab.html')) return false;
  final score = await rootBundle.loadString('assets/web/score.json');
  final sw = Stopwatch()..start();
  await c.web.run('TF.load(${jsonEncode(score)}, 0)');
  try {
    await c.waitEvent('rendered', timeout: const Duration(seconds: 20));
  } on TimeoutException {
    c.fail('alphaTab no emitio rendered en 20 s tras TF.load');
    return false;
  }
  c.report['scoreLoadToRenderedMs'] = sw.elapsedMilliseconds;
  c.report['rendered'] = true;
  return true;
}

Future<void> runTab(Ctx c) async {
  if (!await loadTab(c)) return;
  await Future<void>.delayed(const Duration(milliseconds: 500));
  final diag = await c.evalJson('probe.diag()') as Json;
  c.report['diag'] = diag;
  unawaited(c.web.run('probe.resources()'));
  try {
    final r = await c.waitEvent('res', timeout: const Duration(seconds: 10));
    c.report['resources'] = r['results'];
  } on TimeoutException {
    c.report['resources'] = 'sin respuesta';
  }
  c.report['bravuraLoaded'] = diag['bravuraLoaded'];
  final okFont = diag['bravuraLoaded'] == true;
  if (!okFont) c.fail('Bravura no aparece cargada en document.fonts');
  if (c.jsErrors.isNotEmpty) c.report['ok'] = false;
}

Future<void> runOverlay(Ctx c) async {
  if (!await loadTab(c)) return;
  c.st.overlay = true;
  c.st.status = 'overlay encima del WebView';
  c.st.changed();
  await Future<void>.delayed(const Duration(milliseconds: 1500));
  c.report['note'] = 'ver captura externa: la caja naranja debe estar encima de la partitura';
}

Future<void> runResize(Ctx c) async {
  if (!await loadTab(c)) return;
  // --raf-loop on|off: con on la pagina mantiene un bucle rAF vacio permanente durante todo el caso.
  final raf = c.args.get('--raf-loop') == 'on';
  c.report['rafLoop'] = raf;
  if (raf) await c.web.run('window.__rl=0;(function l(){window.__rl++;requestAnimationFrame(l)})()');
  final renderedAt = <double>[];
  c.handlers['rendered'] = (_) => renderedAt.add(c.clock.elapsedMicroseconds / 1000.0);
  await Future<void>.delayed(const Duration(seconds: 1));
  const widths = [800.0, 560.0, 400.0, 800.0];
  final steps = <Json>[];
  final availW = c.st.avail.width;
  for (final req in widths) {
    final w = req < availW ? req : availW; // la ventana puede ser mas estrecha que el paso
    final nBefore = renderedAt.length;
    final t0 = c.clock.elapsedMicroseconds / 1000.0;
    c.st.frac = Size(w / availW, 1);
    c.st.status = 'ancho $w';
    c.st.changed();
    double? toIw, toRe;
    num iw = -1;
    while (c.clock.elapsedMicroseconds / 1000.0 - t0 < 4000 && (toIw == null || renderedAt.length == nBefore)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      iw = await c.evalJson('window.innerWidth') as num;
      final now = c.clock.elapsedMicroseconds / 1000.0;
      if (toIw == null && (iw - w).abs() <= 1) toIw = now - t0;
      if (toRe == null && renderedAt.length > nBefore) toRe = renderedAt[nBefore] - t0;
    }
    if (renderedAt.length > nBefore) toRe ??= renderedAt[nBefore] - t0;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final s = await c.evalJson('probe.state()') as Json;
    iw = s['iw'] as num;
    final surf = (s['surfaceW'] as num).toDouble();
    final rerendered = renderedAt.length > nBefore;
    steps.add({
      'requestedWidth': req,
      'expectedInnerWidth': w,
      'innerWidth': iw,
      'innerWidthMatches': (iw - w).abs() <= 1,
      'alphaTabRerendered': rerendered,
      'msToInnerWidth': toIw,
      'msToRerender': toRe,
      'surfaceWidth': surf,
      // Repintado: alphaTab volvio a renderizar y su superficie cabe en el ancho nuevo (no conserva el ancho anterior).
      'repaintedAfterResize': rerendered && surf > 0 && surf <= iw + 1,
    });
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  if (raf) c.report['rafLoopFrames'] = await c.evalJson('window.__rl');
  c.handlers.remove('rendered');
  c.report['steps'] = steps;
  final allMatch = steps.every((s) => s['innerWidthMatches'] == true);
  final rerender = steps.skip(1).every((s) => s['alphaTabRerendered'] == true);
  c.report['allInnerMatch'] = allMatch;
  c.report['alphaTabRerenderedEveryStep'] = rerender;
  if (!allMatch || !rerender) c.report['ok'] = false;
}

Future<void> runOccluded(Ctx c) async {
  if (!await loadTab(c)) return;
  final delay = c.args.intOr('--occluded-delay', 0);
  c.st.status = 'esperando $delay s';
  c.st.changed();
  await Future<void>.delayed(Duration(seconds: delay));
  const secs = 10;
  final arrivals = <Json>[];
  c.handlers['occ'] = (m) => arrivals.add({...m, 'dartMs': c.ms});
  c.st.status = 'midiendo $secs s';
  c.st.changed();
  await c.web.run('probe.startCount($secs)');
  final deadline = Stopwatch()..start();
  while (arrivals.length < secs && deadline.elapsed < const Duration(seconds: secs + 8)) {
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  c.report['samples'] = arrivals;
  c.report['samplesReceived'] = arrivals.length;
  if (arrivals.length >= 2) {
    final a = arrivals.first, b = arrivals.last;
    final dt = ((b['t'] as num) - (a['t'] as num)) / 1000.0;
    c.report['rafFps'] = ((b['raf'] as num) - (a['raf'] as num)) / dt;
    c.report['ticksPerSecond'] = ((b['ticks'] as num) - (a['ticks'] as num)) / dt;
    c.report['expectedTicksPerSecond'] = 10;
    c.report['visibilityStates'] = {for (final s in arrivals) '${s['vis']}'}.toList();
  } else {
    c.fail('menos de 2 muestras recibidas: la pagina quedo suspendida');
  }
}
