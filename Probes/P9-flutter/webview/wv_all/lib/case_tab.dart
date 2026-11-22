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
  await Future<void>.delayed(const Duration(seconds: 1));
  const fracs = [Size(1, 1), Size(0.7, 0.75), Size(0.5, 0.5)];
  final steps = <Json>[];
  var prevRendered = c.counts['rendered'] ?? 0;
  for (final f in fracs) {
    c.st.frac = f;
    c.st.status = 'tamano ${f.width}x${f.height}';
    c.st.changed();
    await Future<void>.delayed(const Duration(seconds: 1));
    final w = c.st.avail.width * f.width, h = c.st.avail.height * f.height;
    final s = await c.evalJson('probe.state()') as Json;
    final rendered = c.counts['rendered'] ?? 0;
    steps.add({
      'widgetSize': '${w.toStringAsFixed(1)}x${h.toStringAsFixed(1)}',
      'innerSize': '${s['iw']}x${s['ih']}',
      'innerMatchesWidget': ((s['iw'] as num) - w).abs() <= 1 && ((s['ih'] as num) - h).abs() <= 1,
      'surfaceWidth': s['surfaceW'],
      'renderedEventsSinceLast': rendered - prevRendered,
      'renderedEventsTotal': rendered,
    });
    prevRendered = rendered;
  }
  c.report['steps'] = steps;
  final allMatch = steps.every((s) => s['innerMatchesWidget'] == true);
  final rerender = steps.skip(1).every((s) => (s['renderedEventsSinceLast'] as int) > 0);
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
    c.report['visibilityStates'] = {for (final s in arrivals) '${s['vis']}'};
  } else {
    c.fail('menos de 2 muestras recibidas: la pagina quedo suspendida');
  }
}
