import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'call_timeouts.dart';
import 'ffi_bindings.dart';
import 'host_services.dart';
import 'launch_options.dart';

typedef Json = Map<String, Object?>;

/// Error del núcleo `{code, message, args}`. Se traduce por `code` (`error_<code>` en ARB) y cae a `message`.
/// Códigos propios de Dart: `timeout` (venció el límite de la llamada), `cancelled` (el núcleo se cierra).
class CoreError implements Exception {
  const CoreError(this.code, this.message, [this.args = const {}]);

  factory CoreError.fromJson(Object? e) {
    if (e is Map) {
      final a = e['args'];
      return CoreError('${e['code'] ?? 'internal'}', '${e['message'] ?? ''}',
          a is Map ? a.cast<String, Object?>() : const {});
    }
    return CoreError('internal', '$e');
  }

  final String code;
  final String message;
  final Json args;

  @override
  String toString() => 'CoreError($code: $message)';
}

/// Única puerta al núcleo. Solo los stores la usan; ningún widget.
abstract class CoreClient {
  Future<T> call<T>(String method, Object? params, T Function(Json) decode);

  /// Payload de los eventos [event] (`*.state`, `jobs.progress`...).
  Stream<T> on<T>(String event, T Function(Json) decode);

  /// Cierre asíncrono del núcleo; resuelve con `core.shutdown`.
  Future<void> shutdown();
}

/// Transporte de mensajes JSON con el núcleo; el real es [FfiTransport], los tests usan uno falso.
abstract class CoreTransport {
  /// Respuestas, eventos y `hostRequest` ya decodificados, en orden.
  Stream<Json> get messages;
  void start(List<String> args);
  void send(Json message);

  /// Asíncrono: el final llega como evento `core.shutdown`.
  void shutdown(int timeoutMs);
  void close();
}

Json _asJson(Object? r) =>
    r is Map ? r.cast<String, Object?>() : (r == null ? <String, Object?>{} : {'value': r});

class _Pending {
  _Pending(this.completer);
  final Completer<Object?> completer;
  Timer? timer;
}

/// Lógica del cliente sobre un [CoreTransport]: ids incrementales, límites por método, respuestas tardías descartadas,
/// eventos y servicios de anfitrión.
class TransportCoreClient implements CoreClient {
  TransportCoreClient(
    this._t, {
    HostServices? host,
    this.timeouts = const CallTimeouts(),
    this.shutdownTimeoutMs = 5000,
  }) : _host = host ?? const PlatformHostServices();

  final CoreTransport _t;
  final HostServices _host;
  final CallTimeouts timeouts;

  /// Tope que se pasa a `tf_core_shutdown`; Dart espera además 2 s de margen por si no llega el evento.
  final int shutdownTimeoutMs;
  final _pending = <int, _Pending>{};
  final _events = StreamController<({String name, Object? payload})>.broadcast();
  StreamSubscription<Json>? _sub;
  Future<void>? _shutdown;
  int _nextId = 1;
  bool _closed = false;

  /// Arranca el núcleo con los argumentos de [LaunchOptions.toCoreArgs].
  void start(List<String> args) {
    _sub = _t.messages.listen(_onMessage);
    _t.start(args);
  }

  @override
  Future<T> call<T>(String method, Object? params, T Function(Json) decode) async {
    if (_closed) throw const CoreError('cancelled', 'El núcleo está cerrado.');
    final id = _nextId++;
    final p = _pending[id] = _Pending(Completer<Object?>());
    final limit = timeouts.of(method);
    if (limit != null) {
      p.timer = Timer(limit, () {
        if (_pending.remove(id) == null) return;
        p.completer.completeError(CoreError('timeout',
            'Sin respuesta de $method en ${limit.inSeconds} s.',
            {'method': method, 'seconds': limit.inSeconds}));
      });
    }
    try {
      _t.send({'id': id, 'method': method, 'params': params ?? <String, Object?>{}});
    } catch (e) {
      _pending.remove(id);
      p.timer?.cancel();
      throw CoreError('internal', '$e');
    }
    return decode(_asJson(await p.completer.future));
  }

