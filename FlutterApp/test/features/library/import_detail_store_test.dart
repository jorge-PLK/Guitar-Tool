import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/jobs.dart';
import 'package:toneforge/contract/library.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/library/import_store.dart';
import 'package:toneforge/features/library/project_detail_store.dart';

const id1 = '00000000-0000-0000-0000-000000000001';

Json job(String id, String stage, String state, {double? fraction, String? error}) => {
  'id': id,
  'title': 't',
  'stage': stage,
  'state': state,
  'fraction': ?fraction,
  'text': '',
  'error': ?error,
};

Future<(ProviderContainer, MockCore)> setup() async {
  final core = await MockCore.load((await DirectoryFixtureSource.find())!);
  final c = ProviderContainer(overrides: [coreClientProvider.overrideWithValue(core)]);
  addTearDown(c.dispose);
  return (c, core);
}

void main() {
  group('import_store', () {
    test('jobs.list al arrancar y jobs.progress actualizan chip y fila de importación', () async {
      final (c, core) = await setup();
      c.listen(importStoreProvider, (_, _) {});
      await pumpEventQueue();
      expect(c.read(importStoreProvider).jobs[id1]?.state, JobState.running);

      core.emit('jobs.progress', job('import-1', 'import', 'running', fraction: 0.4));
      core.emit('jobs.progress', job('link-2', 'download', 'queued'));
      core.emit('jobs.progress', job('00000000-0000-0000-0000-000000000009', 'separation', 'running'));
      await pumpEventQueue();
      final s = c.read(importStoreProvider);
      expect([for (final j in s.importRows) j.id], ['import-1', 'link-2']);
      expect(s.importRows.first.fraction, 0.4);

      core.emit('jobs.progress', job('import-1', 'import', 'done'));
      await pumpEventQueue();
      expect(c.read(importStoreProvider).importRows.map((j) => j.id), ['link-2']);
    });

    test('el trabajo vivo sobrescribe separationState y el error de failed es el motivo', () async {
      final (c, core) = await setup();
      c.listen(importStoreProvider, (_, _) {});
      await pumpEventQueue();
      final p = ProjectSummary.fromJson({
        ...coreProject(id1),
        'separationState': 'none',
        'separationError': 'viejo',
      });
      expect(c.read(importStoreProvider).separationStateFor(p), SeparationState.running);
      expect(c.read(importStoreProvider).separationFractionFor(id1), 0.25);

      core.emit('jobs.progress', job(id1, 'separation', 'running', fraction: 0.5));
      await pumpEventQueue();
      expect(c.read(importStoreProvider).separationFractionFor(id1), 0.5);

      core.emit('jobs.progress', job(id1, 'separation', 'failed', error: 'Sin memoria'));
      await pumpEventQueue();
      final s = c.read(importStoreProvider);
      expect(s.separationStateFor(p), SeparationState.failed);
      expect(s.separationErrorFor(p), 'Sin memoria');

      core.emit('jobs.progress', job(id1, 'separation', 'done'));
      await pumpEventQueue();
      final s2 = c.read(importStoreProvider);
      expect(s2.separationStateFor(p), SeparationState.none);
      expect(s2.separationErrorFor(p), 'viejo');
    });

    test('importPaths filtra a wav/flac/mp3 y llama import.file una a una en serie', () async {
      final (c, core) = await setup();
      c.listen(importStoreProvider, (_, _) {});
      final gates = <Completer<void>>[];
      core.handle('import.file', (_) => {'id': 'x', 'duplicate': false});
      final st = c.read(importStoreProvider.notifier);
      final done = st.importPaths(['/a/uno.WAV', '/a/nota.txt', '/a/carpeta', '/a/dos.flac', r'C:\m\tres.Mp3']);
      await done;
      expect(gates, isEmpty);
      final paths = [for (final x in core.calls.where((x) => x.method == 'import.file')) (x.params as Map)['path']];
      expect(paths, ['/a/uno.WAV', '/a/dos.flac', r'C:\m\tres.Mp3']);
      expect(c.read(importStoreProvider).importing, isFalse);
    });

    test('la segunda ruta espera a que acabe la primera', () async {
      final (c, core) = await setup();
      c.listen(importStoreProvider, (_, _) {});
      var inFlight = 0, maxInFlight = 0;
      core.handle('import.file', (_) {
        inFlight++;
        maxInFlight = inFlight > maxInFlight ? inFlight : maxInFlight;
        inFlight--;
        return {'id': 'x', 'duplicate': false};
      });
      await c.read(importStoreProvider.notifier).importPaths(['/a.wav', '/b.wav']);
      expect(maxInFlight, 1);
      expect(core.calls.where((x) => x.method == 'import.file').length, 2);
    });

    test('duplicado deja duplicateOf con el id existente', () async {
      final (c, core) = await setup();
      c.listen(importStoreProvider, (_, _) {});
      core.handle('import.file', (_) => {'id': id1, 'duplicate': true});
      await c.read(importStoreProvider.notifier).importPaths(['/a.mp3']);
      expect(c.read(importStoreProvider).duplicateOf, id1);
      c.read(importStoreProvider.notifier).dismissDuplicate();
      expect(c.read(importStoreProvider).duplicateOf, isNull);
    });

    test('un error de import.file pasa a notice y sigue con las demás', () async {
      final (c, core) = await setup();
      c.listen(importStoreProvider, (_, _) {});
      var n = 0;
      core.handle('import.file', (_) {
        if (n++ == 0) throw const CoreError('not-found', 'No existe');
        return {'id': 'x', 'duplicate': false};
      });
      // MockCore propaga excepciones del handler tal cual.
      await c.read(importStoreProvider.notifier).importPaths(['/a.wav', '/b.wav']);
      final s = c.read(importStoreProvider);
      expect(s.notice?.code, 'not-found');
      expect(s.notice?.message, 'No existe');
      expect(core.calls.where((x) => x.method == 'import.file').length, 2);
    });

    test('pickAndImport usa host.pickAudioFiles', () async {
      final (c, core) = await setup();
      c.listen(importStoreProvider, (_, _) {});
      core.result('host.pickAudioFiles', {'paths': ['/p/x.wav', '/p/y.pdf']});
      core.result('import.file', {'id': 'x', 'duplicate': false});
      await c.read(importStoreProvider.notifier).pickAndImport();
      expect(core.calls.where((x) => x.method == 'import.file').length, 1);
    });
  });

  group('project_detail_store', () {
    test('carga library.project y recarga con library.changed', () async {
      final (c, core) = await setup();
      c.listen(projectDetailStoreProvider(id1), (_, _) {});
      await pumpEventQueue();
      expect(c.read(projectDetailStoreProvider(id1)).loaded, isTrue);
      expect(c.read(projectDetailStoreProvider(id1)).detail, isNotNull);
      final n = core.calls.where((x) => x.method == 'library.project').length;
      core.emitFixture('library.changed');
      await pumpEventQueue();
      expect(core.calls.where((x) => x.method == 'library.project').length, n + 1);
    });

    test('deleteTake y markBest recargan el detalle', () async {
      final (c, core) = await setup();
      c.listen(projectDetailStoreProvider(id1), (_, _) {});
      await pumpEventQueue();
      core.result('library.deleteTake', {'removed': true});
      final st = c.read(projectDetailStoreProvider(id1).notifier);
      var n = core.calls.where((x) => x.method == 'library.project').length;
      expect(await st.deleteTake('t1'), isTrue);
      expect(core.calls.where((x) => x.method == 'library.project').length, n + 1);
      n++;
      expect(await st.markBest('t1'), isTrue);
      expect(core.calls.where((x) => x.method == 'library.project').length, n + 1);
      expect((core.calls.firstWhere((x) => x.method == 'library.markBest').params as Map)['takeId'], 't1');
    });

    test('error de toma queda local, no recarga y se limpia', () async {
      final (c, core) = await setup();
      c.listen(projectDetailStoreProvider(id1), (_, _) {});
      await pumpEventQueue();
      core.failWithFixture('library.deleteTake');
      final n = core.calls.where((x) => x.method == 'library.project').length;
      expect(await c.read(projectDetailStoreProvider(id1).notifier).deleteTake('t1'), isFalse);
      expect(c.read(projectDetailStoreProvider(id1)).takeError, isNotNull);
      expect(core.calls.where((x) => x.method == 'library.project').length, n);
      c.read(projectDetailStoreProvider(id1).notifier).clearTakeError();
      expect(c.read(projectDetailStoreProvider(id1)).takeError, isNull);
    });

    test('error de library.project queda en error', () async {
      final (c, core) = await setup();
      core.failWith('library.project', const CoreError('not-found', 'x'));
      c.listen(projectDetailStoreProvider(id1), (_, _) {});
      await pumpEventQueue();
      final s = c.read(projectDetailStoreProvider(id1));
      expect(s.error?.code, 'not-found');
      expect(s.loaded, isTrue);
    });
  });
}

Map<String, Object?> coreProject(String id) => {
  'id': id,
  'title': 'T',
  'folderName': 'T',
  'duration': 1,
  'sampleRate': 44100,
  'createdAt': '2026-01-01T00:00:00Z',
  'updatedAt': '2026-01-01T00:00:00Z',
  'stemCount': 0,
  'takeCount': 0,
  'rigCount': 0,
  'hasAnalysis': false,
  'guitars': <String>[],
};
