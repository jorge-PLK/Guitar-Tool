import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:fvp/mdk.dart';
import 'clock.dart';
import 'rig.dart';
import 'stats.dart';

Future<void> wait(double s) => Future.delayed(Duration(microseconds: (s * 1e6).round()));

typedef _Gru = int Function(int, Pointer<Int64>);
final _gru = DynamicLibrary.process().lookupFunction<Int32 Function(Int32, Pointer<Int64>), _Gru>('getrusage');

/// CPU de proceso acumulado (s).
double cpuS() {
  final p = calloc<Int64>(40);
  _gru(0, p);
  final v = p[0] + p[1] / 1e6 + p[2] + p[3] / 1e6;
  calloc.free(p);
  return v;
}

Future<Map<String, Object?>> steady(Rig r, double secs) async {
  r.jump(1.0);
  r.play();
  r.startSampling();
  final out = <String, Object?>{};
  for (final rate in [1.0, 0.7, 0.5]) {
    r.setRate(rate);
    final t0 = nowS();
    await wait(secs + 1);
    out['rate_$rate'] = regime(r.samples, t0 + 1, t0 + 1 + secs, rate);
  }
  r.stopSampling();
  out['endPos'] = r.clock.pos();
  return out;
}

Future<Map<String, Object?>> cpu(Rig r, double secs) async {
  r.jump(1.0);
  r.play();
  await wait(2);
  final c0 = cpuS(), t0 = nowS();
  await wait(secs);
  final dc = cpuS() - c0, dt = nowS() - t0;
  return {'cpuPercentOfCore': (dc / dt * 1000).round() / 10, 'rssMb': ProcessInfo.currentRss / 1048576, 'windowS': dt, 'sampling': false};
}

Future<Map<String, Object?>> seekCase(Rig r) async {
  r.jump(2.0);
  r.play();
  r.startSampling();
  await wait(2);
  final jumps = <Map<String, Object?>>[];
  final targets = [15.0, 5.0, 0.0, 20.0, 10.0, 28.3];
  for (final tgt in targets) {
    final tj = nowS();
    final res = <String, Object?>{};
    r.jump(tgt).then((v) => res['seekReply'] = [v, ((nowS() - tj) * 1e4).round() / 10]);
    await wait(1.5);
    final rec = recovery(r.samples, tj, tj + 1.5);
    jumps.add({'target': tgt, ...rec, ...res, 'okThreshold300': (rec['stayOkMs'] as double?) != null && (rec['stayOkMs'] as double) < 300});
  }
  r.stopSampling();
  return {'jumps': jumps, 'flags': r.seekFlags};
}

Future<Map<String, Object?>> loopCase(Rig r) async {
  const a = 10.0, b = 12.0;
  r.jump(a);
  r.play();
  r.startSampling();
  await wait(1.0);
  final wraps = <double>[];
  final timer = Stream.periodic(const Duration(milliseconds: 5)).listen((_) {
    final p = r.clock.pos();
    if (p >= b) {
      wraps.add(nowS());
      r.clock.emit(seconds: a + (p - b), jump: true);
      r.player.seek(position: (a * 1000).round(), flags: SeekFlag(r.seekFlags));
    }
  });
  while (wraps.length < 6) {
    await wait(0.05);
  }
  await wait(1.0);
  await timer.cancel();
  r.stopSampling();
  final rec = <Map<String, Object?>>[];
  final inLoop = <Sample>[];
  for (var i = 0; i < wraps.length; i++) {
    final end = i + 1 < wraps.length ? wraps[i + 1] : wraps[i] + 1.5;
    rec.add(recovery(r.samples, wraps[i], end - 0.05));
    inLoop.addAll(r.samples.where((s) => s.t >= wraps[i] + 0.5 && s.t < end - 0.05));
  }
  return {'wraps': wraps.length, 'recovery': rec, 'inLoop': regime(inLoop, 0, 1e18, 1.0)};
}

Future<Map<String, Object?>> rotation(Rig r, double secs) async {
  r.play();
  await wait(secs);
  final snap = await r.player.snapshot();
  return {'snapshotBytes': snap?.length, 'playedS': secs};
}

Future<Map<String, Object?>> startPts(Rig r) async {
  r.play();
  final out = <Map<String, Object?>>[];
  for (final fl in [SeekFlag.fromStart | SeekFlag.frame, SeekFlag.from0 | SeekFlag.frame]) {
    r.seekFlags = fl;
    for (final c in [0.0, 155.547, 160.0]) {
      final reply = await r.jump(c);
      r.clock.emit(seconds: c, playing: false);
      await wait(1.2);
      final snap = await r.player.snapshot(width: 160, height: 90);
      var sum = 0, hash = 0;
      if (snap != null) {
        for (var i = 0; i < snap.length; i += 4) {
          sum += snap[i + 1];
          hash = (hash * 31 + snap[i + 1]) & 0xffffff;
        }
      }
      out.add({'flags': SeekFlag(fl).toString(), 'clock': c, 'seekReply': reply, 'mdkPositionMs': r.player.position, 'meanG': snap == null ? null : sum * 4 / snap.length, 'hash': hash});
    }
  }
  return {'tests': out};
}
