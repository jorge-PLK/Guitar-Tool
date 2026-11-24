import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/record/mixer_store.dart';
import 'package:toneforge/features/record/record_store.dart';

Json fx(String path) =>
    (json.decode(File('../Contract/fixtures/$path.json').readAsStringSync()) as Map).cast<String, Object?>();

Future<(MockCore, ProviderContainer)> setup() async {
  final core = MockCore()
    ..result('study.open', <String, Object?>{})
    ..result('audio.settings', fx('audio/audio.settings.result'))
    ..result('record.open', fx('record/record.open.result'))
    ..result('audio.setMeters', fx('audio/audio.setMeters.result'))
    ..handle('record.setMaster', (p) {
      final j = Map<String, Object?>.of(fx('record/record.state.base.result'));
      final mix = Map<String, Object?>.of((j['mix'] as Map).cast<String, Object?>())..['masterGainDB'] = p['gainDB'];
      return j..['mix'] = mix;
    })
    ..result('record.setMix', fx('record/record.setMix.result'));
  final c = ProviderContainer(overrides: [coreClientProvider.overrideWithValue(core)]);
  addTearDown(c.dispose);
  c.listen(recordStoreProvider, (_, _) {});
  c.listen(mixerStoreProvider, (_, _) {});
  await c.read(recordStoreProvider.notifier).open('p1');
  return (core, c);
}

MixerState mix(ProviderContainer c) => c.read(mixerStoreProvider);
MixerStore store(ProviderContainer c) => c.read(mixerStoreProvider.notifier);

void main() {
  test('refleja el mix del snapshot y los niveles de record.levels', () async {
    final (core, c) = await setup();
    store(c); // crea el store
    await pumpEventQueue();
    final fxMix = (fx('record/record.open.result')['mix'] as Map).cast<String, Object?>();
    expect(mix(c).masterGainDB, fxMix['masterGainDB']);
    expect(mix(c).channels, isNotEmpty);
    core.emit('record.levels', fx('record/record.levels.event'));
    await pumpEventQueue();
    expect(mix(c).levels, isNotEmpty);
  });

  test('setMaster: imán a 0 dB por debajo de 1,5 y rango -60..+6', () async {
    final (core, c) = await setup();
    final s = store(c);
    final sent = <num>[];
    for (final v in [1.4, -1.4, 1.5, -1.6, 10, -99, 0.2]) {
      await s.setMaster(v);
      sent.add((core.calls.last.params! as Map)['gainDB'] as num);
    }
    expect(sent, [0, 0, 1.5, -1.6, 6, -60, 0]);
    expect(mix(c).masterGainDB, 0);
    expect(c.read(recordStoreProvider).snapshot!.mix.masterGainDB, 0);
  });

  test('setMaster: error revierte al valor del núcleo y not-open se silencia', () async {
    final (core, c) = await setup();
    final before = mix(c).masterGainDB;
    core.failWith('record.setMaster', const CoreError('busy', 'x'));
    await store(c).setMaster(-20);
    expect(mix(c).masterGainDB, before);
    expect(mix(c).error?.code, 'busy');
    core.failWith('record.setMaster', const CoreError('not-open', 'x'));
    await store(c).setMaster(-20);
    expect(mix(c).error, isNull);
  });

  test('setGain acota; solo y mute envían el canal; forcedMuted no actúa', () async {
    final (core, c) = await setup();
    final ch = mix(c).channels.first;
    await store(c).setGain(ch.id, 30);
    expect(core.calls.last.params, {'channel': ch.id, 'gainDB': 6.0});
    await store(c).setMute(ch.id, true);
    expect(core.calls.last.params, {'channel': ch.id, 'mute': true});
    await store(c).setSolo(ch.id, true);
    expect(core.calls.last.params, {'channel': ch.id, 'solo': true});
    // Canal forzado a silencio (la guitarra que sustituye la parte).
    final base = fx('record/record.state.base.result');
    final m = Map<String, Object?>.of((base['mix'] as Map).cast<String, Object?>());
    m['channels'] = [
      for (final x in m['channels'] as List) {...(x as Map).cast<String, Object?>(), 'forcedMuted': true},
    ];
    core.emit('record.state', {...base, 'mix': m});
    await pumpEventQueue();
    final n = core.calls.length;
    await store(c).setMute(ch.id, false);
    await store(c).setSolo(ch.id, false);
    expect(core.calls.length, n);
  });

  test('setMix con error deja el error y no cambia el mix', () async {
    final (core, c) = await setup();
    final ch = mix(c).channels.first;
    core.failWith('record.setMix', const CoreError('internal', 'boom'));
    await store(c).setMute(ch.id, true);
    expect(mix(c).error?.code, 'internal');
    expect(mix(c).channels.first.muted, ch.muted);
  });
}
