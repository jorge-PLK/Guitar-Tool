import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/library.dart';
import 'package:toneforge/contract/montage.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/library/library_store.dart';
import 'package:toneforge/features/montage/montage_store.dart';

Json fx(String name) =>
    (json.decode(File('../Contract/fixtures/montage/montage.$name.json').readAsStringSync()) as Map).cast<String, Object?>();

const _pid = '00000000-0000-0000-0000-000000000003';

class _FakeLibrary extends LibraryStore {
  @override
  LibraryState build() => LibraryState(
        projectsFolder: '/Users/x/Projects',
        entries: [
          ProjectSummary.fromJson({
            'id': _pid,
            'title': 'Tema',
            'folderName': 'Tema-abc',
            'duration': 10,
            'sampleRate': 48000,
            'createdAt': 'x',
            'updatedAt': 'x',
            'separationState': 'done',
            'stemCount': 1,
            'takeCount': 2,
            'rigCount': 0,
            'hasAnalysis': false,
            'guitars': <String>[],
          }),
          ProjectSummary.fromJson({
            'id': 'sin-tomas',
            'title': 'A',
            'folderName': 'A',
            'duration': 10,
            'sampleRate': 48000,
            'createdAt': 'x',
            'updatedAt': 'x',
            'separationState': 'done',
            'stemCount': 1,
            'takeCount': 0,
            'rigCount': 0,
            'hasAnalysis': false,
            'guitars': <String>[],
          }),
        ],
      );
}

({MockCore core, ProviderContainer c}) setup() {
  final core = MockCore()
    ..result('montage.open', fx('open.result'))
    ..result('montage.close', <String, Object?>{})
    ..result('montage.seek', fx('open.result'))
    ..result('montage.play', fx('open.result'))
    ..result('montage.addCut', fx('addCut.result'))
    ..result('montage.framingFrame', fx('framingFrame.result'))
    ..result('montage.reveal', fx('reveal.ok.result'));
  final c = ProviderContainer(overrides: [
    coreClientProvider.overrideWithValue(core),
    libraryStoreProvider.overrideWith(_FakeLibrary.new),
  ]);
  addTearDown(c.dispose);
  c.listen(montageStoreProvider, (_, _) {});
  c.listen(montagePositionProvider, (_, _) {});
  return (core: core, c: c);
}

MontageState read(ProviderContainer c) => c.read(montageStoreProvider);
MontageStore store(ProviderContainer c) => c.read(montageStoreProvider.notifier);
int seekCalls(MockCore core) => core.calls.where((m) => m.method == 'montage.seek').length;

Future<({MockCore core, ProviderContainer c})> opened() async {
  final s = setup();
  await store(s.c).open(_pid);
  return s;
}

