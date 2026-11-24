import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/record.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/record/record_store.dart';

Json fx(String path) =>
    (json.decode(File('../Contract/fixtures/$path.json').readAsStringSync()) as Map).cast<String, Object?>();

Json state(String name) => fx('record/record.state.$name.event');

Json withBlock(Json base, String? reason) {
  final j = Map<String, Object?>.of(base);
  if (reason == null) {
    j.remove('blockReason');
  } else {
    j['blockReason'] = reason;
  }
  return j;
}

({MockCore core, ProviderContainer c}) setup() {
  final core = MockCore()
    ..result('study.open', <String, Object?>{})
    ..result('study.close', <String, Object?>{})
    ..result('record.open', fx('record/record.open.result'))
    ..result('audio.settings', fx('audio/audio.settings.result'))
    ..result('audio.setMeters', fx('audio/audio.setMeters.result'))
    ..result('record.close', <String, Object?>{});
  final c = ProviderContainer(overrides: [coreClientProvider.overrideWithValue(core)]);
  addTearDown(c.dispose);
  c.listen(recordStoreProvider, (_, _) {});
  return (core: core, c: c);
}

Future<void> openIt(MockCore core, ProviderContainer c) async {
  await c.read(recordStoreProvider.notifier).open('p1');
}

RecordState read(ProviderContainer c) => c.read(recordStoreProvider);
RecordStore store(ProviderContainer c) => c.read(recordStoreProvider.notifier);
List<String> methods(MockCore core) => [for (final m in core.calls) m.method];

