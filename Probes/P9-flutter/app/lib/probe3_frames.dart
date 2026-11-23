import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'ffi/tf_core.dart';
import 'probe2_steps.dart';
import 'probe2_util.dart';
import 'probe3_measure.dart';

String? _opt(List<String> a, String n) {
  final i = a.indexOf(n);
  return (i >= 0 && i + 1 < a.length) ? a[i + 1] : null;
}

const _enc = JsonEncoder.withIndent('  ');
const _warmup = Duration(seconds: 1);

/// Prueba 3 de P9: fotogramas (textura externa vs BGRA por FFI).
/// Salida: 0 pasa, 1 incumple umbral, 3 error / tope (segundos + 30).
void startProbe3(List<String> args) {
  final size = _opt(args, '--size') == '1080' ? 1080 : 720;
  final surf = Probe3Surface(size == 1080 ? 1920 : 1280, size);
  final wd = Watchdog()..start();
  final ft = FrameTimings()..start();
  runApp(Probe3View(surface: surf));
  WidgetsBinding.instance.addPostFrameCallback((_) => _run(args, surf, wd, ft));
}

Future<void> _run(
    List<String> args, Probe3Surface surf, Watchdog wd, FrameTimings ft) async {
  final seconds = int.tryParse(_opt(args, '--seconds') ?? '') ?? 60;
  final mode = _opt(args, '--mode') == 'bgra' ? 'bgra' : 'texture';
  final failed = <String>[];
  final report = <String, Object?>{
    'probe': 'frames',
    'mode': mode,
    'textureKind': _opt(args, '--texture-kind') ?? 'gpu',
    'platform': Platform.operatingSystem,
    'size': surf.height,
    'width': surf.width,
    'height': surf.height,
    'fps': 30,
    'seconds': seconds,
    'startedAt': DateTime.now().toIso8601String(),
    'dart': Platform.version.split(' ').first,
    'failed': failed,
  };
  final path = _opt(args, '--report');
  void write() {
    if (path != null) File(path).writeAsStringSync(_enc.convert(report));
  }

  Timer(Duration(seconds: seconds + 30), () {
    report['aborted'] = true;
    failed.add('aborted');
    write();
    exit(3);
  });
  try {
    await _measure(args, surf, wd, ft, mode, seconds, report);
  } catch (e, st) {
    report['exception'] = '$e\n$st';
    exit3(report, write);
  }
  write();
  exit(failed.isEmpty ? 0 : 1);
}

Never exit3(Map<String, Object?> report, void Function() write) {
  (report['failed'] as List<String>).add('exception');
  write();
  exit(3);
}