void main() {
  test('estado inicial sin tema; open llama a montage.open y mapea el snapshot', () async {
    final s = setup();
    expect(read(s.c).status, MontageStatus.noSong);
    final f = store(s.c).open(_pid);
    expect(read(s.c).status, MontageStatus.loading);
    await f;
    expect(s.core.calls.first.method, 'montage.open');
    expect(s.core.calls.first.params, {'projectId': _pid});
    final st = read(s.c);
    expect(st.status, MontageStatus.ready);
    expect(st.snapshot!.projectId, _pid);
    expect(st.canvasLabel, '1920 × 1080');
    expect(st.isPortrait, isFalse);
    expect(st.formatVisible, isTrue);
    expect(st.hasTakes, isTrue);
    expect(st.span!.start, 2);
    expect(s.c.read(montagePositionProvider).seconds, 2);
  });

  test('montage.state sustituye el snapshot; el de otro tema se ignora', () async {
    final s = await opened();
    s.core.emit('montage.state', {...fx('open.result'), 'layout': 'grid'});
    await pumpEventQueue();
    expect(read(s.c).snapshot!.layout, 'grid');
    s.core.emit('montage.state', {...fx('open.result'), 'layout': 'stack', 'projectId': 'otro'});
    await pumpEventQueue();
    expect(read(s.c).snapshot!.layout, 'grid');
  });

  test('montage.position no reconstruye el snapshot ni el estado', () async {
    final s = await opened();
    final before = read(s.c);
    var stateBuilds = 0;
    var posBuilds = 0;
    s.c.listen(montageStoreProvider, (_, _) => stateBuilds++);
    s.c.listen(montagePositionProvider, (_, _) => posBuilds++);
    for (var i = 0; i < 5; i++) {
      s.core.emit('montage.position', {'seconds': 2.5 + i, 'videoSeconds': 0.5 + i, 'playing': true});
    }
    await pumpEventQueue();
    expect(identical(read(s.c).snapshot, before.snapshot), isTrue);
    expect(identical(read(s.c), before), isTrue);
    expect(stateBuilds, 0);
    expect(posBuilds, 5);
    expect(s.c.read(montagePositionProvider).seconds, 6.5);
    expect(s.c.read(montagePositionProvider).playing, isTrue);
  });

  test('export: running, done, failed y cancelled -> idle (MO1)', () async {
    final s = await opened();
    s.core.emit('montage.export', fx('export.running.event'));
    await pumpEventQueue();
    expect(read(s.c).export.phase, MontageExportPhase.running);
    expect(read(s.c).export.stage, 'Codificando el vídeo');
    expect(read(s.c).export.progress, closeTo(0.4, 1e-9));
    expect(read(s.c).exportRunning, isTrue);
    expect(read(s.c).exportEnabled, isFalse);
    s.core.emit('montage.export', fx('export.done.event'));
    await pumpEventQueue();
    expect(read(s.c).export.phase, MontageExportPhase.done);
    expect(read(s.c).export.result, isNotNull);
    s.core.emit('montage.export', fx('export.failed.event'));
    await pumpEventQueue();
    expect(read(s.c).export.phase, MontageExportPhase.failed);
    expect(read(s.c).export.message, isNotNull);
    s.core.emit('montage.export', fx('export.cancelled.event'));
    await pumpEventQueue();
    expect(read(s.c).export.phase, MontageExportPhase.idle);
    expect(read(s.c).exportLive!.phase, MontageExportPhase.cancelled);
  });

  test('framing: analyzing -> isAnalyzing y exportEnabled; ready lo libera', () async {
    final s = setup();
    s.core.result('montage.open', {...fx('open.result'), 'isAnalyzing': false});
    await store(s.c).open(_pid);
    expect(read(s.c).isAnalyzing, isFalse);
    expect(read(s.c).exportEnabled, isTrue);
    s.core.emit('montage.framing', fx('framing.analyzing.event'));
    await pumpEventQueue();
    final id = fx('framing.analyzing.event')['takeId']! as String;
    expect(read(s.c).framingStatus(id), MontageFramingStatus.analyzing);
    expect(read(s.c).framingProgress(id), 0.5);
    expect(read(s.c).isAnalyzing, isTrue);
    expect(read(s.c).exportEnabled, isFalse);
    s.core.emit('montage.framing', fx('framing.ready.event'));
    await pumpEventQueue();
    expect(read(s.c).isAnalyzing, isFalse);
    expect(read(s.c).exportEnabled, isTrue);
  });

  test('exportEnabled exige tomas con vídeo', () async {
    final s = setup();
    s.core.result('montage.open', {...fx('open.result'), 'isAnalyzing': false, 'hasVideo': false});
    await store(s.c).open(_pid);
    expect(read(s.c).exportEnabled, isFalse);
  });

  testWidgets('seek: acota a span y limita el envío a uno cada 120 ms más el final', (tester) async {
    final s = setup();
    final n = store(s.c);
    unawaited(n.open(_pid));
    await tester.pump();
    // Span 2...5. 11 movimientos en ~300 ms (cada 27 ms).
    for (var i = 0; i < 11; i++) {
      n.seek(1.0 + i * 0.5);
      await tester.pump(const Duration(milliseconds: 27));
    }
    expect(seekCalls(s.core), inInclusiveRange(2, 4));
    final seeks = <double>[
      for (final m in s.core.calls)
        if (m.method == 'montage.seek') ((m.params! as Map<String, Object?>)['seconds']! as num).toDouble(),
    ];
    expect(seeks.first, 2.0, reason: 'el primero sale al momento y acotado');
    expect(seeks.every((v) => v >= 2 && v <= 5), isTrue);
    final before = seekCalls(s.core);
    n.seek(99);
    n.seekEnd();
    await tester.pump();
    expect(seekCalls(s.core), before + 1);
    expect((s.core.calls.last.params! as Map<String, Object?>)['seconds'], 5.0);
    expect(s.c.read(montagePositionProvider).seconds, 5.0);
    await tester.pump(const Duration(seconds: 1));
    expect(seekCalls(s.core), before + 1, reason: 'sin envíos extra tras el final');
  });

  test('framingFrame resuelve la ruta relativa contra la carpeta del tema', () async {
    final s = await opened();
    final f = await store(s.c).framingFrame('t1', 3);
    expect(f!.themeFolder, '/Users/x/Projects/Tema-abc');
    expect(f.result.path, startsWith('cache/montage/'));
    expect(f.absolutePath, '/Users/x/Projects/Tema-abc/${f.result.path}');
    expect(s.core.calls.last.params, {'takeId': 't1', 'time': 3});
  });

  test('addCut devuelve el cutId y aplica el snapshot', () async {
    final s = await opened();
    final id = await store(s.c).addCut(3);
    expect(id, fx('addCut.result')['cutId']);
    expect(read(s.c).actionError, isNull);
  });

  test('error de open: estado error; reintentar; error de acción en actionError; not-open se ignora', () async {
    final s = setup();
    s.core.failWith('montage.open', const CoreError('no-takes', 'Sin tomas'));
    await store(s.c).open(_pid);
    expect(read(s.c).status, MontageStatus.error);
    expect(read(s.c).loadError!.code, 'no-takes');
    s.core.result('montage.open', fx('open.result'));
    await store(s.c).retry();
    expect(read(s.c).status, MontageStatus.ready);
    expect(read(s.c).loadError, isNull);

    s.core.failWith('montage.play', const CoreError('audio-unavailable', 'Sin audio'));
    expect(await store(s.c).play(), isFalse);
    expect(read(s.c).actionError!.code, 'audio-unavailable');
    expect(read(s.c).status, MontageStatus.ready);
    s.core.failWith('montage.play', const CoreError('not-open', 'x'));
    await store(s.c).play();
    expect(read(s.c).actionError, isNull);
    s.core.failWith('montage.reveal', const CoreError('boom', 'x'));
    expect(await store(s.c).reveal(), isFalse);
    expect(read(s.c).actionError!.code, 'boom');
  });

  test('close vuelve a sin tema; temas con tomas desde Biblioteca', () async {
    final s = await opened();
    await store(s.c).close();
    expect(read(s.c).status, MontageStatus.noSong);
    expect(s.core.calls.last.method, 'montage.close');
    expect([for (final p in s.c.read(montageSongsProvider)) p.id], [_pid]);
  });

  test('joinPath y clampToSpan', () {
    expect(joinPath('/a/b/', 'c/d.png', windows: false), '/a/b/c/d.png');
    expect(joinPath(r'C:\a', 'c/d.png', windows: true), r'C:\a\c\d.png');
    const span = MontageRangeInfo(start: 2, end: 5);
    expect(clampToSpan(1, span), 2);
    expect(clampToSpan(9, span), 5);
    expect(clampToSpan(3, span), 3);
  });
}