void main() {
  test('open: record.open + setMeters, calibrationValid de audio.setMeters y de audio.state', () async {
    final s = setup();
    await openIt(s.core, s.c);
    expect(methods(s.core), ['study.open', 'record.open', 'audio.settings', 'audio.setMeters']);
    expect(s.core.calls.first.params, {'projectId': 'p1'});
    expect(read(s.c).opened, isTrue);
    expect(read(s.c).phase, RecordPhase.idle);
    s.core.emit('audio.state', {...fx('audio/audio.state.event'), 'calibrationValid': true});
    await pumpEventQueue();
    expect(read(s.c).calibrationValid, isTrue);
  });

  test('fases idle -> counting(n) -> recording -> finishing -> idle por record.state', () async {
    final s = setup();
    await openIt(s.core, s.c);
    final seen = <(RecordPhase, int?)>[];
    s.c.listen(recordStoreProvider, (_, n) => seen.add((n.phase, n.countBeat)));
    for (final n in ['counting', 'recording', 'finishing', 'idle', 'adjusting']) {
      s.core.emit('record.state', state(n));
      await pumpEventQueue();
    }
    expect(seen.map((e) => e.$1), [
      RecordPhase.counting, RecordPhase.recording, RecordPhase.finishing, RecordPhase.idle, RecordPhase.adjusting,
    ]);
    expect(seen.first.$2, 2);
    expect(seen[1].$2, isNull);
    expect(read(s.c).isBusy, isTrue);
  });

  test('record.position actualiza el tiempo; fuera de open se ignora', () async {
    final s = setup();
    s.core.emit('record.position', fx('record/record.position.event'));
    await pumpEventQueue();
    expect(read(s.c).position, 0);
    await openIt(s.core, s.c);
    s.core.emit('record.position', {'seconds': 12.5, 'playing': true, 'phase': 'recording'});
    await pumpEventQueue();
    expect(read(s.c).position, 12.5);
  });

  test('botón: start en idle, stop en counting y recording, nada en finishing/adjusting', () async {
    final s = setup();
    s.core.handle('record.start', (_) => state('counting'));
    s.core.handle('record.stop', (_) => state('finishing'));
    await openIt(s.core, s.c);
    await store(s.c).toggleTake();
    expect(methods(s.core).last, 'record.start');
    expect(read(s.c).phase, RecordPhase.counting);
    await store(s.c).toggleTake();
    expect(methods(s.core).last, 'record.stop');
    s.core.emit('record.state', state('recording'));
    await pumpEventQueue();
    expect(read(s.c).canStopTake, isTrue);
    await store(s.c).toggleTake();
    expect(s.core.calls.where((m) => m.method == 'record.stop').length, 2);
    final n = s.core.calls.length;
    for (final p in ['finishing', 'adjusting']) {
      s.core.emit('record.state', state(p));
      await pumpEventQueue();
      expect(read(s.c).canPressRecord, isFalse);
      await store(s.c).toggleTake();
    }
    expect(s.core.calls.length, n);
  });

  test('blockReason se refleja y no habilita el botón ni envía start', () async {
    final s = setup();
    await openIt(s.core, s.c);
    s.core.emit('record.state', state('punch-armed-no-marks'));
    await pumpEventQueue();
    expect(read(s.c).blockReason, isNotNull);
    expect(read(s.c).canStartTake, isFalse);
    await store(s.c).startTake();
    expect(methods(s.core), isNot(contains('record.start')));
    expect(read(s.c).showUncalibrated, isFalse);
  });

  test('sin calibrar: aviso solo en reposo y sin bloqueo', () async {
    final s = setup();
    await openIt(s.core, s.c);
    s.core.emit('audio.state', {...fx('audio/audio.state.event'), 'calibrationValid': false});
    await pumpEventQueue();
    expect(read(s.c).showUncalibrated, isTrue);
    s.core.emit('record.state', state('recording'));
    await pumpEventQueue();
    expect(read(s.c).showUncalibrated, isFalse);
  });

  test('errores: busy y record-blocked quedan en error; not-open se ignora; se limpia al acertar', () async {
    final s = setup();
    s.core.handle('record.start', (_) => state('counting'));
    await openIt(s.core, s.c);
    s.core.failWith('record.start', const CoreError('busy', 'Ya hay una toma'));
    await store(s.c).startTake();
    expect(read(s.c).error?.code, 'busy');
    s.core.failWith('record.start', const CoreError('record-blocked', 'Elige una parte.'));
    await store(s.c).startTake();
    expect(read(s.c).error?.code, 'record-blocked');
    s.core.failWith('record.start', const CoreError('not-open', 'x'));
    await store(s.c).startTake();
    expect(read(s.c).error, isNull);
    s.core.handle('record.start', (_) => state('counting'));
    s.core.failWith('record.addPart', const CoreError('busy', 'x'));
    await store(s.c).addPart('Armonía');
    expect(read(s.c).error?.code, 'busy');
    await store(s.c).startTake();
    expect(read(s.c).error, isNull);
  });

  test('punch: la casilla exige tomas; punchReady exige toma elegida y marcas', () async {
    final s = setup();
    await openIt(s.core, s.c);
    expect(read(s.c).canArmPunch, isTrue);
    s.core.emit('record.state', state('punch-armed-no-marks'));
    await pumpEventQueue();
    expect(read(s.c).punchReady, isFalse);
    s.core.emit('record.state', state('punch-armed-marks'));
    await pumpEventQueue();
    expect(read(s.c).punchReady, read(s.c).snapshot!.selectedTakeId != null);
    // Sin tomas en la parte activa: no se envía setPunch.
    final base = fx('record/record.state.base.result');
    final noTakes = Map<String, Object?>.of(base)
      ..['parts'] = [
        for (final p in base['parts'] as List) {...(p as Map).cast<String, Object?>(), 'takes': <Object?>[], 'bestTakeId': null}
      ];
    s.core.emit('record.state', noTakes);
    await pumpEventQueue();
    expect(read(s.c).canArmPunch, isFalse);
    final n = s.core.calls.length;
    await store(s.c).setPunchEnabled(true);
    expect(s.core.calls.length, n);
  });

  test('punch: enabled y marcas viajan como in/out/free; startPunch con takeId', () async {
    final s = setup();
    s.core.handle('record.setPunch', (_) => state('punch-armed-marks'));
    s.core.handle('record.startPunch', (_) => state('counting'));
    await openIt(s.core, s.c);
    await store(s.c).setPunchEnabled(true);
    expect(s.core.calls.last.params, {'enabled': true});
    await store(s.c).setPunchPoints(entry: 10, free: true);
    expect(s.core.calls.last.params, {'in': 10, 'free': true});
    await store(s.c).setPunchPoints(clearOut: true);
    expect(s.core.calls.last.params, {'clearOut': true});
    s.core.emit('record.state', state('idle'));
    await pumpEventQueue();
    await store(s.c).startPunch('t1');
    expect(s.core.calls.last.params, {'takeId': 't1'});
  });

  test('rotateCamera: el núcleo suma 90 módulo 360 y la superficie lo refleja; solo en idle', () async {
    final s = setup();
    s.core.handle('record.rotate', (_) {
      final j = Map<String, Object?>.of(fx('record/record.state.base.result'));
      final cam = Map<String, Object?>.of((j['camera'] as Map).cast<String, Object?>());
      cam['rotation'] = ((cam['rotation'] as int) + 90) % 360;
      return j..['camera'] = cam;
    });
    await openIt(s.core, s.c);
    final before = ((fx('record/record.state.base.result')['camera'] as Map)['rotation'] as int);
    await store(s.c).rotateCamera();
    expect(read(s.c).cameraRotation, (before + 90) % 360);
    expect(read(s.c).cameraFrameSize, const Size(640, 360));
    s.core.emit('record.state', state('recording'));
    await pumpEventQueue();
    final n = s.core.calls.length;
    await store(s.c).rotateCamera();
    expect(s.core.calls.length, n);
  });

  test('cámara sin width/height: sin tamaño de fotograma', () async {
    final s = setup();
    await openIt(s.core, s.c);
    s.core.emit('record.state', state('camera-denied'));
    await pumpEventQueue();
    expect(read(s.c).cameraFrameSize, isNull);
  });

  test('setCountIn, setPreRoll, setStartSection: solo envían lo que cambia', () async {
    final s = setup();
    s.core.handle('record.setCountIn', (_) => fx('record/record.setCountIn.result'));
    s.core.handle('record.setPreRoll', (_) => fx('record/record.setPreRoll.result'));
    s.core.handle('record.setStartSection', (_) => fx('record/record.setStartSection.result'));
    await openIt(s.core, s.c);
    final snap = read(s.c).snapshot!;
    final n = s.core.calls.length;
    await store(s.c).setCountIn(snap.countIn);
    await store(s.c).setPreRoll(snap.preRollBars);
    await store(s.c).setStartSection(snap.startSectionId);
    expect(s.core.calls.length, n);
    await store(s.c).setCountIn(!snap.countIn);
    expect(s.core.calls.last.params, {'on': !snap.countIn});
    await store(s.c).setPreRoll(snap.preRollBars == 1 ? 2 : 1);
    expect(s.core.calls.last.method, 'record.setPreRoll');
    s.core.emit('record.state', {...fx('record/record.state.base.result'), 'startSectionId': 'sec-x'});
    await pumpEventQueue();
    await store(s.c).setStartSection(null);
    expect(s.core.calls.last.params, <String, Object?>{});
  });

  test('partes y tomas: selectPart, selectTake(null), markBest, deleteTake, close limpia', () async {
    final s = setup();
    for (final m in ['selectPart', 'selectTake', 'markBest', 'deleteTake']) {
      s.core.handle('record.$m', (_) => fx('record/record.state.base.result'));
    }
    await openIt(s.core, s.c);
    await store(s.c).selectPart('a');
    expect(s.core.calls.last.params, {'partId': 'a'});
    await store(s.c).selectTake(null);
    expect(s.core.calls.last.params, <String, Object?>{});
    await store(s.c).markBest('t');
    await store(s.c).deleteTake('t');
    expect(methods(s.core).sublist(4), ['record.selectPart', 'record.selectTake', 'record.markBest', 'record.deleteTake']);
    await store(s.c).close();
    expect(read(s.c).opened, isFalse);
    expect(methods(s.core).sublist(methods(s.core).length - 3), ['audio.setMeters', 'record.close', 'study.close']);
  });

  test('salir rumbo a Montaje: no llama a study.close', () async {
    final s = setup();
    await openIt(s.core, s.c);
    final n = s.core.calls.length;
    await store(s.c).close(toMontage: true);
    expect(methods(s.core).sublist(n), ['audio.setMeters', 'record.close']);
    expect(s.core.calls[n].params, {'visible': false});
  });
}
