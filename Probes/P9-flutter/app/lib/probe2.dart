import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ffi/tf_core.dart';
import 'probe2_measure.dart';
import 'probe2_util.dart';

String? _opt(List<String> a, String n) {
  final i = a.indexOf(n);
  return (i >= 0 && i + 1 < a.length) ? a[i + 1] : null;
}

int _rssMb() => ProcessInfo.currentRss ~/ (1024 * 1024);

/// Prueba 2 de P9: FFI e hilos. Escribe `--report` y sale sola.
Future<void> runProbe2(List<String> args, Watchdog wd, FrameStats fs) async {
  final report = <String, Object?>{
    'probe': _opt(args, '--probe'),
    'sink': _opt(args, '--sink'),
    'startedAt': DateTime.now().toIso8601String(),
    'dart': Platform.version.split(' ').first,
  };
  try {
    await _run(args, report, wd, fs);
  } catch (e, st) {
    report['exception'] = '$e\n$st';
  }
  wd.stop();
  report['frames_total'] = fs.toJson();
  final path = _opt(args, '--report');
  if (path != null) {
    await File(path).writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
    );
  }
  exit(0);
}

Future<void> _run(
  List<String> args,
  Map<String, Object?> report,
  Watchdog wd,
  FrameStats fs,
) async {
  final study = _opt(args, '--probe') == 'ffi-study';
  final sink = _opt(args, '--sink') ?? 'listener';

  // a. Hilo
  final main = pthreadMainNp();
  report['a_pthread_main_np'] = main;
  report['a_uiIsolateOnMainThread'] = main == 1;

  final core = TfCore.open(_opt(args, '--core-lib')!, sink);
  final rc = core.start(jsonEncode({
    'args': [
      '--projects-folder', _opt(args, '--projects-folder')!,
      '--support-dir', _opt(args, '--support-dir')!,
      '--audio', 'simulated',
    ],
  }));
  report['startRc'] = rc;
  if (rc != 0) return;

  // b. Humo
  final smoke = <String, Object?>{};
  Object? libraryList;
  for (final m in methods4) {
    try {
      final r = await core.call(m);
      if (m == 'library.list') libraryList = r;
      smoke[m] = 'ok';
    } catch (e) {
      smoke[m] = 'error: $e';
    }
  }
  report['b_smoke'] = smoke;

  if (study) {
    await _study(core, report, wd, libraryList);
    return;
  }

  // c + d. 1000 rondas x2
  final rss = <String, Object?>{'before': _rssMb()};
  final live = <String, Object?>{'afterSmoke': core.liveBuffers()};
  report['startupFrames'] = fs.toJson(); // incluye primer fotograma (arranque en frío)
  wd.reset();
  fs.reset();
  final (a, errA) = await rounds(core, 1000);
  rss['after4000'] = _rssMb();
  live['after4000'] = core.liveBuffers();
  final (b, errB) = await rounds(core, 1000);
  rss['after8000'] = _rssMb();
  live['after8000'] = core.liveBuffers();
  final wdMax = wd.maxDelayMs;
  await Future<void>.delayed(const Duration(seconds: 1));
  live['plus1s'] = core.liveBuffers();
  report['c_roundtrip'] = {
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
    return;
  }

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
  report['g_background'] = await _import(core, _opt(args, '--wav')!);
  report['liveBuffersEnd'] = core.liveBuffers();

  // h. Cierre
  report['h_shutdown'] = await _shutdown(core, wd);
}

Future<Map<String, Object?>> _import(TfCore core, String wav) async {
  final seq = <String>[];
  var progress = 0, changed = 0;
  String? lastJob;
  final errors = <String>[];
  final sw = Stopwatch()..start();
  final done = Completer<void>();
  final sub = core.events.listen((ev) {
    if (ev.name == 'library.changed') {
      changed++;
    } else if (ev.name == 'jobs.progress' && ev.payload is Map) {
      final p = ev.payload as Map;
      progress++;
      lastJob = '${p['id']}';
      final s = '${p['stage']}:${p['state']}';
      if (seq.isEmpty || !seq.last.startsWith('$s@')) {
        seq.add('$s@${sw.elapsedMilliseconds}ms');
      }
      if (p['error'] != null) errors.add('${p['stage']}: ${p['error']}');
      final st = p['state'];
      if (p['stage'] != 'import' &&
          (st == 'failed' || st == 'done' || st == 'cancelled')) {
        if (!done.isCompleted) done.complete();
      }
    }
  });
  Object? importResult;
  String? importError;
  try {
    importResult = await core.call('import.file', {'path': wav});
  } catch (e) {
    importError = '$e';
  }
  var timedOut = false;
  String? cancelled;
  if (importError == null) {
    await done.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => timedOut = true,
    );
    if (timedOut && lastJob != null) {
      try {
        await core.call('jobs.cancel', {'id': lastJob});
        cancelled = 'jobs.cancel($lastJob) enviado';
      } catch (e) {
        cancelled = 'jobs.cancel error: $e';
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  await sub.cancel();
  return {
    'importResult': importResult,
    'importError': importError,
    'sequence': seq,
    'jobsProgressEvents': progress,
    'libraryChangedEvents': changed,
    'errors': errors,
    'timedOut30s': timedOut,
    'cancel': cancelled,
    'isolateAlive': true,
    'decodeErrors': core.decodeErrors,
  };
}

Future<Map<String, Object?>> _shutdown(TfCore core, Watchdog wd) async {
  final c = Completer<Object?>();
  final sub = core.events.listen((e) {
    if (e.name == 'core.shutdown' && !c.isCompleted) c.complete(e.payload);
  });
  wd.reset();
  final sw = Stopwatch()..start();
  core.shutdown(5000);
  final payload = await c.future.timeout(
    const Duration(seconds: 10),
    onTimeout: () => 'timeout 10s sin core.shutdown',
  );
  final ms = sw.elapsedMilliseconds;
  await sub.cancel();
  return {
    'ms': ms,
    'payload': payload,
    'watchdogMaxDelayMs': round3(wd.maxDelayMs),
  };
}

Future<void> _study(
  TfCore core,
  Map<String, Object?> report,
  Watchdog wd,
  Object? list,
) async {
  Object? first;
  if (list is List && list.isNotEmpty) {
    first = list.first;
  } else if (list is Map) {
    for (final v in list.values) {
      if (v is List && v.isNotEmpty) {
        first = v.first;
        break;
      }
    }
  }
  final id = first is Map ? first['id'] : first;
  report['study_projectId'] = id;
  report['study_listShape'] = list.runtimeType.toString();
  if (id == null) return;
  try {
    report['study_open'] = await core.call('study.open', {'projectId': id});
  } catch (e) {
    report['study_open'] = 'error: $e';
  }
  await Future<void>.delayed(const Duration(seconds: 1));
  report['h_shutdown'] = await _shutdown(core, wd);
}
