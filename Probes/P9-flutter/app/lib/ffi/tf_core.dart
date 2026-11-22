// Enlaces dart:ffi a libAppCoreFFI y cliente mínimo (sin paquete `ffi`:
// malloc/free de libc por DynamicLibrary.process()).
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

typedef TfMessageCb = Void Function(Pointer<Uint8>, Int32);

final _libc = DynamicLibrary.process();
final _malloc = _libc.lookupFunction<Pointer<Uint8> Function(IntPtr),
    Pointer<Uint8> Function(int)>('malloc');
final _cfree = _libc.lookupFunction<Void Function(Pointer<Uint8>),
    void Function(Pointer<Uint8>)>('free');

/// `pthread_main_np()` llamado desde el isolate actual: 1 = hilo principal.
int pthreadMainNp() => _libc
    .lookupFunction<Int32 Function(), int Function()>('pthread_main_np')();

Pointer<Uint8> _cString(String s) {
  final b = utf8.encode(s);
  final p = _malloc(b.length + 1);
  p.asTypedList(b.length + 1)
    ..setAll(0, b)
    ..[b.length] = 0;
  return p;
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
        _emit = lib.lookupFunction<Int32 Function(Int32, Int32, Int32),
            int Function(int, int, int)>('tf_debug_emit');

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
  final int Function(int, int, int) _emit;

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

  int emit(int hz, int count, int bytes) => _emit(hz, count, bytes);
  void shutdown(int timeoutMs) => _shutdown(timeoutMs);

  void dispose() {
    _callable?.close();
    _port?.close();
  }
}
