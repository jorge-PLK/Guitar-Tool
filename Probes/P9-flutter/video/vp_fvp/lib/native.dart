// Primitivas nativas por plataforma: reloj común, CPU de proceso, id de hilo y callback de onSync.
// macOS: vp_onsync_clock (MainFlutterWindow.swift), memoria compartida de doubles, reloj de pared.
// Windows: tf_sync_* (windows/runner/tf_sync.cpp), reloj QueryPerformanceCounter en ns.
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

DynamicLibrary _lib() {
  try {
    return DynamicLibrary.process();
  } catch (_) {
    return DynamicLibrary.executable();
  }
}

final DynamicLibrary _dl = _lib();

typedef _I64 = int Function();
typedef _U32 = int Function();
typedef _D = double Function();
typedef _SetF = void Function(double, int, int, double, int);
typedef _StatsF = void Function(Pointer<Double>);

class WinShim {
  final nowNs = _dl.lookupFunction<Int64 Function(), _I64>('tf_sync_now_ns');
  final tid = _dl.lookupFunction<Uint32 Function(), _U32>('tf_thread_id');
  final cpu = _dl.lookupFunction<Double Function(), _D>('tf_cpu_s');
  final set = _dl.lookupFunction<Void Function(Double, Int32, Int64, Double, Int64), _SetF>('tf_sync_set');
  final stats = _dl.lookupFunction<Void Function(Pointer<Double>), _StatsF>('tf_sync_stats');
  final cb = _dl.lookup<NativeFunction<Double Function(Pointer<Void>)>>('tf_sync_cb');
}

WinShim? _winCache;
WinShim get win => _winCache ??= WinShim();

/// Reloj común (s) para el callback y para la medida.
double nowS() => Platform.isWindows ? win.nowNs() / 1e9 : DateTime.now().microsecondsSinceEpoch / 1e6;

/// Id del hilo actual (para saber si el callback corre en el hilo de UI).
int threadId() {
  if (Platform.isWindows) return win.tid();
  return _dl.lookupFunction<Uint64 Function(), _I64>('pthread_self')() & 0xFFFFFFFFFFFF;
}

Pointer<NativeFunction<Double Function(Pointer<Void>)>> syncCallback() => Platform.isWindows
    ? win.cb
    : _dl.lookup<NativeFunction<Double Function(Pointer<Void>)>>('vp_onsync_clock');

/// CPU de proceso acumulada (s).
double cpuS() {
  if (Platform.isWindows) return win.cpu();
  final gru = _dl.lookupFunction<Int32 Function(Int32, Pointer<Int64>), int Function(int, Pointer<Int64>)>('getrusage');
  final p = calloc<Int64>(40);
  gru(0, p);
  final v = p[0] + p[1] / 1e6 + p[2] + p[3] / 1e6;
  calloc.free(p);
  return v;
}
