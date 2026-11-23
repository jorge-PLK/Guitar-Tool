// P9 7g: caso fpsbar. Pagina fpsbar.html (fondo negro, barra blanca que avanza por rAF) a pantalla completa del WebView.
// El detector externo (win/tear.ps1 -Series) mide lo que llega a pantalla; aqui solo se anota rafFps y rafMaxGapMs (lado JS).
// Duracion: --capture-secs (por defecto 20). Sin cambios de estado de Flutter durante la medida (nada se repinta fuera del WebView).
import 'dart:async';

import 'case_tab.dart';
import 'ctx.dart';

Future<void> runFpsBar(Ctx c) async {
  if (!await loadPage(c, 'fpsbar.html')) return;
  final secs = c.args.intOr('--capture-secs', 20);
  await c.web.run('fb.start()');
  await Future<void>.delayed(Duration(seconds: secs));
  await c.web.run('fb.stop()');
  await Future<void>.delayed(const Duration(milliseconds: 300));
  final info = await c.evalJson('fb.info()') as Json;
  c.report['rafFps'] = info['rafFps'];
  c.report['rafMaxGapMs'] = info['rafMaxGapMs'];
  c.report['rafFrames'] = info['n'];
  c.report['jsDevicePixelRatio'] = info['dpr'];
  c.report['jsInnerWidth'] = info['iw'];
  c.report['jsInnerHeight'] = info['ih'];
  c.report['barStepPx'] = info['step'];
  c.report['barWidthPx'] = info['barPx'];
  c.report['measureSecs'] = secs;
}
