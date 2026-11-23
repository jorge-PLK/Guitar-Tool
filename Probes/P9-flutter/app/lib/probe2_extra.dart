import 'dart:async';
import 'dart:io';

import 'ffi/tf_core.dart';
import 'probe2_measure.dart';
import 'probe2_util.dart';

/// P9 7g · medida 2: RSS largo. `--probe ffi-soak --soak-seconds N` y/o `--calls N` (para al primero que se cumpla).
/// Muestrea RSS (MB, 2 decimales) y búferes vivos cada [soakSampleSeconds] s en el isolate de UI.
const soakSampleSeconds = 10;

Future<void> soakRun(
  TfCore core,
  Map<String, Object?> report,
  Watchdog wd,
  List<String> methods,
  int soakSeconds,
  int maxCalls,
) async {
  final samples = <Map<String, Object?>>[];
  final sw = Stopwatch()..start();
  var calls = 0, errors = 0;
  double maxMs = 0;
  var next = 0;
  void sample() {
    samples.add({
      'tS': (sw.elapsedMilliseconds / 1000).round(),
      'rssMb': round3(ProcessInfo.currentRss / (1024 * 1024)),
      'live': core.liveBuffers(),
      'calls': calls,
    });
  }

  wd.setPhase('soak');
  sample();
  next = soakSampleSeconds;
  while ((soakSeconds <= 0 || sw.elapsedMilliseconds < soakSeconds * 1000) &&
      (maxCalls <= 0 || calls < maxCalls)) {
    final (ms, err) = await rounds(core, 50, methods);
    calls += ms.length;
    errors += err;
    for (final x in ms) {
      if (x > maxMs) maxMs = x;
    }
    if (sw.elapsedMilliseconds >= next * 1000) {
      sample();
      next += soakSampleSeconds;
    }
  }
  sample();
  report['soak'] = {
    'seconds': round3(sw.elapsedMilliseconds / 1000),
    'calls': calls,
    'errors': errors,
    'maxRoundtripMs': round3(maxMs),
    'sampleEveryS': soakSampleSeconds,
    'samples': samples,
  };
}

/// P9 7g · medida 3: apartamento COM del hilo de UI (el del motor, vía 1) antes/después de MFStartup y de
/// crear algo real de MF (MFCreateAttributes + MFEnumDeviceSources; sin abrir dispositivos).
/// `tf_debug_mf_step`: 1 MFStartup, 2 MFCreateAttributes+MFEnumDeviceSources (n >= 0 o HRESULT < 0), 3 MFShutdown.
/// Umbral: el apartamento sigue igual (STA = 0/3 según el hilo) y audio.devices responde.
Future<void> mfRun(
  TfCore core,
  Map<String, Object?> report,
  List<String> failed,
) async {
  final m = <String, Object?>{};
  m['apartment0'] = core.apartment();
  m['isMainThread'] = core.isMainThread();
  m['startupRc'] = core.mfStep(1);
  m['apartmentAfterMFStartup'] = core.apartment();
  m['enumDevices'] = core.mfStep(2);
  m['apartmentAfterEnum'] = core.apartment();
  Object? dev;
  try {
    dev = await core.call('audio.devices').timeout(const Duration(seconds: 5));
    m['audioDevices'] = 'ok';
  } catch (e) {
    m['audioDevices'] = 'fallo: $e';
    dev = null;
  }
  final ma = Completer<Object?>();
  final sub = core.events.listen((e) {
    if (e.name == 'probe.mainactor' && !ma.isCompleted) ma.complete(e.payload);
  });
  final rc = core.mainActorSelftest(3000);
  m['mainActorSelftestRc'] = rc;
  if (rc == 0) {
    m['mainActor'] = await ma.future.timeout(const Duration(seconds: 5),
        onTimeout: () => <String, Object?>{'timeout': true});
  }
  await sub.cancel();
  m['shutdownRc'] = core.mfStep(3);
  m['apartmentAfterMFShutdown'] = core.apartment();
  m['audioDevicesAfterShutdown'] = await core
      .call('audio.devices')
      .timeout(const Duration(seconds: 5))
      .then((_) => 'ok', onError: (Object e) => 'fallo: $e');
  report['mf'] = m;
  final a0 = m['apartment0'];
  final ok = m['apartmentAfterMFStartup'] == a0 &&
      m['apartmentAfterEnum'] == a0 &&
      m['apartmentAfterMFShutdown'] == a0 &&
      (m['startupRc'] as int) >= 0 &&
      (m['enumDevices'] as int) >= 0 &&
      m['audioDevices'] == 'ok' &&
      m['audioDevicesAfterShutdown'] == 'ok' &&
      dev != null &&
      m['mainActor'] is Map &&
      (m['mainActor'] as Map)['mainActor'] == true;
  if (!ok) failed.add('mf');
}
