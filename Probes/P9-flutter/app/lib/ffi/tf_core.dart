// Enlaces dart:ffi a libAppCoreFFI y cliente mínimo (sin paquete `ffi`:
// malloc/free de la libc: process() en macOS, ucrtbase.dll en Windows).
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:typed_data';

typedef TfMessageCb = Void Function(Pointer<Uint8>, Int32);

final _libc = Platform.isWindows
    ? DynamicLibrary.open('ucrtbase.dll')
    : DynamicLibrary.process();
final _malloc = _libc.lookupFunction<Pointer<Uint8> Function(IntPtr),
    Pointer<Uint8> Function(int)>('malloc');
final _cfree = _libc.lookupFunction<Void Function(Pointer<Uint8>),
    void Function(Pointer<Uint8>)>('free');

final _calloc = _libc.lookupFunction<Pointer<Uint8> Function(IntPtr, IntPtr),
    Pointer<Uint8> Function(int, int)>('calloc');

/// calloc de la libc (búfer nativo a cero); liberar con [nativeFree].
Pointer<Uint8> nativeCalloc(int bytes) => _calloc(bytes, 1);
void nativeFree(Pointer<NativeType> p) => _cfree(p.cast<Uint8>());

Pointer<Uint8> _cString(String s) {
  final b = utf8.encode(s);
  final p = _malloc(b.length + 1);
  p.asTypedList(b.length + 1)
    ..setAll(0, b)
    ..[b.length] = 0;
  return p;
}

/// Prueba 5 (vídeo, solo Apple): lookups perezosos al construir, no al cargar.
class TfVideo {
  TfVideo._(DynamicLibrary lib)
      : open = lib.lookupFunction<Int32 Function(Int32, Pointer<Uint8>),
            int Function(int, Pointer<Uint8>)>('tf_debug_video_open'),
        close = lib.lookupFunction<Void Function(Int32), void Function(int)>(
            'tf_debug_video_close'),
        state = lib.lookupFunction<Int32 Function(Int32), int Function(int)>(
            'tf_debug_video_state'),
        _clock = lib.lookupFunction<
            Void Function(Int32, Double, Double, Int32, Int32),
            void Function(int, double, double, int, int)>('tf_debug_video_clock'),
        _loop = lib.lookupFunction<Void Function(Int32, Double, Double, Int32),
            void Function(int, double, double, int)>('tf_debug_video_loop'),
        _info = lib.lookupFunction<Pointer<Uint8> Function(Int32),
            Pointer<Uint8> Function(int)>('tf_debug_video_info'),
        _stats = lib.lookupFunction<Pointer<Uint8> Function(Int32, Int32),
            Pointer<Uint8> Function(int, int)>('tf_debug_video_stats'),
        textureCreate = lib.lookupFunction<Int64 Function(Int32),
            int Function(int)>('tf_texture_create'),
        textureDispose = lib.lookupFunction<Void Function(Int32),
            void Function(int)>('tf_texture_dispose');

  factory TfVideo.open(String libPath) => TfVideo._(DynamicLibrary.open(libPath));

  final int Function(int, Pointer<Uint8>) open;
  final void Function(int) close;

  /// 0 abriendo, 1 listo, 2 fallo, -1 sin canal.
  final int Function(int) state;
  final void Function(int, double, double, int, int) _clock;
  final void Function(int, double, double, int) _loop;
  final Pointer<Uint8> Function(int) _info;
  final Pointer<Uint8> Function(int, int) _stats;
  final int Function(int) textureCreate;
  final void Function(int) textureDispose;

  /// 0 arrancó la apertura (asíncrona; ver [state]), 1 ruta nula.
  int openFile(int ch, String path) {
    final p = _cString(path);
    try {
      return open(ch, p);
    } finally {
      _cfree(p);
    }
  }

  void clock(int ch, double seconds, double rate, bool playing, bool jump) =>
      _clock(ch, seconds, rate, playing ? 1 : 0, jump ? 1 : 0);
  void loop(int ch, double start, double end, bool enabled) =>
      _loop(ch, start, end, enabled ? 1 : 0);

  Map<String, Object?> _json(Pointer<Uint8> p) {
    if (p == nullptr) return {};
    try {
      var n = 0;
      while (p[n] != 0) {
        n++;
      }
      final m = json.decode(utf8.decode(p.asTypedList(n)));
      return m is Map ? m.cast<String, Object?>() : {};
    } finally {
      _cfree(p); // strdup: free() de libc
    }
  }

