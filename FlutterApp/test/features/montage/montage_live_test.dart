import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/montage.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/montage/montage_live_query.dart';
import 'package:toneforge/features/montage/montage_store.dart';

Json fx(String name) =>
    (json.decode(File('../Contract/fixtures/montage/montage.$name.json').readAsStringSync()) as Map).cast<String, Object?>();

const _pid = '00000000-0000-0000-0000-000000000003';
const _take = '00000000-0000-0000-0000-000000000001';

void main() {
  Future<({MockCore core, ProviderContainer c})> opened() async {
    final core = MockCore()
      ..result('montage.open', fx('open.result'))
      ..result('montage.snapCut', fx('snapCut.result'))
      ..result('montage.framingBox', fx('framingBox.framing-follow.result'));
    final c = ProviderContainer(overrides: [coreClientProvider.overrideWithValue(core)]);
    addTearDown(c.dispose);
    c.listen(montageStoreProvider, (_, _) {});
    await c.read(montageStoreProvider.notifier).open(_pid);
    return (core: core, c: c);
  }

  test('snapCut y framingBox devuelven el valor y no emiten estado nuevo', () async {
    final s = await opened();
    var emitted = 0;
    s.c.listen(montageStoreProvider, (_, _) => emitted++);
    final before = s.c.read(montageStoreProvider);
    final store = s.c.read(montageStoreProvider.notifier);

    expect(await store.snapCut('c1', 3.1), closeTo(3.3, 1e-9));
    final r = await store.framingBox(_take, 3, followZoom: 2, followOffset: const MontageOffsetInfo(x: 0.05, y: 0));
    expect(r?.box?.width, closeTo(0.2, 1e-9));
    expect(emitted, 0);
    expect(identical(s.c.read(montageStoreProvider), before), isTrue);
    expect(s.core.calls.last.params, {
      'takeId': _take,
      'time': 3.0,
      'followZoom': 2.0,
      'followOffset': {'x': 0.05, 'y': 0.0},
    });
  });

  test('error de snapCut: devuelve null y deja actionError', () async {
    final s = await opened();
    s.core.failWith('montage.snapCut', const CoreError('not-found', 'sin corte'));
    final store = s.c.read(montageStoreProvider.notifier);
    expect(await store.snapCut('x', 1), isNull);
    expect(s.c.read(montageStoreProvider).actionError?.code, 'not-found');
  });

  test('ráfaga de 10 movimientos: ≤2 peticiones, se aplica la última', () async {
    final gates = <Completer<int>>[];
    final applied = <int>[];
    final q = MontageLiveQuery<int, int>(
      fetch: (a) {
        final c = Completer<int>();
        gates.add(c);
        return c.future.then((_) => a);
      },
      onResult: applied.add,
    );
    for (var i = 1; i <= 10; i++) {
      q.push(i);
    }
    expect(gates.length, 1);
    gates.first.complete(0);
    await Future<void>.delayed(Duration.zero);
    expect(gates.length, 2);
    gates.last.complete(0);
    await Future<void>.delayed(Duration.zero);
    expect(gates.length, 2);
    expect(q.sent, 2);
    expect(applied, [1, 10]);
  });

  test('reset descarta la respuesta en vuelo y lo pendiente', () async {
    final gate = Completer<int>();
    final applied = <int>[];
    final q = MontageLiveQuery<int, int>(fetch: (a) => gate.future, onResult: applied.add);
    q.push(1);
    q.push(2);
    q.reset();
    gate.complete(7);
    await Future<void>.delayed(Duration.zero);
    expect(applied, isEmpty);
    expect(q.sent, 0);
  });
}