  @override
  Stream<T> on<T>(String event, T Function(Json) decode) => _events.stream
      .where((e) => e.name == event)
      .map((e) => decode(_asJson(e.payload)));

  @override
  Future<void> shutdown() => _shutdown ??= _doShutdown();

  Future<void> _doShutdown() async {
    final done = on('core.shutdown', (j) => j).first;
    _t.shutdown(shutdownTimeoutMs);
    try {
      await done.timeout(Duration(milliseconds: shutdownTimeoutMs + 2000));
    } on TimeoutException {
      // El tope del núcleo ya cubre el cierre; seguimos para no colgar la ventana.
    }
    _closeAll();
  }

  void _closeAll() {
    _closed = true;
    final all = _pending.values.toList();
    _pending.clear();
    for (final p in all) {
      p.timer?.cancel();
      p.completer.completeError(const CoreError('cancelled', 'El núcleo se cierra.'));
    }
    _sub?.cancel();
    _events.close();
    _t.close();
  }

  void _onMessage(Json m) {
    final id = m['id'];
    if (id is int) {
      final p = _pending.remove(id);
      if (p == null) return; // tardía (tras el límite) o desconocida
      p.timer?.cancel();
      final err = m['error'];
      if (err != null) {
        p.completer.completeError(CoreError.fromJson(err));
      } else {
        p.completer.complete(m['result']);
      }
    } else if (m['event'] is String) {
      if (!_events.isClosed) {
        _events.add((name: m['event'] as String, payload: m['payload']));
      }
    } else if (m['hostRequest'] is Map) {
      _onHostRequest(_asJson(m['hostRequest']));
    }
  }

  Future<void> _onHostRequest(Json r) async {
    final id = r['id'];
    Json response;
    try {
      final result = await _host.handle(r['method'] as String? ?? '', _asJson(r['params']));
      response = {'id': id, 'result': result};
    } on HostError catch (e) {
      response = {'id': id, 'error': e.toJson()};
    } catch (e) {
      response = {'id': id, 'error': HostError('internal', '$e').toJson()};
    }
    if (!_closed) _t.send({'hostResponse': response});
  }
}

/// Transporte real: puerto nativo de Dart sobre `tf_core_*`.
class FfiTransport implements CoreTransport {
  FfiTransport(this._b);
  final TfBindings _b;
  final _out = StreamController<Json>();
  ReceivePort? _port;

  @override
  Stream<Json> get messages => _out.stream;

  @override
  void start(List<String> args) {
    final rc = _b.initDartApi(NativeApi.initializeApiDLData);
    if (rc != 0) throw StateError('tf_core_init_dart_api = $rc');
    final port = _port = ReceivePort();
    port.listen(_onPort);
    final started = _b.start(jsonEncode({'args': args}), port.sendPort.nativePort);
    if (started != 0) {
      port.close();
      throw StateError('tf_core_start = $started');
    }
  }

  void _onPort(Object? m) {
    if (m is! Uint8List) return; // el finalizador del búfer externo llama a tf_core_free
    try {
      final msg = utf8.decoder.fuse(json.decoder).convert(m);
      if (msg is Map) _out.add(msg.cast<String, Object?>());
    } catch (_) {
      // mensaje ilegible: se descarta
    }
  }

  @override
  void send(Json message) => _b.send(utf8.encode(jsonEncode(message)));

  @override
  void shutdown(int timeoutMs) => _b.shutdown(timeoutMs);

  @override
  void close() {
    _port?.close();
    _out.close();
  }
}

/// Cliente real: carga la biblioteca, arranca el núcleo con los argumentos de [o] y atiende los servicios de anfitrión.
CoreClient createFfiCoreClient(LaunchOptions o, {HostServices? host}) {
  final client = TransportCoreClient(
    FfiTransport(TfBindings.open(coreLib: o.coreLib)),
    host: host,
  );
  client.start(o.toCoreArgs());
  return client;
}
