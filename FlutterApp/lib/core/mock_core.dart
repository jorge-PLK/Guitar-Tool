import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show AssetManifest, rootBundle;

import 'core_client.dart';

/// Origen de los fixtures de `Contract/fixtures/<grupo>/<nombre>.<params|result|error|event>.json`.
abstract class FixtureSource {
  /// Rutas relativas a la carpeta de fixtures (`app/app.info.result.json`).
  Future<List<String>> list();
  Future<String> read(String path);
}

/// Tests (y desarrollo con `--mock` desde el repo): lee de disco, de forma asíncrona.
class DirectoryFixtureSource implements FixtureSource {
  DirectoryFixtureSource(this.root);
  final Directory root;

  /// Sube desde [from] (o el directorio actual) hasta encontrar `Contract/fixtures`.
  static Future<DirectoryFixtureSource?> find([Directory? from]) async {
    var d = (from ?? Directory.current).absolute;
    while (true) {
      final c = Directory('${d.path}/Contract/fixtures');
      if (await c.exists()) return DirectoryFixtureSource(c);
      if (d.parent.path == d.path) return null;
      d = d.parent;
    }
  }

  @override
  Future<List<String>> list() async => [
        await for (final e in root.list(recursive: true))
          if (e is File && e.path.endsWith('.json'))
            e.path.substring(root.path.length + 1).replaceAll(r'\', '/'),
      ];

  @override
  Future<String> read(String path) => File('${root.path}/$path').readAsString();
}

/// App con `--mock`: lee de los assets empaquetados bajo [prefix].
class AssetFixtureSource implements FixtureSource {
  const AssetFixtureSource([this.prefix = 'assets/fixtures/']);
  final String prefix;

  @override
  Future<List<String>> list() async {
    final m = await AssetManifest.loadFromAssetBundle(rootBundle);
    return [
      for (final a in m.listAssets())
        if (a.startsWith(prefix) && a.endsWith('.json')) a.substring(prefix.length),
    ];
  }

  @override
  Future<String> read(String path) => rootBundle.loadString('$prefix$path');
}

class MockCall {
  const MockCall(this.method, this.params);
  final String method;
  final Object? params;
}

/// Núcleo falso: responde con los fixtures reales y deja inyectar resultados, errores y eventos.
class MockCore implements CoreClient {
  MockCore({
    Map<String, Object?> results = const {},
    Map<String, Object?> errors = const {},
    Map<String, Object?> events = const {},
    this.state,
  })  : _results = {...results},
        _errors = {...errors},
        _events = {...events} {
    // Con mapas vacíos los fixtures llegan después (load/lazy) y avisa _loadFrom.
    if (results.isNotEmpty || errors.isNotEmpty || events.isNotEmpty) _applyState();
  }

  /// Carga todos los fixtures de [source]. Con [state], `<clave>.<state>` sustituye a `<clave>`
  /// en resultados y errores, y los eventos `<evento>.<state>` se emiten una vez al primer suscriptor.
  static Future<MockCore> load(FixtureSource source, {String? state}) async {
    final m = MockCore(state: state);
    await m._loadFrom(source);
    return m;
  }

  /// Síncrono para los providers: los fixtures se cargan en segundo plano y la primera llamada los espera.
  factory MockCore.lazy(Future<FixtureSource> Function() source, {String? state}) {
    final m = MockCore(state: state);
    m._ready = source().then(m._loadFrom);
    return m;
  }

  /// Variante de fixtures activa (`--state`), o null.
  final String? state;
  Future<void>? _ready;
  final _seeds = <String, Object?>{};

  void _applyState() {
    final s = state;
    if (s == null) return;
    final suffix = '.$s';
    var used = false;
    void sub(Map<String, Object?> from, Map<String, Object?> into) {
      for (final k in from.keys.toList()) {
        if (!k.endsWith(suffix) || k.length == suffix.length) continue;
        into[k.substring(0, k.length - suffix.length)] = from[k];
        used = true;
      }
    }

    sub(_results, _results);
    sub(_errors, _errors);
    sub(_events, _seeds);
    if (!used) debugPrint('MockCore: el estado "$s" no coincide con ningún fixture.');
  }

  Future<void> _loadFrom(FixtureSource source) async {
    final results = _results, errors = _errors, events = _events;
    final kinds = {'result': results, 'error': errors, 'event': events};
    for (final path in await source.list()) {
      final file = path.split('/').last; // <nombre>.<tipo>.json
      final parts = file.split('.');
      if (parts.length < 3) continue;
      final target = kinds[parts[parts.length - 2]];
      if (target == null) continue;
      target[parts.sublist(0, parts.length - 2).join('.')] =
          json.decode(await source.read(path));
    }
    _applyState();
  }

  final Map<String, Object?> _results;
  final Map<String, Object?> _errors;
  final Map<String, Object?> _events;
  final _handlers = <String, Object? Function(Json params)>{};
  final _failures = <String, CoreError>{};
  final _bus = StreamController<({String name, Object? payload})>.broadcast();

  /// Llamadas recibidas, en orden.
  final calls = <MockCall>[];
  bool isShutdown = false;

  /// Fija el resultado de [method].
  void result(String method, Object? value) {
    _failures.remove(method);
    _results[method] = value;
  }

  /// Calcula el resultado de [method] a partir de los params.
  void handle(String method, Object? Function(Json params) handler) =>
      _handlers[method] = handler;

  /// Hace fallar [method] con [error] (una vez fijado, hasta [result] o [handle]).
  void failWith(String method, CoreError error) => _failures[method] = error;

  /// Hace fallar [method] con su fixture `<method>.error.json`.
  void failWithFixture(String method) {
    final e = _errors[method];
    if (e == null) throw StateError('No hay fixture de error para $method');
    _failures[method] = CoreError.fromJson(e);
  }

  /// Emite un evento con [payload] inventado por el test.
  void emit(String event, Json payload) => _bus.add((name: event, payload: payload));

  /// Emite el payload del fixture `<event>.event.json`.
  void emitFixture(String event) {
    if (!_events.containsKey(event)) throw StateError('No hay fixture de evento para $event');
    _bus.add((name: event, payload: _events[event]));
  }

  @override
  Future<T> call<T>(String method, Object? params, T Function(Json) decode) async {
    await _ready;
    calls.add(MockCall(method, params));
    final failure = _failures[method];
    if (failure != null) throw failure;
    final h = _handlers[method];
    final Object? r;
    if (h != null) {
      r = h(params is Map ? params.cast<String, Object?>() : <String, Object?>{});
    } else if (_results.containsKey(method)) {
      r = _results[method];
    } else {
      throw CoreError('unsupported', 'MockCore sin respuesta para $method.');
    }
    return decode(r is Map ? r.cast<String, Object?>() : (r == null ? {} : {'value': r}));
  }

  @override
  Stream<T> on<T>(String event, T Function(Json) decode) {
    final base = _bus.stream.where((e) => e.name == event).map((e) {
      final p = e.payload;
      return decode(p is Map ? p.cast<String, Object?>() : <String, Object?>{});
    });
    return Stream<T>.multi((c) {
      final sub = base.listen(c.add, onError: c.addError, onDone: c.close);
      c.onCancel = sub.cancel;
      Future<void>(() async {
        await _ready;
        if (!_seeds.containsKey(event)) return;
        final payload = _seeds.remove(event);
        await Future<void>.microtask(() {});
        if (!_bus.isClosed) _bus.add((name: event, payload: payload));
      });
    }, isBroadcast: true);
  }

  @override
  Future<void> shutdown() async {
    if (isShutdown) return;
    isShutdown = true;
    await _bus.close();
  }
}