  Map<String, Object?> info(int ch) => _json(_info(ch));
  Map<String, Object?> stats(int ch, {bool reset = false}) =>
      _json(_stats(ch, reset ? 1 : 0));
}

class CoreEvent {
  CoreEvent(this.name, this.payload, this.recvNs);
  final String name;
  final Object? payload;
  /// tf_debug_now_ns() al recibir, antes de decodificar.
  final int recvNs;
}

class CoreError implements Exception {
  CoreError(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'CoreError($code: $message)';
}

class TfCore {
  TfCore._(this.sink, DynamicLibrary lib)
      : _start = lib.lookupFunction<
            Int32 Function(Pointer<Uint8>, Pointer<NativeFunction<TfMessageCb>>,
                Pointer<Void>),
            int Function(Pointer<Uint8>, Pointer<NativeFunction<TfMessageCb>>,
                Pointer<Void>)>('tf_core_start'),
        _startPort = lib.lookupFunction<Int32 Function(Pointer<Uint8>, Int64),
            int Function(Pointer<Uint8>, int)>('tf_core_start_port'),
        _initDartApi = lib.lookupFunction<IntPtr Function(Pointer<Void>),
            int Function(Pointer<Void>)>('tf_core_init_dart_api'),
        _send = lib.lookupFunction<Void Function(Pointer<Uint8>, Int32),
            void Function(Pointer<Uint8>, int)>('tf_core_send'),
        _free = lib.lookupFunction<Void Function(Pointer<Uint8>),
            void Function(Pointer<Uint8>)>('tf_core_free'),
        _shutdown = lib.lookupFunction<Void Function(Int32),
            void Function(int)>('tf_core_shutdown'),
        liveBuffers = lib.lookupFunction<Int64 Function(), int Function()>(
            'tf_debug_live_buffers'),
        nowNs = lib.lookupFunction<Int64 Function(), int Function()>(
            'tf_debug_now_ns',
            isLeaf: true),
        isMainThread = lib.lookupFunction<Int32 Function(), int Function()>(
            'tf_debug_is_main_thread'),
        apartment = lib.lookupFunction<Int32 Function(), int Function()>(
            'tf_debug_apartment'),
        _mainActorSelftest = lib.lookupFunction<Int32 Function(Int32),
            int Function(int)>('tf_debug_mainactor_selftest'),
        _emit = lib.lookupFunction<Int32 Function(Int32, Int32, Int32),
            int Function(int, int, int)>('tf_debug_emit'),
        textureCreate = lib.lookupFunction<Int64 Function(Int32),
            int Function(int)>('tf_texture_create'),
        textureDispose = lib.lookupFunction<Void Function(Int32),
            void Function(int)>('tf_texture_dispose'),
        framesStart = lib.lookupFunction<
            Int32 Function(Int32, Int32, Int32, Int32),
            int Function(int, int, int, int)>('tf_debug_frames_start'),
        framesStop = lib.lookupFunction<Void Function(Int32),
            void Function(int)>('tf_debug_frames_stop'),
        frameBgra = lib.lookupFunction<
            Int32 Function(Int32, Pointer<Uint8>, Int32, Pointer<Int32>,
                Pointer<Int32>, Pointer<Int64>),
            int Function(int, Pointer<Uint8>, int, Pointer<Int32>,
                Pointer<Int32>, Pointer<Int64>)>('tf_debug_frame_bgra'),
        _framesStats = lib.lookupFunction<
            Void Function(Int32, Pointer<Int64>, Pointer<Int64>,
                Pointer<Int64>, Pointer<Int64>),
            void Function(int, Pointer<Int64>, Pointer<Int64>, Pointer<Int64>,
                Pointer<Int64>)>('tf_debug_frames_stats'),
        framesCostUs = lib.lookupFunction<Int64 Function(Int32),
            int Function(int)>('tf_debug_frames_cost_us');

  /// `sink` = `listener` | `port`.
  factory TfCore.open(String libPath, String sink) =>
      TfCore._(sink, DynamicLibrary.open(libPath));

