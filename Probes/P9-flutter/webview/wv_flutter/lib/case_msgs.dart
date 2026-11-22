// P9.4: casos messages y keys (pagina assets/web/probe.html).
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'case_tab.dart';
import 'ctx.dart';

Json _seq(List<int> got, int expected) {
  final set = got.toSet();
  var ooo = 0;
  for (var i = 1; i < got.length; i++) {
    if (got[i] < got[i - 1]) ooo++;
  }
  return {
    'sent': expected,
    'received': got.length,
    'missing': expected - set.length,
    'duplicates': got.length - set.length,
    'outOfOrder': ooo,
  };
}

Future<void> runMessages(Ctx c) async {
  if (!await loadPage(c, 'probe.html')) return;
  // A) ida y vuelta secuencial: Dart->JS (runJavaScript) y JS->Dart (canal), numerados.
  final rtts = <double>[];
  final pend = <int, Completer<void>>{};
  final order = <int>[];
  c.handlers['echo'] = (m) {
    final n = m['n'] as int;
    order.add(n);
    pend.remove(n)?.complete();
  };
  var lost = 0;
  for (var i = 1; i <= 1000; i++) {
    final cp = Completer<void>();
    pend[i] = cp;
    final sw = Stopwatch()..start();
    try {
      await c.web.run('probe.echo($i)');
      await cp.future.timeout(const Duration(seconds: 2));
      rtts.add(sw.elapsedMicroseconds / 1000.0);
    } on TimeoutException {
      lost++;
      pend.remove(i);
    }
  }
  c.report['roundTrip'] = {'rttMs': stats(rtts), 'lost': lost, 'seq': _seq(order, 1000)};
  // B) rafaga JS->Dart.
  final got = <int>[];
  final done = Completer<void>();
  c.handlers['b'] = (m) => got.add(m['n'] as int);
  c.handlers['bdone'] = (m) {
    if (!done.isCompleted) done.complete();
  };
  final swB = Stopwatch()..start();
  await c.web.run('probe.burst(1000)');
  await done.future.timeout(const Duration(seconds: 10), onTimeout: () {});
  await Future<void>.delayed(const Duration(seconds: 1));
  c.report['burstJsToDart'] = {..._seq(got, 1000), 'totalMs': swB.elapsedMilliseconds};
  // C) rafaga Dart->JS: 1000 llamadas sin esperar entre ellas.
  final swC = Stopwatch()..start();
  final futs = <Future<void>>[for (var n = 1; n <= 1000; n++) c.web.run('probe.recv($n)')];
  await Future.wait(futs);
  final issueMs = swC.elapsedMilliseconds;
  c.clearSeen('rdone');
  await c.web.run('probe.recvReport()');
  try {
    final r = await c.waitEvent('rdone', timeout: const Duration(seconds: 5));
    c.report['burstDartToJs'] = {
      'sent': 1000,
      'received': r['count'],
      'missing': r['missing'],
      'duplicates': r['duplicates'],
      'outOfOrder': r['outOfOrder'],
      'issueMs': issueMs,
    };
  } on TimeoutException {
    c.report['burstDartToJs'] = {'error': 'sin informe de la pagina', 'issueMs': issueMs};
  }
  final bad = lost > 0 ||
      (c.report['roundTrip'] as Json)['seq']['outOfOrder'] != 0 ||
      got.length != 1000 ||
      (c.report['burstDartToJs'] as Json)['received'] != 1000;
  if (bad) c.report['ok'] = false;
}

String _label(KeyEvent e) => e.logicalKey.keyLabel.isEmpty ? (e.logicalKey.debugName ?? '?') : e.logicalKey.keyLabel;

Future<void> runKeys(Ctx c) async {
  if (!await loadPage(c, 'probe.html')) return;
  final flutterSeq = <Json>[];
  final jsSeq = <Json>[];
  int now() => DateTime.now().millisecondsSinceEpoch;
  bool handler(KeyEvent e) {
    if (flutterSeq.length < 5000) {
      flutterSeq.add({
        'type': e is KeyDownEvent ? 'down' : (e is KeyUpEvent ? 'up' : 'repeat'),
        'key': _label(e),
        'physical': e.physicalKey.debugName,
        'ts': now(),
        'primaryFocus': FocusManager.instance.primaryFocus?.debugLabel ?? 'none',
      });
    }
    return false;
  }

  HardwareKeyboard.instance.addHandler(handler);
  c.handlers['key'] = (m) {
    if (jsSeq.length < 5000) jsSeq.add({...m, 'dartTs': now()});
  };
  c.st.keys = true;
  c.st.onFocusAction = (action) {
    flutterSeq.add({'type': 'focusAction', 'action': action, 'ts': now()});
    if (action == 'webview') {
      c.st.focusNode.unfocus();
      unawaited(c.web.run("window.focus();document.body.tabIndex=0;document.body.focus();__post({event:'focusAction',action:'webview',ts:Date.now()})"));
    } else {
      c.st.focusNode.requestFocus();
    }
  };
  c.handlers['focusAction'] = (m) => jsSeq.add({...m, 'type': 'focusAction'});
  c.st.status = 'PULSA TECLAS (pasos en el encargo)';
  c.st.changed();
  final total = c.args.intOr('--exit-after', 60);
  await Future<void>.delayed(Duration(seconds: total > 8 ? total - 4 : 4));
  HardwareKeyboard.instance.removeHandler(handler);
  try {
    c.report['jsPageSideCount'] = (await c.evalJson('JSON.stringify(window.__keys)') as List).length;
  } catch (e) {
    c.report['jsPageSideCount'] = 'error: $e';
  }
  Json tally(List<Json> seq, String keyField) {
    final t = <String, Json>{};
    for (final e in seq) {
      final type = '${e['type']}';
      if (type == 'focusAction') continue;
      final k = '${e[keyField]}';
      final j = t[k] ??= {'down': 0, 'up': 0, 'repeat': 0};
      final norm = type == 'keydown' ? 'down' : (type == 'keyup' ? 'up' : type);
      j[norm] = (j[norm] as int) + 1;
    }
    return t;
  }

  c.report['jsSequence'] = jsSeq;
  c.report['flutterSequence'] = flutterSeq;
  c.report['jsTally'] = tally(jsSeq, 'key');
  c.report['flutterTally'] = tally(flutterSeq, 'key');
  c.report['jsEvents'] = jsSeq.where((e) => e['type'] != 'focusAction').length;
  c.report['flutterEvents'] = flutterSeq.where((e) => e['type'] != 'focusAction').length;
  c.report['fieldText'] = c.st.fieldController.text;
}
