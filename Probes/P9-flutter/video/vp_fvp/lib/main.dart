// P9.5a prueba 5: vídeo de tomas con fvp (mdk) y reloj externo onSync. macOS y Windows x64.
// Argumentos: --case <steady|cpu|seek|loop|rotation|start-pts> --video|--file <ruta absoluta>
//   --report <ruta.json> --exit-after <s> --regime-s <s> --decoders <lista separada por comas>
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:fvp/mdk.dart';
import 'cases.dart';
import 'clock.dart';
import 'rig.dart';
import 'stats.dart';

void main(List<String> args) {
  runZonedGuarded(() => _run(args), (e, st) => _fail?.call('$e', '$st'));
}

void Function(String, String)? _fail;

Future<void> _run(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  String? opt(String k) {
    final i = args.indexOf(k);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final kase = opt('--case') ?? 'steady';
  final file = opt('--video') ?? opt('--file') ?? '';
  final report = opt('--report') ?? '${Directory.systemTemp.path}${Platform.pathSeparator}vp_fvp.json';
  final exitAfter = double.tryParse(opt('--exit-after') ?? '') ?? 120;
  final regimeS = double.tryParse(opt('--regime-s') ?? '') ?? 10;
  final rig = Rig()..decodersArg = opt('--decoders');
  rig.strip = kase == 'steady' || kase == 'seek' || kase == 'loop';
  final mdkLog = <String>[];
  setLogHandler((l, m) {
    if (mdkLog.length < 60 && RegExp(r'decoder|VideoToolbox|VT|hardware|codec|MFT|D3D11|DXVA|CUDA|d3d', caseSensitive: false).hasMatch(m)) mdkLog.add(m.trim().split('\n').first.substring(0, m.trim().split('\n').first.length.clamp(0, 200)));
  });
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final result = <String, Object?>{
    'case': kase,
    'file': file,
    'fvp': '0.40.0',
    'platform': '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    'devicePixelRatio': view.devicePixelRatio,
    'physicalSize': [view.physicalSize.width, view.physicalSize.height],
    'args': args,
    'startedAt': DateTime.now().toIso8601String(),
  };
  final dog = Watchdog()..start();
  final sw = Stopwatch()..start();
  final cpu0 = _safe(cpuS) ?? 0;
  var done = false;
  Future<void> finish(int code) async {
    if (done) return;
    done = true;
    dog.stop();
    result['wallS'] = sw.elapsedMilliseconds / 1000;
    result['cpuProcessS'] = (_safe(cpuS) ?? 0) - cpu0;
    result['watchdog'] = dog.toJson();
    result['watchdogMaxMs'] = dog.toJson()['maxMs'];
    result['mdkLog'] = mdkLog;
    result['decoderEventsEnd'] = rig.decoderEvents;
    result['activeDecoder'] = rig.activeDecoder;
    result['syncStats'] = _safe(rig.clock.syncStats);
    result['rssMbEnd'] = ProcessInfo.currentRss / 1048576;
    result['exitCode'] = code;
    try {
      await File(report).writeAsString(const JsonEncoder.withIndent(' ').convert(clean(result)));
    } catch (e) {
      stderr.writeln('no se pudo escribir $report: $e');
    }
    exit(code);
  }

  _fail = (e, st) {
    result['error'] = e;
    result['stack'] = st.split('\n').take(8).toList();
    finish(1);
  };
  FlutterError.onError = (d) => _fail!(d.exceptionAsString(), '${d.stack}');
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
      await finish(result['error'] == null ? 0 : 1);
    } catch (e, st) {
      _fail!('$e', '$st');
    }
  });
}

T? _safe<T>(T Function() f) {
  try {
    return f();
  } catch (_) {
    return null;
  }
}
