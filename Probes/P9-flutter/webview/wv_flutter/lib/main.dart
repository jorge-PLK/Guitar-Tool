// P9.4: prueba 4 (WebView en el Mac). Uso: --case tab|messages|keys|overlay|resize|songsterr|occluded
//   --report <json> [--snapshot <png>] --exit-after <s> [--occluded-delay <s>]
import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'case_keys.dart';
import 'case_msgs.dart';
import 'case_songsterr.dart';
import 'case_tab.dart';
import 'ctx.dart';
import 'probe_webview.dart';
import 'screen.dart';

Future<void> main(List<String> argv) async {
  WidgetsFlutterBinding.ensureInitialized();
  final c = Ctx(Args(argv));  runApp(ProbeApp(c));
  final exitAfter = c.args.intOr('--exit-after', 60);
  Timer(Duration(seconds: exitAfter), () async {
    c.report.putIfAbsent('timedOut', () => true);
    await c.finish();
    exit(0);
  });
  unawaited(_run(c));
}

Future<void> _run(Ctx c) async {
  final name = c.args.get('--case') ?? 'tab';
  c.report['candidate'] = ProbeWebView.candidate;
  c.report['case'] = name;
  c.report['platform'] = Platform.operatingSystemVersion;
  c.report['argv'] = c.args.list;
  try {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    switch (name) {
      case 'tab':
        await runTab(c);
      case 'messages':
        await runMessages(c);
      case 'keys':
        await runKeys(c);
      case 'overlay':
        await runOverlay(c);
      case 'resize':
        await runResize(c);
      case 'songsterr':
        await runSongsterr(c);
      case 'occluded':
        await runOccluded(c);
      default:
        c.fail('caso desconocido: $name');
    }
  } catch (e, s) {
    c.fail('excepcion: $e');
    c.report['stack'] = '$s'.split('\n').take(8).toList();
  }
  c.report['timedOut'] = false;
  await c.finish();
}
