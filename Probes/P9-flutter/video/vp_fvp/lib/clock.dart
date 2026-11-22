// Reloj externo takeview.position sintético + enganche a mdk onSync por FFI directo.
// onSync (C, hilo de render de mdk) llama a la función nativa vp_onsync_clock (MainFlutterWindow.swift).
// NativeCallable.isolateGroupBound no sirve: exige --experimental-shared-data.
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:fvp/mdk.dart';
// ignore: implementation_imports
import 'package:fvp/src/generated_bindings.dart';

/// Memoria nativa compartida: 0 seq, 1 seconds, 2 playing, 3 at, 4 rate, 5 epoch, 6 nCalls,
/// 7 tPrimera, 8 tÚltima, 9 maxGap, 10 hiloPrimero, 11 llamadasEnOtroHilo, 12 hiloMain
// (la dirección viaja en el `opaque` del callback: nada de estado global en Dart)

/// Reloj de pared en s (µs). Mismo reloj para el callback y para la medida.
double nowS() => DateTime.now().microsecondsSinceEpoch / 1e6;

typedef _Tid = int Function();


class ExtClock {
  ExtClock() {
    _p = calloc<Double>(16);
    _p[12] = (_tid() & 0xFFFFFFFFFFFF).toDouble();
  }
  late final Pointer<Double> _p;
  int epoch = 0;
  double _sec = 0, _at = 0, _rate = 1;
  bool _playing = false;

  static int _tid() => DynamicLibrary.process().lookupFunction<Uint64 Function(), _Tid>('pthread_self')();

  double pos([double? t]) => _playing ? _sec + ((t ?? nowS()) - _at) * _rate : _sec;
  double get rate => _rate;
  bool get playing => _playing;
  double get at => _at;
  double get seconds => _sec;

  /// Emite un takeview.position (lo que el 30 Hz reescribe).
  void emit({double? seconds, bool? playing, double? rate, bool jump = false}) {
    final t = nowS();
    final cur = pos(t);
    _sec = seconds ?? cur;
    _playing = playing ?? _playing;
    _rate = rate ?? _rate;
    _at = t;
    if (jump) epoch++;
    _write();
  }

  void _write() {
    final s = _p[0];
    _p[0] = s + 1;
    _p[1] = _sec;
    _p[2] = _playing ? 1 : 0;
    _p[3] = _at;
    _p[4] = _rate;
    _p[5] = epoch.toDouble();
    _p[0] = s + 2;
  }

  /// Re-emisión periódica (mismo estado, `at` nuevo) como haría el núcleo a 30 Hz.
  void heartbeat() => emit();

  void attach(Player player) {
    _write();
    final fn = DynamicLibrary.process().lookup<NativeFunction<Double Function(Pointer<Void>)>>('vp_onsync_clock');
    final api = Pointer<mdkPlayerAPI>.fromAddress(player.nativeHandle);
    final cb = calloc<mdkSyncCallback>();
    cb.ref.cb = fn;
    cb.ref.opaque = Pointer<Void>.fromAddress(_p.address);
    api.ref.onSync.asFunction<void Function(Pointer<mdkPlayer>, mdkSyncCallback, int)>()(api.ref.object, cb.ref, 0);
  }

  Map<String, Object?> syncStats() => {
        'calls': _p[6].toInt(),
        'spanS': _p[8] - _p[7],
        'hz': _p[6] > 1 ? (_p[6] - 1) / (_p[8] - _p[7]) : 0,
        'maxGapMs': _p[9] * 1e3,
        'otherThreadCalls': _p[11].toInt(),
        'cbThreadIsMain': _p[10] == _p[12],
      };
}
