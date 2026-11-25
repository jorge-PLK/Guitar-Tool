import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/record/record_store.dart';

Json fx(String path) =>
    (json.decode(File('../Contract/fixtures/$path.json').readAsStringSync()) as Map).cast<String, Object?>();

MockCore core0() => MockCore()
  ..result('study.open', <String, Object?>{})
  ..result('study.close', <String, Object?>{})
  ..result('audio.settings', fx('audio/audio.settings.result'))
  ..result('audio.setMeters', fx('audio/audio.setMeters.result'))
  ..result('record.close', <String, Object?>{});

ProviderContainer container(MockCore core) {
  final c = ProviderContainer(overrides: [coreClientProvider.overrideWithValue(core)]);
  addTearDown(c.dispose);
  c.listen(recordStoreProvider, (_, _) {});
  return c;
}

void main() {
  test('record.open con un snapshot indecodificable: estado de error, no cargando', () async {
    final bad = fx('record/record.open.result')..remove('audio');
    final core = core0()..result('record.open', bad);
    final c = container(core);
    await c.read(recordStoreProvider.notifier).open('p1');
    final s = c.read(recordStoreProvider);
    expect(s.opened, isFalse);
    expect(s.snapshot, isNull);
    expect(s.error, isNotNull);
    expect(s.error!.code, 'internal');
    expect(s.error!.message, isNotEmpty);
  });

  test('record.open con cámara sin opcionales abre normalmente', () async {
    final j = fx('record/record.open.result');
    j['camera'] = {'state': 'none', 'rotation': 0, 'cameras': <Object?>[]};
    final core = core0()..result('record.open', j);
    final c = container(core);
    await c.read(recordStoreProvider.notifier).open('p1');
    expect(c.read(recordStoreProvider).opened, isTrue);
    expect(c.read(recordStoreProvider).error, isNull);
  });

  test('record.state mal formado se ignora y el stream sigue vivo', () async {
    final core = core0()..result('record.open', fx('record/record.open.result'));
    final c = container(core);
    await c.read(recordStoreProvider.notifier).open('p1');
    final before = c.read(recordStoreProvider).snapshot;
    core.emit('record.state', <String, Object?>{'title': 1});
    await pumpEventQueue();
    expect(c.read(recordStoreProvider).snapshot, same(before));
    core.emit('record.state', fx('record/record.state.counting.event'));
    await pumpEventQueue();
    expect(c.read(recordStoreProvider).snapshot, isNot(same(before)));
  });
}
