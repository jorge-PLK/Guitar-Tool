import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ffi/tf_core.dart';
import 'probe2_measure.dart';
import 'probe2_steps.dart';
import 'probe2_util.dart';

String? _opt(List<String> a, String n) {
  final i = a.indexOf(n);
  return (i >= 0 && i + 1 < a.length) ? a[i + 1] : null;
}

int _rssMb() => ProcessInfo.currentRss ~/ (1024 * 1024);

const _enc = JsonEncoder.withIndent('  ');

/// Prueba 2 de P9: FFI e hilos. Escribe `--report` y sale sola.
/// Salida: 0 todo pasa, 1 algún umbral falla, 3 abortada por el tope de 180 s.
Future<void> runProbe2(List<String> args, Watchdog wd, FrameStats fs) async {
  final report = <String, Object?>{
    'probe': _opt(args, '--probe'),
    'sink': _opt(args, '--sink'),
    'startedAt': DateTime.now().toIso8601String(),
    'dart': Platform.version.split(' ').first,
    'threads': <String, Object?>{'requested': _opt(args, '--threads')},
    'failed': <String>[],
  };
  final path = _opt(args, '--report');
  // Tope global: informe parcial y salida 3. Timer en el isolate de UI.
  Timer(const Duration(seconds: 180), () {
    report['aborted'] = true;
    _finalize(report, wd, fs);
    if (path != null) File(path).writeAsStringSync(_enc.convert(report));
    exit(3);
  });
  try {
    await _run(args, report, wd, fs);
  } catch (e, st) {
    report['exception'] = '$e\n$st';
    (report['failed'] as List<String>).add('exception');
  }
  _finalize(report, wd, fs);
  if (path != null) await File(path).writeAsString(_enc.convert(report));
  exit((report['failed'] as List).isEmpty ? 0 : 1);
}

void _finalize(Map<String, Object?> report, Watchdog wd, FrameStats fs) {
  wd.stop();
  report['frames_total'] = fs.toJson();
  final failed = report['failed'] as List<String>;
  final th = report['threads'] as Map<String, Object?>;
  if (th['threadsOk'] != true) failed.add('threadsOk');
  final sd = report['h_shutdown'];
  final clean = sd is Map && sd['payload'] is Map && (sd['payload'] as Map)['clean'] == true;
  if (!clean) failed.add('clean');
  if (report['aborted'] == true) failed.add('aborted');
}

