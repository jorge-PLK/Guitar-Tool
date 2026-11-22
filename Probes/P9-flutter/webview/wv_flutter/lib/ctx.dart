// P9.4: contexto compartido de los casos (argumentos, informe, mensajes del WebView).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as dart_ui;

import 'package:flutter/rendering.dart';

import 'probe_webview.dart';
import 'screen.dart';

class Args {
  Args(this.list);
  final List<String> list;
  String? get(String name) {
    final i = list.indexOf(name);
    return (i >= 0 && i + 1 < list.length) ? list[i + 1] : null;
  }

  int intOr(String name, int d) => int.tryParse(get(name) ?? '') ?? d;
}

typedef Json = Map<String, dynamic>;

const safariUa =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15';

class Ctx {
  Ctx(this.args);
  final Args args;
  final Json report = {};
  final st = UiState();
  late ProbeWebView web;
  final clock = Stopwatch()..start();
  final consoleLog = <String>[];
  final jsErrors = <String>[];
  final webErrors = <String>[];
  final counts = <String, int>{};
  final handlers = <String, void Function(Json)>{};
  final _seen = <String, Json>{};
  final _waiters = <String, List<Completer<Json>>>{};
  Completer<String>? _pageFinished;
  Future<void>? _finishing;
  int badMessages = 0;

  Future<void> newWeb({String? userAgent}) async {
    late final ProbeWebView w;
    w = ProbeWebView(
      onMessage: (raw) {
        if (identical(w, web)) _onMessage(raw);
      },
      onConsole: (level, msg) {
        if (consoleLog.length < 200) consoleLog.add('$level: $msg');
      },
      onPageFinished: (url) {
        final p = _pageFinished;
        _pageFinished = null;
        if (p != null && !p.isCompleted) p.complete(url);
      },
      onError: (d) => webErrors.add(d),
    );
    await w.init(userAgent: userAgent);
    web = w;
  }

  /// Ejecuta [load] y espera onPageFinished.
  Future<String> loadAndWait(Future<void> Function() load, Duration timeout) {
    final p = Completer<String>();
    _pageFinished = p;
    return () async {
      await load();
      return p.future.timeout(timeout);
    }();
  }

  void _onMessage(String raw) {
    Json m;
    try {
      m = jsonDecode(raw) as Json;
    } catch (_) {
      badMessages++;
      if (badMessages <= 3) consoleLog.add('MENSAJE NO JSON: ${raw.length > 120 ? raw.substring(0, 120) : raw}');
      return;
    }
    final ev = '${m['event']}';
    counts[ev] = (counts[ev] ?? 0) + 1;
    if (ev == 'error' && jsErrors.length < 50) jsErrors.add('${m['message']}');
    handlers[ev]?.call(m);
    _seen[ev] = m;
    final ws = _waiters.remove(ev);
    if (ws != null) {
      for (final w in ws) {
        if (!w.isCompleted) w.complete(m);
      }
    }
  }

  void clearSeen(String ev) => _seen.remove(ev);

  Future<Json> waitEvent(String ev, {Duration timeout = const Duration(seconds: 20)}) {
    final s = _seen[ev];
    if (s != null) return Future.value(s);
    final w = Completer<Json>();
    (_waiters[ev] ??= []).add(w);
    return w.future.timeout(timeout);
  }

  Future<dynamic> evalJson(String js) async {
    var s = await web.eval(js).timeout(const Duration(seconds: 8));
    if (s.startsWith('"') && s.endsWith('"')) s = jsonDecode(s) as String;
    return jsonDecode(s);
  }

  int get ms => clock.elapsedMilliseconds;

  void fail(String why) {
    report['ok'] = false;
    report['failure'] = why;
  }

  /// Escribe snapshot interno (si se pidio), cierra el informe y lo guarda. Idempotente.
  Future<void> finish() => _finishing ??= _finish();

  Future<void> _finish() async {
    final snap = args.get('--snapshot');
    if (snap != null && st.showWeb) {
      try {
        report['internalSnapshot'] = await _snapshotInternal(snap);
      } catch (e) {
        report['internalSnapshot'] = {'error': '$e'};
      }
    }
    report['consoleLog'] = consoleLog;
    report['jsErrors'] = jsErrors;
    report['webErrors'] = webErrors;
    report['badMessages'] = badMessages;
    report['eventCounts'] = counts;
    report['elapsedMs'] = ms;
    report.putIfAbsent('ok', () => true);
    final path = args.get('--report');
    if (path != null) {
      await File(path).parent.create(recursive: true);
      await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    }
    st.status = 'hecho';
    st.changed();
  }

  /// RepaintBoundary.toImage: en macOS no incluye la vista de plataforma; se mide cuantos pixeles no son del fondo de Flutter.
  Future<Json> _snapshotInternal(String path) async {
    final ro = st.boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (ro == null) return {'error': 'sin RepaintBoundary'};
    final img = await ro.toImage(pixelRatio: 1.0);
    final png = await img.toByteData(format: dart_ui.ImageByteFormat.png);
    final raw = await img.toByteData(format: dart_ui.ImageByteFormat.rawRgba);
    await File(path).parent.create(recursive: true);
    await File(path).writeAsBytes(png!.buffer.asUint8List());
    final px = raw!.buffer.asUint8List();
    final bg = screenBackground;
    var nonBg = 0, total = 0;
    for (var y = topBarHeight.toInt() + 2; y < img.height; y += 2) {
      for (var x = 0; x < img.width; x += 2) {
        final i = (y * img.width + x) * 4;
        total++;
        final r = px[i], g = px[i + 1], b = px[i + 2];
        final isBg = (r - bg.r * 255).abs() < 3 && (g - bg.g * 255).abs() < 3 && (b - bg.b * 255).abs() < 3;
        final isOverlay = r > 150 && g < 160 && b < 100;
        if (!isBg && !isOverlay) nonBg++;
      }
    }
    return {
      'path': path,
      'size': '${img.width}x${img.height}',
      'sampledPixels': total,
      'nonBackgroundPixels': nonBg,
      'webContentCaptured': nonBg > total * 0.05,
    };
  }
}

Json stats(List<double> v) {
  if (v.isEmpty) return {'n': 0};
  final s = [...v]..sort();
  double q(double p) => s[((s.length - 1) * p).round()];
  return {
    'n': s.length,
    'median': q(0.5),
    'p95': q(0.95),
    'p99': q(0.99),
    'max': s.last,
    'min': s.first,
    'mean': s.reduce((a, b) => a + b) / s.length,
  };
}
