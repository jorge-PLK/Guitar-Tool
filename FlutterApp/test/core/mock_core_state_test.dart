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

void main() {
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
