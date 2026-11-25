import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/record/record_offset_actions.dart';
import 'package:toneforge/features/record/record_store.dart';

Json fx(String path) =>
    (json.decode(File('../Contract/fixtures/$path.json').readAsStringSync()) as Map).cast<String, Object?>();

({MockCore core, ProviderContainer c}) setup() {
  final core = MockCore()
    ..result('study.open', <String, Object?>{})
    ..result('record.open', fx('record/record.open.result'))
    ..result('audio.settings', fx('audio/audio.settings.result'))
    ..result('audio.setMeters', fx('audio/audio.setMeters.result'))
    ..result('record.adjustOffset', fx('record/record.adjustOffset.result'))
    ..result('record.setOffset', fx('record/record.setOffset.result'))
    ..result('record.finishOffset', fx('record/record.state.adjusting.event'));
  final c = ProviderContainer(overrides: [coreClientProvider.overrideWithValue(core)]);
  addTearDown(c.dispose);
  c.listen(recordStoreProvider, (_, _) {});
  return (core: core, c: c);
}

RecordStore store(ProviderContainer c) => c.read(recordStoreProvider.notifier);
List<Object?> paramsOf(MockCore core, String m) => [for (final x in core.calls) if (x.method == m) x.params];

void main() {
  test('adjustOffset envía takeId y el snapshot trae offset', () async {
    final s = setup();
    await store(s.c).open('p1');
    expect(s.c.read(recordStoreProvider).offset, isNull);
    await store(s.c).adjustOffset('t1');
    expect(paramsOf(s.core, 'record.adjustOffset'), [
      {'takeId': 't1'}
    ]);
    final o = s.c.read(recordStoreProvider).offset;
    expect(o, isNotNull);
    expect(s.c.read(recordStoreProvider).isNewOffsetTake, o!.isNew);
  });

  test('setOffset: un cambio se envía tal cual', () async {
    final s = setup();
    await store(s.c).open('p1');
    await store(s.c).setOffset(valueMs: 12.5);
    await store(s.c).setOffset(frames: -1);
    expect(paramsOf(s.core, 'record.setOffset'), [
      {'valueMs': 12.5},
      {'frames': -1},
    ]);
  });

  test('setOffset coalesce: con uno en vuelo solo se envía el último acumulado', () async {
    final s = setup();
    await store(s.c).open('p1');
    final st = store(s.c);
    await Future.wait([
      st.setOffset(deltaMs: 1),
      st.setOffset(deltaMs: 1),
      st.setOffset(deltaMs: 1),
      st.setOffset(valueMs: 10),
    ]);
    expect(paramsOf(s.core, 'record.setOffset'), [
      {'deltaMs': 1},
      {'valueMs': 10},
    ]);
  });

  test('setOffset coalesce: pasos y fotogramas se suman', () async {
    final s = setup();
    await store(s.c).open('p1');
    final st = store(s.c);
    await st.adjustOffset('t1');
    await Future.wait([st.setOffset(frames: 1), st.setOffset(frames: -1), st.setOffset(frames: -1), st.setOffset(deltaMs: 2)]);
    final calls = paramsOf(s.core, 'record.setOffset');
    expect(calls, hasLength(2));
    expect(calls.first, {'frames': 1});
    final frameMs = fx('record/record.setOffset.result')['offset'] == null
        ? 0
        : ((fx('record/record.setOffset.result')['offset']! as Map)['frameMs'] as num);
    expect((calls.last as Map)['deltaMs'], closeTo(-2 * frameMs + 2, 1e-9));
  });

  group('finishOffset', () {
    for (final (save, makeDefault, expected) in [
      (true, true, true),
      (true, false, false),
      (false, true, false),
      (false, false, false),
    ]) {
      test('save=$save makeDefault=$makeDefault envía makeDefault=$expected', () async {
        final s = setup();
        await store(s.c).open('p1');
        await store(s.c).finishOffset(save: save, makeDefault: makeDefault);
        expect(paramsOf(s.core, 'record.finishOffset'), [
          {'save': save, 'makeDefault': expected}
        ]);
      });
    }
  });

  test('error del núcleo en setOffset queda en state.error', () async {
    final s = setup();
    await store(s.c).open('p1');
    s.core.failWith('record.setOffset', const CoreError('busy', 'ocupado'));
    await store(s.c).setOffset(deltaMs: 1);
    expect(s.c.read(recordStoreProvider).error?.code, 'busy');
  });
}