Future<void> _measure(List<String> args, Probe3Surface surf, Watchdog wd,
    FrameTimings ft, String mode, int seconds, Map<String, Object?> report) async {
  final failed = report['failed'] as List<String>;
  final bgra = mode == 'bgra';
  final core = TfCore.open(_opt(args, '--core-lib')!, 'port');
  final rc = core.start(jsonEncode({
    'args': [
      '--projects-folder', _opt(args, '--projects-folder')!,
      '--support-dir', _opt(args, '--support-dir')!,
      '--audio', 'simulated',
    ],
  }));
  report['startRc'] = rc;
  if (rc != 0) {
    failed.add('startRc=$rc');
    return;
  }
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final dpr = view.devicePixelRatio;
  report['window'] = {
    'physicalW': view.physicalSize.width,
    'physicalH': view.physicalSize.height,
    'devicePixelRatio': dpr,
    'logicalW': view.physicalSize.width / dpr,
    'logicalH': view.physicalSize.height / dpr,
  };
  if (!bgra) {
    final id = core.textureCreate(0);
    report['textureId'] = id;
    if (id < 0) {
      failed.add('textureCreate=$id');
      core.shutdown(5000);
      return;
    }
    surf.textureId.value = id;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  // Estado de medida.
  final sw = Stopwatch()..start();
  var inWindow = false;
  var decodedInWindow = 0;
  var decoded = 0, painted = 0, paintedInWindow = 0, skipped = 0, maxGap = 0;
  var lastSeq = 0;
  final copyMs = <double>[], decodeMs = <double>[];
  final rss = <String, double>{};
  List<int> s0 = const [0, 0, 0, 0];
  List<int> x0 = List.filled(20, 0);
  double cpuW0 = 0;
  var wallW0 = 0.0;

  final frc = core.framesStart(0, surf.width, surf.height, 30);
  report['framesStartRc'] = frc;
  if (frc != 0) failed.add('framesStart=$frc');
  final cpu0 = cpuSeconds();
  final wall0 = sw.elapsedMicroseconds;
  final half = seconds ~/ 2;
  Timer(const Duration(seconds: 5), () => rss['5s'] = rssMb());
  Timer(Duration(seconds: half), () => rss['30s'] = rssMb());
  Timer(_warmup, () {
    report['startup'] = {
      'watchdogMaxMs': round3(wd.maxDelayMs),
      'statsAt1s': core.framesStats(0),
      'bgraSkippedFirstSecond': skipped,
    };
    s0 = core.framesStats(0);
    x0 = core.framesExtra(0);
    core.framesReset(0);
    cpuW0 = cpuSeconds();
    wallW0 = sw.elapsedMicroseconds / 1e6;
    wd.reset();
    skipped = 0;
    maxGap = 0;
    ft.active = true;
    inWindow = true;
  });

  // Camino bgra.
  final cap = surf.width * surf.height * 4;
  final buf = bgra ? nativeCalloc(cap) : nullptr.cast<Uint8>();
  final meta = nativeCalloc(32);
  final pw = meta.cast<Int32>(), ph = pw + 1, pseq = (meta + 8).cast<Int64>();
  ui.Image? current;
  Future<bool> pollOnce() async {
    final a = sw.elapsedMicroseconds;
    pseq.value = lastSeq;
    final n = core.frameBgra(0, buf, cap, pw, ph, pseq);
    final b = sw.elapsedMicroseconds;
    if (n < 0) {
      failed.add('bgraCapacity');
      return false;
    }
    if (n == 0) return false;
    final seq = pseq.value, w = pw.value, h = ph.value;
    final gap = lastSeq == 0 ? 0 : seq - lastSeq - 1;
    lastSeq = seq;
    final done = Completer<ui.Image>();
    final px = buf.asTypedList(n);
    ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.bgra8888, done.complete);
    final img = await done.future;
    final c = sw.elapsedMicroseconds;
    decoded++;
    if (inWindow) {
      copyMs.add((b - a) / 1000);
      decodeMs.add((c - b) / 1000);
      decodedInWindow++;
      skipped += gap;
      if (gap + 1 > maxGap) maxGap = gap + 1;
    }
    final old = current;
    current = img;
    surf.image.value = img;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      old?.dispose(); // el anterior ya no está en el árbol
      painted++;
      if (inWindow) paintedInWindow++;
    });
    return true;
  }

  if (bgra) {
    while (sw.elapsedMicroseconds - wall0 < seconds * 1000000 && failed.isEmpty) {
      if (!await pollOnce()) {
        await Future<void>.delayed(const Duration(milliseconds: 3));
      }
    }
  } else {
    await Future<void>.delayed(Duration(seconds: seconds));
  }

  // Cierre de la medida.
  final cpu1 = cpuSeconds();
  final wall1 = sw.elapsedMicroseconds / 1e6;
  rss['60s'] = rssMb();
  final wdMax = wd.maxDelayMs;
  final cost = core.framesCostUs(0);
  core.framesStop(0);
  if (bgra) await pollOnce(); // recoge el último fotograma producido
  await Future<void>.delayed(const Duration(milliseconds: 400));
  final s1 = core.framesStats(0);
  final x1 = core.framesExtra(0);
  // FrameTiming llega por lotes con retraso: espera a que se vacíe el último.
  await Future<void>.delayed(const Duration(milliseconds: 1500));
  ft.active = false;
  inWindow = false;

  final produced = s1[0] - s0[0];
  // Contador de textura: indice 2 (copias distintas) para gpu/macOS; indice 3 (copias BGRA) para pixel.
  // presented = fotogramas DISTINTOS entregados (por secuencia): gpu = indice 2; pixel = extra[0] (bgra distintos).
  final pixel = _opt(args, '--texture-kind') == 'pixel';
  final ti = pixel ? 3 : 2;
  final distinct = bgra ? decodedInWindow : (pixel ? x1[0] - x0[0] : s1[2] - s0[2]);
  final totalCopies = bgra ? decodedInWindow : (pixel ? s1[3] - s0[3] : s1[1] - s0[1]);
  final presented = bgra ? paintedInWindow : distinct;
  final discarded = bgra ? skipped : produced - presented;
  final growth = (rss['60s'] ?? 0) - (rss['30s'] ?? 0);
  report['counts'] = {
    'produced': produced,
    'presented': presented,
    'discarded': discarded,
    'distinctDelivered': distinct,
    'totalCopies': totalCopies,
    'duplicateCopies': totalCopies - distinct,
    'discardedByStatsDelta':
        produced - (bgra ? s1[3] - s0[3] : s1[ti] - s0[ti]),
    'maxSeqGap': bgra ? maxGap : null,
    'decodedTotal': decoded,
    'paintedTotal': painted,
    'producedTotal': s1[0],
    'distinctTextureCopiesTotal': s1[2],
    'discardedTotalRun': s1[0] - (bgra ? s1[3] : s1[ti]),
    'note': 'ventana = tras el primer segundo; margen +-1 en los bordes',
  };
  List<int> blk(int o) => x1.sublist(o, o + 7);
  Map<String, Object?> iv(int o) {
    final b = blk(o);
    double ms(int us) => round3(us / 1000);
    return {
      'count': b[0], 'min': ms(b[1]), 'p50': ms(b[2]), 'p99': ms(b[3]), 'max': ms(b[4]),
      'under8ms': b[5], 'over50ms': b[6],
    };
  }
  report['producerIntervalMs'] = iv(6);
  report['fetchIntervalMs'] = iv(13);
  report['fetches'] = {
    'requests': x1[1], 'repeatRequests': x1[2], 'gapRequests': x1[3],
    'skippedSeqs': x1[4], 'gapRequestsLate40ms': x1[5],
    'note': 'ventana; peticion = llamada al callback de textura (gpu/pixel) o sondeo de Dart (bgra)',
  };
  report['preciseTimer'] = Platform.environment['TF_P9_PRECISE'] == '1';
  // P9.7k: modo de textura compartida (Windows gpu). ring = anillo de 3 texturas; flushes solo si framesExtra
  // devuelve >= 22 valores (hoy pide 20: ver tf_core.dart).
  report['ring'] = {
    'enabled': Platform.environment['TF_P9_RING'] != '0',
    'flushes': x1.length >= 22 ? x1[21] : null,
    'tearPattern': Platform.environment['TF_P9_TEAR'] == '1',
  };
  // P9 7n: espera a la GPU antes de publicar (TF_P9_WAIT) y variante CopyResource (TF_P9_COPY).
  report['gpuWait'] = x1.length >= 27
      ? {
          'wait': x1[22] & 1, 'copy': (x1[22] >> 1) & 1, 'waits': x1[23],
          'meanUs': x1[23] > 0 ? x1[24] ~/ x1[23] : 0, 'maxUs': x1[25], 'waitTimeouts': x1[26],
        }
      : null;
  report['statsRaw'] = {'atWindowStart': s0, 'atEnd': s1};
  report['frameTiming'] = ft.toJson();
  if (bgra) {
    report['bgra'] = {
      'copyMs': stats(copyMs),
      'decodeMs': stats(decodeMs),
      'skippedLastWins': skipped,
    };
  }
  final wall = wall1 - wallW0, cpu = cpu1 - cpuW0;
  // cpuSeconds(): getrusage en macOS, GetProcessTimes en Windows; NaN (otro SO) no se puede codificar a JSON.
  final cpuOk = !cpu.isNaN && !cpu1.isNaN && !cpu0.isNaN;
  report['cpu'] = {
    'percentOfCoreWindow': cpuOk ? round3(cpu / wall * 100) : null,
    'percentOfCoreWhole':
        cpuOk ? round3((cpu1 - cpu0) / (wall1 - wall0 / 1e6) * 100) : null,
    'cpuSeconds': cpuOk ? round3(cpu) : null,
    'wallSeconds': round3(wall),
    if (!cpuOk) 'note': 'sin medida de CPU en ${Platform.operatingSystem}',
  };
  report['rssMb'] = {...rss, 'growth30to60': round3(growth)};
  report['watchdogMaxMs'] = round3(wdMax);
  report['generatorCostUs'] = cost;
  if (discarded > 0) failed.add('descartes=$discarded');
  if (growth >= 10) failed.add('rssGrowth=$growth MB');

  // Liberación y cierre como en la prueba 2.
  if (!bgra) {
    surf.textureId.value = null;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    core.textureDispose(0);
  }
  surf.image.value = null;
  await Future<void>.delayed(const Duration(milliseconds: 100));
  current?.dispose();
  report['h_shutdown'] = await shutdownCore(core, wd);
  final sd = report['h_shutdown'] as Map<String, Object?>;
  final payload = sd['payload'];
  if (!(payload is Map && payload['clean'] == true)) failed.add('shutdownNotClean');
}
