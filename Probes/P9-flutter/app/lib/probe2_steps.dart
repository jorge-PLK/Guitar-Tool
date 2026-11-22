import 'dart:async';

import 'ffi/tf_core.dart';
import 'probe2_util.dart';

Future<Map<String, Object?>> importWav(TfCore core, String wav) async {
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

Future<Map<String, Object?>> shutdownCore(TfCore core, Watchdog wd) async {
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

Future<void> studyRun(
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
  report['h_shutdown'] = await shutdownCore(core, wd);
}
