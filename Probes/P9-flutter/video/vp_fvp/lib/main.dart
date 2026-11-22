// P9.5a prueba 5: vídeo de tomas con fvp (mdk) y reloj externo onSync.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:fvp/mdk.dart';
import 'cases.dart';
import 'rig.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  String? opt(String k) {
    final i = args.indexOf(k);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final kase = opt('--case') ?? 'steady';
  final file = opt('--file') ?? '';
  final report = opt('--report') ?? '/tmp/vp_fvp.json';
  final exitAfter = double.tryParse(opt('--exit-after') ?? '') ?? 120;
  final regimeS = double.tryParse(opt('--regime-s') ?? '') ?? 10;
  final rig = Rig();
  rig.strip = kase == 'steady' || kase == 'seek' || kase == 'loop';
  final mdkLog = <String>[];
  setLogHandler((l, m) {
    if (mdkLog.length < 40 && RegExp(r'decoder|VideoToolbox|VT|hardware|codec', caseSensitive: false).hasMatch(m)) mdkLog.add(m.trim());
  });
  final result = <String, Object?>{'case': kase, 'file': file, 'fvp': '0.40.0', 'startedAt': DateTime.now().toIso8601String()};
  var done = false;
  Future<void> finish(int code) async {
    if (done) return;
    done = true;
    result['mdkLog'] = mdkLog;
    result['syncStats'] = rig.clock.syncStats();
    result['rssMbEnd'] = ProcessInfo.currentRss / 1048576;
    await File(report).writeAsString(const JsonEncoder.withIndent(' ').convert(result));
    exit(code);
  }

  Timer(Duration(milliseconds: (exitAfter * 1000).round()), () {
    result['error'] = 'exit-after';
    finish(2);
  });
  runApp(Directionality(
    textDirection: TextDirection.ltr,
    child: ColoredBox(color: const Color(0xFF202020), child: rig.view(showStrip: rig.strip)),
  ));
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      result['open'] = await rig.open(file);
      await wait(0.5);
      switch (kase) {
        case 'steady':
          result['result'] = await steady(rig, regimeS);
        case 'cpu':
          result['result'] = await cpu(rig, regimeS);
        case 'seek':
          result['result'] = await seekCase(rig);
        case 'loop':
          result['result'] = await loopCase(rig);
        case 'rotation':
          result['result'] = await rotation(rig, 6);
        case 'start-pts':
          result['result'] = await startPts(rig);
        default:
          result['error'] = 'caso desconocido';
      }
      await finish(0);
    } catch (e, st) {
      result['error'] = '$e';
      result['stack'] = '$st'.split('\n').take(8).toList();
      await finish(1);
    }
  });
}
