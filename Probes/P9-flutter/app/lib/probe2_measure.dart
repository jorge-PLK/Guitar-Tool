import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'ffi/tf_core.dart';
import 'probe2_util.dart';

const methods4 = ['app.info', 'library.list', 'settings.get', 'audio.devices'];

/// n rondas secuenciales de los 4 métodos; devuelve ms por ida y vuelta y errores.
Future<(List<double>, int)> rounds(
  TfCore core,
  int n, [
  List<String> methods = methods4,
]) async {
  final ms = <double>[];
  var errors = 0;
  final sw = Stopwatch();
  for (var i = 0; i < n; i++) {
    for (final m in methods) {
      sw.reset();
      sw.start();
      try {
        await core.call(m);
      } catch (_) {
        errors++;
      }
      ms.add(sw.elapsedMicroseconds / 1000);
    }
  }
  return (ms, errors);
}

/// Emisión nativa→Dart y medidas de latencia, jitter, orden y pérdidas.
Future<Map<String, Object?>> emitRun(
  TfCore core,
  int hz,
  int count,
  int bytes,
) async {
  final seqs = <int>[];
  final lat = <double>[];
  final arr = <int>[];
  var doneNs = 0;
  final done = Completer<void>();
  final sub = core.events.listen((e) {
    if (e.name == 'probe.tick') {
      final p = e.payload as Map;
      seqs.add(p['seq'] as int);
      lat.add((e.recvNs - (p['t'] as int)) / 1000);
      arr.add(e.recvNs);
    } else if (e.name == 'probe.done') {
      doneNs = e.recvNs;
      if (!done.isCompleted) done.complete();
    }
  });
  final t0 = core.nowNs();
  final rc = core.emit(hz, count, bytes);
  var timedOut = false;
  if (rc == 0) {
    final secs = hz > 0 ? count / hz + 10 : 30;
    await done.future.timeout(
      Duration(seconds: secs.ceil()),
      onTimeout: () => timedOut = true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  await sub.cancel();
  var maxSeen = -1, outOfOrder = 0, descents = 0, prev = -1;
  for (final s in seqs) {
    if (s < maxSeen) outOfOrder++;
    if (s < prev) descents++;
    if (s > maxSeen) maxSeen = s;
    prev = s;
  }
  final unique = seqs.toSet().length;
  final iv = <double>[];
  for (var i = 1; i < arr.length; i++) {
    iv.add((arr[i] - arr[i - 1]) / 1e6);
  }
  final dev = iv.map((d) => d - 1000 / 60).toList();
  final rms = dev.isEmpty
      ? 0.0
      : (dev.fold(0.0, (a, b) => a + b * b) / dev.length);
  return {
    'rc': rc,
    'timedOut': timedOut,
    'received': seqs.length,
    'unique': unique,
    'lost': count - unique,
    'duplicates': seqs.length - unique,
    'outOfOrder': outOfOrder,
    'descents': descents,
    'latencyUs': stats(lat, 1),
    if (hz > 0) ...{
      'intervalMs': stats(iv),
      'intervalStddevMs': round3(stddev(iv)),
      'jitterRmsVs16_67Ms': round3(_sqrt(rms)),
    } else ...{
      'totalMs': round3((doneNs - t0) / 1e6),
      'usPerMessage': round3((doneNs - t0) / 1000 / count),
    },
  };
}

double _sqrt(double x) => math.sqrt(x);

/// jsonDecode(utf8.decode) contra utf8.decoder.fuse(json.decoder), µs/mensaje.
Map<String, Object?> decodeBench() {
  const base = '{"event":"probe.tick","payload":{"seq":12345,"t":123456789012345,"pad":"';
  const tail = '"}}';
  final pad = 'x' * (300 - base.length - tail.length);
  final bytes = Uint8List.fromList(utf8.encode('$base$pad$tail'));
  final fused = utf8.decoder.fuse(json.decoder);
  const n = 100000;
  var sink = 0;
  for (var i = 0; i < 10000; i++) {
    sink += (jsonDecode(utf8.decode(bytes)) as Map).length;
    sink += (fused.convert(bytes) as Map).length;
  }
  final sw = Stopwatch()..start();
  for (var i = 0; i < n; i++) {
    sink += (jsonDecode(utf8.decode(bytes)) as Map).length;
  }
  final a = sw.elapsedMicroseconds / n;
  sw.reset();
  for (var i = 0; i < n; i++) {
    sink += (fused.convert(bytes) as Map).length;
  }
  final b = sw.elapsedMicroseconds / n;
  return {
    'bytes': bytes.length,
    'iterations': n,
    'jsonDecode_utf8decode_us': round3(a),
    'fused_us': round3(b),
    'sink': sink,
  };
}
