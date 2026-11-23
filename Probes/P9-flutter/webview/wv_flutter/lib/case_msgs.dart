// P9.4: casos messages y keys (pagina assets/web/probe.html).
import 'dart:async';

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
