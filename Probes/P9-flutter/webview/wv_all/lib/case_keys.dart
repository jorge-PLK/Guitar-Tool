// P9.4: caso keys con variantes (--keys-mode raw|prevent|handled|flutter) y deteccion de tormenta de teclas.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'case_tab.dart';
import 'ctx.dart';

String _label(KeyEvent e) => e.logicalKey.keyLabel.isEmpty ? (e.logicalKey.debugName ?? '?') : e.logicalKey.keyLabel;

/// Contadores sin tope de un lado (JS o Flutter) y detector de tormenta.
/// Tormenta: mas de 5 down (sin repeat) de una tecla en 200 ms, o 16 down de cualquier tipo en 200 ms.
class _Side {
  int total = 0;
  bool storm = false;
  final downs = <String, int>{};
  final _fresh = <String, List<int>>{};
  final _any = <String, List<int>>{};

  void add(String type, String key, bool repeat, int t) {
    total++;
    if (type != 'down') return;
    downs[key] = (downs[key] ?? 0) + 1;
    _hit(_any[key] ??= [], 16, t);
    if (!repeat) _hit(_fresh[key] ??= [], 6, t);
  }

  void _hit(List<int> l, int n, int t) {
    l.add(t);
    if (l.length > n) l.removeAt(0);
    if (l.length == n && t - l.first <= 200) storm = true;
  }

  int get maxDowns => downs.values.fold(0, (a, b) => a > b ? a : b);
}

Future<void> runKeys(Ctx c) async {
  if (!await loadPage(c, 'probe.html')) return;
  final mode = c.args.get('--keys-mode') ?? 'raw';
  final reclaim = c.args.get('--reclaim') ?? 'focusNode';
  final flutterSeq = <Json>[];
  final jsSeq = <Json>[];
  final js = _Side(), fl = _Side();
  var wantWeb = false;
  var mouseDowns = 0;
  var reclaimCalls = 0;
  final reclaimResults = <String>[];
  const channel = MethodChannel('tf/focus');
  int now() => DateTime.now().millisecondsSinceEpoch;
  c.report['keysMode'] = mode;
  if (mode == 'flutter') c.report['focusReclaim'] = reclaim;

  bool handler(KeyEvent e) {
    final type = e is KeyDownEvent ? 'down' : (e is KeyUpEvent ? 'up' : 'repeat');
    fl.add(type, _label(e), false, now());
    if (flutterSeq.length < 5000) {
      flutterSeq.add({
        'type': type,
        'key': _label(e),
        'physical': e.physicalKey.debugName,
        'ts': now(),
        'primaryFocus': FocusManager.instance.primaryFocus?.debugLabel ?? 'none',
      });
    }
    return mode == 'handled' && wantWeb;
  }

  HardwareKeyboard.instance.addHandler(handler);
  c.handlers['key'] = (m) {
    final type = m['type'] == 'keydown' ? 'down' : (m['type'] == 'keyup' ? 'up' : '${m['type']}');
    js.add(type, '${m['key']}', m['repeat'] == true, now());
    if (jsSeq.length < 5000) jsSeq.add({...m, 'dartTs': now()});
  };
  c.handlers['mousedown'] = (m) {
    mouseDowns++;
    if (mode != 'flutter') return;
    c.st.keyNode.requestFocus();
    if (reclaim == 'makeFirstResponder') {
      reclaimCalls++;
      channel.invokeMethod<bool>('reclaim').then((r) {
        c.report.putIfAbsent('reclaimSupported', () => true);
        if (reclaimResults.length < 20) reclaimResults.add('$r');
      }, onError: (Object e) {
        if (e is MissingPluginException) c.report['reclaimSupported'] = false;
        if (reclaimResults.length < 20) reclaimResults.add('error: $e');
      });
    }
  };
  c.st.keys = true;
  c.st.onKey = (e) {
    final h = HardwareKeyboard.instance;
    final o = {
      'type': e is KeyDownEvent ? 'keydown' : (e is KeyUpEvent ? 'keyup' : 'keydown'),
      'key': e.character ?? _label(e),
      'code': e.physicalKey.debugName,
      'meta': h.isMetaPressed,
      'ctrl': h.isControlPressed,
      'shift': h.isShiftPressed,
      'alt': h.isAltPressed,
      'repeat': e is KeyRepeatEvent,
    };
    unawaited(c.web.run('__key(${jsonEncode(o)})'));
    return KeyEventResult.handled;
  };
  c.st.onFocusAction = (action) {
    flutterSeq.add({'type': 'focusAction', 'action': action, 'ts': now()});
    wantWeb = action == 'webview';
    if (!wantWeb) {
      c.st.focusNode.requestFocus();
    } else if (mode == 'flutter') {
      c.st.focusNode.unfocus();
      c.st.keyNode.requestFocus();
    } else {
      c.st.focusNode.unfocus();
      unawaited(c.web.run("window.focus();document.body.tabIndex=0;document.body.focus();__post({event:'focusAction',action:'webview',ts:Date.now()})"));
    }
  };
  c.handlers['focusAction'] = (m) => jsSeq.add({...m, 'type': 'focusAction'});
  if (mode == 'prevent') await c.web.run('window.__preventKeys = true');
  final ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
    c.st.status = 'keys:$mode JS=${js.total} Flutter=${fl.total}${(js.storm || fl.storm) ? '  TORMENTA' : ''}';
    c.st.changed();
  });
  final total = c.args.intOr('--exit-after', 60);
  await Future<void>.delayed(Duration(seconds: total > 8 ? total - 4 : 4));
  ticker.cancel();
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
      final j = t['${e[keyField]}'] ??= {'down': 0, 'up': 0, 'repeat': 0};
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
  c.report['jsKeyTotal'] = js.total;
  c.report['flutterKeyTotal'] = fl.total;
  c.report['maxDownsPerKey'] = {'js': js.maxDowns, 'flutter': fl.maxDowns};
  c.report['storm'] = js.storm || fl.storm;
  c.report['stormSide'] = {'js': js.storm, 'flutter': fl.storm};
  c.report['mouseDowns'] = mouseDowns;
  if (mode == 'flutter') {
    c.report['reclaimCalls'] = reclaimCalls;
    c.report['reclaimResults'] = reclaimResults;
  }
  c.report['fieldText'] = c.st.fieldController.text;
}