Future<void> _run(
  List<String> args,
  Map<String, Object?> report,
  Watchdog wd,
  FrameStats fs,
) async {
  final study = _opt(args, '--probe') == 'ffi-study';
  final sink = _opt(args, '--sink') ?? 'listener';
  final failed = report['failed'] as List<String>;
  final th = report['threads'] as Map<String, Object?>;

  // a. Hilo y apartamento
  final core = TfCore.open(_opt(args, '--core-lib')!, sink);
  final main = core.isMainThread();
  th['isMainThread'] = main;
  report['a_pthread_main_np'] = main; // nombre histórico
  report['a_uiIsolateOnMainThread'] = main == 1;
  th['apartmentBefore'] = core.apartment();

  // El selftest emite probe.mainactor: escuchar antes de lanzarlo.
  final mainActor = Completer<Object?>();
  final subMa = core.events.listen((e) {
    if (e.name == 'probe.mainactor' && !mainActor.isCompleted) {
      mainActor.complete(e.payload);
    }
  });
  final rc = core.start(jsonEncode({
    'args': [
      '--projects-folder', _opt(args, '--projects-folder')!,
      '--support-dir', _opt(args, '--support-dir')!,
      '--audio', 'simulated',
    ],
  }));
  report['startRc'] = rc;
  th['apartmentAfterStart'] = core.apartment();
  if (rc != 0) {
    failed.add('startRc=$rc');
    return;
  }

  // a2. MainActor / dispatchMain antes del humo
  var threadsOk = true;
  final strc = core.mainActorSelftest(3000);
  if (strc != 0) {
    th['mainActor'] = {'selftestRc': strc};
    threadsOk = false;
  } else {
    final ma = await mainActor.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => <String, Object?>{'timeout': true},
    );
    th['mainActor'] = ma;
    threadsOk = ma is Map && ma['mainActor'] == true && ma['dispatchMain'] == true;
  }
  await subMa.cancel();

  // b. Humo (cada método con tope de 5 s)
  final smoke = <String, Object?>{};
  Object? libraryList;
  var methods = methods4;
  for (final m in methods4) {
    try {
      final r = await core.call(m).timeout(const Duration(seconds: 5));
      if (m == 'library.list') libraryList = r;
      smoke[m] = 'ok';
    } on TimeoutException {
      smoke[m] = 'timeout';
      if (m == 'audio.devices') {
        th['audioDevices'] = 'timeout';
        threadsOk = false;
        methods = methods4.where((x) => x != m).toList();
      }
    } catch (e) {
      smoke[m] = 'error: $e';
    }
  }
  if (!th.containsKey('audioDevices')) th['audioDevices'] = smoke['audio.devices'];
  report['b_smoke'] = smoke;
  th['threadsOk'] = threadsOk;

  if (study) {
    await studyRun(core, report, wd, libraryList);
    return;
  }

  // c + d. 1000 rondas x2
  final rss = <String, Object?>{'before': _rssMb()};
  final live = <String, Object?>{'afterSmoke': core.liveBuffers()};
  report['startupFrames'] = fs.toJson(); // incluye primer fotograma (arranque en frío)
  wd.reset();
  fs.reset();
  final (a, errA) = await rounds(core, 1000, methods);
  rss['after4000'] = _rssMb();
  live['after4000'] = core.liveBuffers();
  final (b, errB) = await rounds(core, 1000, methods);
  rss['after8000'] = _rssMb();
  live['after8000'] = core.liveBuffers();
  final wdMax = wd.maxDelayMs;
  await Future<void>.delayed(const Duration(seconds: 1));
  live['plus1s'] = core.liveBuffers();
  report['c_roundtrip'] = {
    'methods': methods,
    'first4000_ms': stats(a),
    'second4000_ms': stats(b),
    'errors': errA + errB,
    'rssMb': rss,
    'liveBuffers': live,
  };
  report['d_uiBlock'] = {
    'watchdogMaxDelayMs': round3(wdMax),
    'watchdogTicks': wd.ticks,
    'frames': fs.toJson(),
  };
  final med = (stats(a)['median'] as double);
  final p99 = (stats(a)['p99'] as double);
  final growth = (rss['after8000'] as int) - (rss['after4000'] as int);
  final fails = <String>[
    if (errA + errB > 0) 'errores=${errA + errB}',
    if (med >= 5) 'mediana=$med>=5ms',
    if (p99 >= 16) 'p99=$p99>=16ms',
    if (wdMax > 16) 'watchdog=$wdMax>16ms',
    if (growth > 8) 'RSS crece $growth MB entre 4000 y 8000',
  ];
  if (fails.isNotEmpty) {
    report['STOPPED_threshold'] = fails;
    failed.addAll(fails);
  } else {
    // e. Nativo -> Dart
    final e = <String, Object?>{};
    wd.reset();
    fs.reset();
    e['free_60hz'] = await emitRun(core, 60, 600, 300);
    final busy = BusyLoad()..start();
    e['busy_60hz'] = await emitRun(core, 60, 600, 300);
    busy.stop();
    e['burst_5000'] = await emitRun(core, 0, 5000, 300);
    e['watchdogMaxDelayMs'] = round3(wd.maxDelayMs);
    e['decodeErrors'] = core.decodeErrors;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    e['frames'] = fs.toJson();
    report['e_nativeToDart'] = e;

    // f. Decodificación
    report['f_decode'] = decodeBench();

    // g. Eventos de fondo reales
    report['g_background'] = await importWav(core, _opt(args, '--wav')!);
    report['liveBuffersEnd'] = core.liveBuffers();
  }

  // El hilo de UI debe seguir en el mismo apartamento tras usar COM/MF.
  final after = core.apartment();
  th['apartmentAfterCalls'] = after;
  if (after != th['apartmentBefore']) {
    th['threadsOk'] = false;
    th['why'] = 'apartmentAfterCalls != apartmentBefore';
  }

  // h. Cierre
  report['h_shutdown'] = await shutdownCore(core, wd);
}
