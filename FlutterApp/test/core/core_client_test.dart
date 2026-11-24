import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/call_timeouts.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/host_services.dart';

class FakeTransport implements CoreTransport {
  // ignore: close_sinks
  final inbox =StreamController<Json>(sync: true);
  final sent = <Json>[];
  List<String>? startedWith;
  int? shutdownMs;
  bool closed = false;

  @override
  Stream<Json> get messages => inbox.stream;
  @override
  void start(List<String> args) => startedWith = args;
  @override
  void send(Json message) => sent.add(message);
  @override
  void shutdown(int timeoutMs) => shutdownMs = timeoutMs;
  @override
  void close() => closed = true;
}

void main() {
  late FakeTransport t;
  late TransportCoreClient c;

  TransportCoreClient make({CallTimeouts timeouts = const CallTimeouts()}) {
    t = FakeTransport();
    final client = TransportCoreClient(t, timeouts: timeouts, host: _Host());
    client.start(['--audio', 'simulated']);
    return client;
  }

  setUp(() {
    c = make();
  });

  test('start pasa los argumentos', () => expect(t.startedWith, ['--audio', 'simulated']));

  test('ids incrementales y respuesta por id', () async {
    final a = c.call('a.one', {'x': 1}, (j) => j['v']);
    final b = c.call('b.two', null, (j) => j['v']);
    expect(t.sent.map((m) => m['id']), [1, 2]);
    expect(t.sent[0]['params'], {'x': 1});
    expect(t.sent[1]['params'], <String, Object?>{});
    t.inbox.add({'id': 2, 'result': {'v': 'B'}});
    t.inbox.add({'id': 1, 'result': {'v': 'A'}});
    expect(await a, 'A');
    expect(await b, 'B');
  });

  test('error tipado con args', () async {
    final f = c.call('x', null, (j) => j);
    t.inbox.add({
      'id': 1,
      'error': {'code': 'bad-params', 'message': 'm', 'args': {'k': 1}},
    });
    await expectLater(
        f,
        throwsA(isA<CoreError>()
            .having((e) => e.code, 'code', 'bad-params')
            .having((e) => e.message, 'message', 'm')
            .having((e) => e.args, 'args', {'k': 1})));
  });

  test('timeout por tabla; la respuesta tardía se descarta', () async {
    c = make(timeouts: const CallTimeouts(overrides: {'slow': Duration(milliseconds: 20)}));
    final f = c.call('slow', null, (j) => j);
    await expectLater(f, throwsA(isA<CoreError>().having((e) => e.code, 'code', 'timeout')));
    final id = t.sent.last['id'];
    t.inbox.add({'id': id, 'result': {}}); // tardía: no debe lanzar
    await Future<void>.delayed(Duration.zero);
  });

  test('sin límite: no vence', () async {
    c = make(timeouts: const CallTimeouts(overrides: {'dlg': null}));
    final f = c.call('dlg', null, (j) => j['v']);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    t.inbox.add({'id': t.sent.last['id'], 'result': {'v': 7}});
    expect(await f, 7);
  });

  test('eventos por nombre', () async {
    final got = <Object?>[];
    final sub = c.on('jobs.progress', (j) => j['fraction']).listen(got.add);
    t.inbox.add({'event': 'other', 'payload': {'fraction': 9}});
    t.inbox.add({'event': 'jobs.progress', 'payload': {'fraction': 0.25}});
    await Future<void>.delayed(Duration.zero);
    expect(got, [0.25]);
    await sub.cancel();
  });

  test('hostRequest se responde con hostResponse', () async {
    t.inbox.add({'hostRequest': {'id': 5, 'method': 'ok', 'params': {}}});
    t.inbox.add({'hostRequest': {'id': 6, 'method': 'boom', 'params': {}}});
    await Future<void>.delayed(Duration.zero);
    expect(t.sent[0], {'hostResponse': {'id': 5, 'result': {'ok': true}}});
    expect(t.sent[1], {
      'hostResponse': {'id': 6, 'error': {'code': 'unsupported', 'message': 'no'}},
    });
  });

  test('shutdown resuelve con core.shutdown y falla las pendientes', () async {
    final pending = c.call('x', null, (j) => j);
    final pendingErr = expectLater(
        pending, throwsA(isA<CoreError>().having((e) => e.code, 'code', 'cancelled')));
    final done = c.shutdown();
    expect(t.shutdownMs, 5000);
    t.inbox.add({'event': 'core.shutdown', 'payload': {'clean': true}});
    await done;
    await pendingErr;
    expect(t.closed, isTrue);
    await expectLater(c.call('y', null, (j) => j), throwsA(isA<CoreError>()));
  });
}

class _Host implements HostServices {
  @override
  Future<Json> handle(String method, Json params) async {
    if (method == 'ok') return {'ok': true};
    throw const HostError('unsupported', 'no');
  }
}
