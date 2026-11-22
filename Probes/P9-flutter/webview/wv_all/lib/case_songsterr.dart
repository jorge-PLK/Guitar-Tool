// P9.4: caso songsterr (WebView oculto, UA de Safari, una sola peticion).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import 'ctx.dart';

const _modes = ['none', 'offstage', 'zero', 'offscreen'];

/// Prueba local (sin red) de un modo de ocultacion: carga HTML propio y lee outerHTML.
Future<Json> _testHidden(Ctx c, String mode) async {
  final sw = Stopwatch()..start();
  try {
    await c.newWeb(userAgent: safariUa);
    c.st.hidden = mode;
    c.st.changed();
    await WidgetsBinding.instance.endOfFrame;
    await c.loadAndWait(() => c.web.loadHtml('<html><body><p id="x">hidden-test</p></body></html>'), const Duration(seconds: 6));
    final html = await c.web.eval('document.documentElement.outerHTML').timeout(const Duration(seconds: 4));
    return {'ok': html.contains('hidden-test'), 'ms': sw.elapsedMilliseconds};
  } catch (e) {
    return {'ok': false, 'error': '$e', 'ms': sw.elapsedMilliseconds};
  }
}

/// Songsterr real con un modo oculto fijo (--mode): ms hasta pagina lista, bytes, titulo y JS vivo.
Future<void> _runHiddenReal(Ctx c, String mode) async {
  c.report['hiddenModeUsed'] = mode;
  final sw = Stopwatch()..start();
  try {
    await c.newWeb(userAgent: safariUa);
    c.st.hidden = mode;
    c.st.status = 'songsterr (oculto: $mode)';
    c.st.changed();
    await WidgetsBinding.instance.endOfFrame;
    await c.loadAndWait(() => c.web.loadUrl('https://www.songsterr.com/'), const Duration(seconds: 15));
  } on TimeoutException {
    c.report['msToPageReady'] = null;
    c.fail('no cargo en 15 s (modo $mode)');
    return;
  } catch (e) {
    c.fail('carga fallo ($mode): $e');
    return;
  }
  c.report['msToPageReady'] = sw.elapsedMilliseconds;
  try {
    var s = await c.web.eval('document.documentElement.outerHTML');
    if (s.startsWith('"') && s.endsWith('"')) s = jsonDecode(s) as String;
    c.report['htmlBytes'] = utf8.encode(s).length;
    c.report['title'] = await c.web.eval('document.title');
    c.report['readyState'] = await c.web.eval('document.readyState');
    await c.web.run('window.__n=0;setInterval(function(){window.__n++},100);');
    await Future<void>.delayed(const Duration(seconds: 2));
    final raw = await c.web.eval('String(window.__n)');
    c.report['jsTicksRaw'] = raw;
    final n = int.tryParse(raw.replaceAll('"', '')) ?? 0;
    c.report['jsTicksIn2s'] = n;
    c.report['jsAlive'] = n >= 5;
    c.report['navigatorUserAgent'] = await c.web.eval('navigator.userAgent');
    c.report['ok'] = (c.report['htmlBytes'] as int) > 0;
  } catch (e) {
    c.fail('eval fallo ($mode): $e');
  }
}

Future<void> runSongsterr(Ctx c) async {
  final fixed = c.args.get('--mode');
  if (fixed != null) return _runHiddenReal(c, fixed);
  c.report['offscreenApi'] = await (() async {
    try {
      await c.newWeb();
      return await c.web.offscreenSupport();
    } catch (e) {
      return 'error: $e';
    }
  })();
  final modes = <String, Json>{};
  String? chosen;
  for (final m in _modes) {
    c.st.status = 'probando oculto: $m';
    modes[m] = await _testHidden(c, m);
    if (chosen == null && modes[m]!['ok'] == true) chosen = m;
  }
  c.report['hiddenModesLocalTest'] = modes;
  c.report['hiddenModeUsed'] = chosen;
  if (chosen == null) {
    c.fail('ningun modo de WebView oculto cargo HTML local');
    return;
  }
  await c.newWeb(userAgent: safariUa);
  c.st.hidden = chosen;
  c.st.status = 'songsterr (oculto: $chosen)';
  c.st.changed();
  await WidgetsBinding.instance.endOfFrame;
  final sw = Stopwatch()..start();
  try {
    await c.loadAndWait(() => c.web.loadUrl('https://www.songsterr.com/'), const Duration(seconds: 40));
  } on TimeoutException {
    c.fail('onPageFinished no llego en 40 s');
  } catch (e) {
    c.fail('carga fallo: $e');
  }
  c.report['secondsToPageFinished'] = sw.elapsedMilliseconds / 1000.0;
  if (c.report['ok'] == false) {
    c.report['webErrorsAtFail'] = c.webErrors;
    return;
  }
  Future<int> bytes() async {
    var s = await c.web.eval('document.documentElement.outerHTML');
    if (s.startsWith('"') && s.endsWith('"')) s = jsonDecode(s) as String;
    return utf8.encode(s).length;
  }

  c.report['htmlBytesAtFinish'] = await bytes();
  c.report['secondsToFirstHtml'] = sw.elapsedMilliseconds / 1000.0;
  await Future<void>.delayed(const Duration(seconds: 4));
  c.report['htmlBytesAfter4s'] = await bytes();
  c.report['navigatorUserAgent'] = await c.web.eval('navigator.userAgent');
  c.report['title'] = await c.web.eval('document.title');
  c.report['uaPlugin'] = await c.web.userAgentFromPlugin();
  c.report['uaSetTo'] = safariUa;
  c.report['uaMatches'] = '${c.report['navigatorUserAgent']}'.contains('Version/17.5');
  c.report['totalSeconds'] = sw.elapsedMilliseconds / 1000.0;
}