  final String sink;
  final int Function(Pointer<Uint8>, Pointer<NativeFunction<TfMessageCb>>,
      Pointer<Void>) _start;
  final int Function(Pointer<Uint8>, int) _startPort;
  final int Function(Pointer<Void>) _initDartApi;
  final void Function(Pointer<Uint8>, int) _send;
  final void Function(Pointer<Uint8>) _free;
  final void Function(int) _shutdown;
  final int Function() liveBuffers;
  final int Function() nowNs;
  /// 1 si el hilo que llama es el principal del proceso.
  final int Function() isMainThread;
  /// Windows: 0 STA, 1 MTA, 2 NA, 3 MAINSTA, -1 sin COM; otras = -2.
  final int Function() apartment;
  final int Function(int) _mainActorSelftest;
  final int Function(int, int, int) _emit;

  // Prueba 3 (fotogramas).
  final int Function(int) textureCreate;
  final void Function(int) textureDispose;
  final int Function(int, int, int, int) framesStart;
  final void Function(int) framesStop;
  final int Function(int, Pointer<Uint8>, int, Pointer<Int32>, Pointer<Int32>,
      Pointer<Int64>) frameBgra;
  final void Function(int, Pointer<Int64>, Pointer<Int64>, Pointer<Int64>,
      Pointer<Int64>) _framesStats;
  final int Function(int) framesCostUs;

  /// [producidos, copiasTextura, copiasTexturaDistintas, copiasBgra].
  List<int> framesStats(int channel) {
    final p = nativeCalloc(32).cast<Int64>();
    try {
      _framesStats(channel, p, p + 1, p + 2, p + 3);
      return [p[0], p[1], p[2], p[3]];
    } finally {
      nativeFree(p);
    }
  }

  NativeCallable<TfMessageCb>? _callable;
  ReceivePort? _port;
  int _nextId = 1;
  int decodeErrors = 0;
  int messages = 0;
  final _pending = <int, Completer<Object?>>{};
  final _events = StreamController<CoreEvent>.broadcast(sync: true);

  Stream<CoreEvent> get events => _events.stream;

  /// 0 ok, 1 ya arrancado, otros = error del núcleo.
  int start(String optionsJson) {
    final opts = _cString(optionsJson);
    try {
      if (sink == 'port') {
        final rc = _initDartApi(NativeApi.initializeApiDLData);
        if (rc != 0) throw StateError('tf_core_init_dart_api = $rc');
        final port = _port = ReceivePort();
        port.listen((Object? m) {
          final t = nowNs();
          if (m is Uint8List) _handle(m, t); // el finalizador libera: sin tf_core_free
        });
        return _startPort(opts, port.sendPort.nativePort);
      }
      final c = _callable = NativeCallable<TfMessageCb>.listener(_onNative);
      return _start(opts, c.nativeFunction, nullptr);
    } finally {
      _cfree(opts);
    }
  }

  void _onNative(Pointer<Uint8> ptr, int len) {
    final t = nowNs();
    try {
      _handle(ptr.asTypedList(len), t);
    } finally {
      _free(ptr);
    }
  }

  void _handle(Uint8List bytes, int recvNs) {
    messages++;
    final Object? msg;
    try {
      msg = utf8.decoder.fuse(json.decoder).convert(bytes);
    } catch (_) {
      decodeErrors++;
      return;
    }
    if (msg is! Map) return;
    final id = msg['id'];
    if (id is int) {
      final c = _pending.remove(id);
      if (c == null) return;
      final err = msg['error'];
      if (err is Map) {
        c.completeError(CoreError('${err['code']}', '${err['message']}'));
      } else {
        c.complete(msg['result']);
      }
    } else if (msg['event'] is String) {
      _events.add(CoreEvent(msg['event'] as String, msg['payload'], recvNs));
    }
  }

  Future<Object?> call(String method, [Map<String, Object?> params = const {}]) {
    final id = _nextId++;
    final c = _pending[id] = Completer<Object?>();
    final b = utf8.encode(jsonEncode({'id': id, 'method': method, 'params': params}));
    final p = _malloc(b.length);
    p.asTypedList(b.length).setAll(0, b);
    _send(p, b.length); // el núcleo copia
    _cfree(p);
    return c.future;
  }

  /// 0 lanzada, 1 núcleo sin arrancar; el resultado llega como `probe.mainactor`.
  int mainActorSelftest(int timeoutMs) => _mainActorSelftest(timeoutMs);

  int emit(int hz, int count, int bytes) => _emit(hz, count, bytes);
  void shutdown(int timeoutMs) => _shutdown(timeoutMs);

  void dispose() {
    _callable?.close();
    _port?.close();
  }
}
