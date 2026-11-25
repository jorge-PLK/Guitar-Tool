import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/mock_core.dart';

MockCore _core({String? state}) => MockCore(
      state: state,
      results: {
        'takeview.open': {'v': 'base'},
        'takeview.open.no-video': {'v': 'novideo'},
      },
      errors: {
        'a.b': {'code': 'base', 'message': 'm'},
        'a.b.broken': {'code': 'broken', 'message': 'm'},
      },
      events: {
        'record.state': {'s': 'base'},
        'record.state.counting': {'s': 'counting'},
      },
    );

class _MemorySource implements FixtureSource {
  _MemorySource(this.files);
  final Map<String, String> files;

  @override
  Future<List<String>> list() async => files.keys.toList();

  @override
  Future<String> read(String path) async => files[path]!;
}

void main() {
  group('fixtures con estado antes o después del tipo', () {
    final source = _MemorySource({
      'x.do.result.json': '{"v":"base"}',
      'x.do.result.missing.json': '{"v":"missing"}',
      'x.ev.event.missing.json': '{"s":"seed"}',
      'x.do.params.missing.json': 'no es json',
    });

    test('sin state: resultado base; variante y params no se aplican', () async {
      final c = await MockCore.load(source);
      expect(await c.call('x.do', null, (j) => j['v']), 'base');
    });

    test('state missing: variante sustituye al base y el evento se siembra al primer suscriptor', () async {
      final c = await MockCore.load(source, state: 'missing');
      expect(await c.call('x.do', null, (j) => j['v']), 'missing');
      final a = <Object?>[];
      final sub = c.on('x.ev', (j) => j['s']).listen(a.add);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(a, ['seed']);
      await sub.cancel();
    });
  });

  test('resultado sustituido por <metodo>.<state>', () async {
    final c = _core(state: 'no-video');
    final r = await c.call('takeview.open', null, (j) => j['v']);
    expect(r, 'novideo');
  });

  test('error sustituido por <metodo>.<state>', () {
    final c = _core(state: 'broken')..failWithFixture('a.b');
    expect(
      c.call('a.b', null, (j) => j),
      throwsA(isA<CoreError>().having((e) => e.code, 'code', 'broken')),
    );
  });

  test('evento sembrado al primer suscriptor, no al segundo', () async {
    final c = _core(state: 'counting');
    final a = <Object?>[];
    final sub = c.on('record.state', (j) => j['s']).listen(a.add);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(a, ['counting']);
    final b = <Object?>[];
    final sub2 = c.on('record.state', (j) => j['s']).listen(b.add);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(b, isEmpty);
    expect(a, ['counting']);
    await sub.cancel();
    await sub2.cancel();
  });

  test('state null no cambia nada', () async {
    final c = _core();
    expect(await c.call('takeview.open', null, (j) => j['v']), 'base');
    final a = <Object?>[];
    final sub = c.on('record.state', (j) => j['s']).listen(a.add);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(a, isEmpty);
    await sub.cancel();
  });

  testWidgets('state null no deja temporizadores pendientes al suscribirse', (_) async {
    final c = _core();
    final sub = c.on('record.state', (j) => j['s']).listen((_) {});
    unawaited(sub.cancel());
  });

  test('estado sin claves avisa con debugPrint', () {
    final logs = <String?>[];
    final old = debugPrint;
    debugPrint = (m, {wrapWidth}) => logs.add(m);
    addTearDown(() => debugPrint = old);
    _core(state: 'nada');
    expect(logs.single, contains('nada'));
  });
}
