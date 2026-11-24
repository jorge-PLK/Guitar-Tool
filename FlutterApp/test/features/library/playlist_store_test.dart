import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/playlist.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/library/playlist_store.dart';

late DirectoryFixtureSource _src;

Future<Json> fixture(String name) async =>
    (json.decode(await _src.read('playlist/$name.json')) as Map).cast<String, Object?>();

/// Snapshot del fixture `playlist.changed.<step>` con cambios de [edit].
Future<Json> snap(String step, [void Function(Json j)? edit]) async {
  final j = await fixture('playlist.changed.$step.event');
  edit?.call(j);
  return j;
}

Future<(ProviderContainer, MockCore)> setup({Json? info}) async {
  _src = (await DirectoryFixtureSource.find())!;
  final core = await MockCore.load(_src);
  if (info != null) {
    final base = (json.decode(await _src.read('app/app.info.result.json')) as Map).cast<String, Object?>();
    core.result('app.info', {...base, 'playlist': info});
  }
  final c = ProviderContainer(overrides: [coreClientProvider.overrideWithValue(core)]);
  addTearDown(c.dispose);
  c.listen(playlistStoreProvider, (_, _) {});
  await pumpEventQueue();
  return (c, core);
}

PlaylistState st(ProviderContainer c) => c.read(playlistStoreProvider);
PlaylistStore store(ProviderContainer c) => c.read(playlistStoreProvider.notifier);

Future<void> emitStep(ProviderContainer c, MockCore core, String step, [void Function(Json)? edit]) async {
  core.emit('playlist.changed', await snap(step, edit));
  await pumpEventQueue();
}

void main() {
  test('arranca sin lista cuando app.info no trae playlist', () async {
    final (c, _) = await setup();
    expect(st(c).snapshot, isNull);
    expect(st(c).indicator, isNull);
    expect(st(c).sheetOpen, isFalse);
    expect(st(c).buttons.showContinue, isFalse);
  });

  test('arranca con app.info.playlist, sin abrir la hoja', () async {
    final (c, _) = await setup(info: await snap('running', (j) => j['indicator'] = 'Importando 1 de 2'));
    expect(st(c).step, PlaylistStep.running);
    expect(st(c).indicator, 'Importando 1 de 2');
    expect(st(c).isLive, isTrue);
    expect(st(c).sheetOpen, isFalse);
  });

  test('un indicador en blanco es null', () async {
    final (c, _) = await setup(info: await snap('running', (j) => j['indicator'] = '  '));
    expect(st(c).indicator, isNull);
  });

  test('adopt pone el snapshot y abre la hoja', () async {
    final (c, _) = await setup();
    store(c).adopt(PlaylistSnapshot.fromJson(await snap('tracks')));
    expect(st(c).step, PlaylistStep.tracks);
    expect(st(c).sheetOpen, isTrue);
    store(c).closeSheet();
    expect(st(c).sheetOpen, isFalse);
    expect(st(c).snapshot, isNotNull);
    store(c).openSheet();
    expect(st(c).sheetOpen, isTrue);
  });

  test('playlist.changed sustituye el snapshot en cada step y no abre la hoja', () async {
    final (c, core) = await setup();
    for (final step in ['loading', 'tracks', 'searching', 'review', 'running', 'stopped', 'summary', 'error']) {
      await emitStep(c, core, step);
      expect(st(c).step?.raw, step, reason: step);
      expect(st(c).sheetOpen, isFalse);
    }
  });

  test('un evento llegado antes que app.info no lo pisa app.info', () async {
    _src = (await DirectoryFixtureSource.find())!;
    final core = await MockCore.load(_src);
    final c = ProviderContainer(overrides: [coreClientProvider.overrideWithValue(core)]);
    addTearDown(c.dispose);
    c.listen(playlistStoreProvider, (_, _) {});
    core.emit('playlist.changed', await snap('summary'));
    await pumpEventQueue();
    expect(st(c).step, PlaylistStep.summary);
  });

  test('select aplica el snapshot de la respuesta y envía los params', () async {
    final (c, core) = await setup();
    core.result('playlist.select', await snap('tracks', (j) => (j['totals'] as Json)['selected'] = 1));
    final e = await store(c).select('3demoDemoDemoDemoDemoA', true);
    expect(e, isNull);
    expect(st(c).tracks?.selected, 1);
    expect(st(c).busy, isFalse);
    final call = core.calls.last;
    expect(call.method, 'playlist.select');
    expect(call.params, {'id': '3demoDemoDemoDemoDemoA', 'selected': true});
  });

  test('choose con in-library expone el error y conserva el snapshot', () async {
    final (c, core) = await setup();
    await emitStep(c, core, 'review');
    core.failWith('playlist.choose', CoreError.fromJson(await fixture('playlist.choose.error.error')));
    final e = await store(c).choose('3demoDemoDemoDemoDemoA', 'x');
    expect(e?.code, 'in-library');
    expect(st(c).error?.code, 'in-library');
    expect(st(c).step, PlaylistStep.review);
    expect(core.calls.last.params, {'id': '3demoDemoDemoDemoDemoA', 'candidateId': 'x'});
  });

  test('select y skip con not-found devuelven el error; una acción buena lo limpia', () async {
    final (c, core) = await setup();
    await emitStep(c, core, 'tracks');
    core.failWith('playlist.select', const CoreError('not-found', 'No está.'));
    expect((await store(c).select('zz', true))?.code, 'not-found');
    core.failWith('playlist.skip', CoreError.fromJson(await fixture('playlist.skip.error.error')));
    expect(await store(c).skip('zz'), isA<CoreError>());
    core.result('playlist.selectAll', await snap('tracks'));
    expect(await store(c).selectAll(), isNull);
    expect(st(c).error, isNull);
  });

  test('no-playlist limpia la lista local y cierra la hoja', () async {
    final (c, core) = await setup();
    store(c).adopt(PlaylistSnapshot.fromJson(await snap('running')));
    core.failWith('playlist.cancel', const CoreError('no-playlist', 'Sin lista.'));
    expect((await store(c).cancel())?.code, 'no-playlist');
    expect(st(c).snapshot, isNull);
    expect(st(c).sheetOpen, isFalse);
  });

  test('cada método del puente llama a su método', () async {
    final (c, core) = await setup();
    final s = store(c);
    await s.selectNone();
    await s.continue_();
    await s.search();
    await s.start();
    await s.cancel();
    await s.resume();
    await s.updateAndRetry();
    await s.retryFailed();
    expect([for (final x in core.calls.where((x) => x.method.startsWith('playlist.'))) x.method], [
      'playlist.selectNone',
      'playlist.continue',
      'playlist.search',
      'playlist.start',
      'playlist.cancel',
      'playlist.resume',
      'playlist.updateAndRetry',
      'playlist.retryFailed',
    ]);
  });

  test('close sin sesión limpia lo local', () async {
    final (c, core) = await setup();
    core.result('playlist.close', {'closed': false, 'live': false});
    final o = await store(c).close();
    expect(o.error, isNull);
    expect(o.result?.closed, isFalse);
    expect(o.result?.live, isFalse);
    expect(st(c).snapshot, isNull);
  });

  test('close con trabajo vivo no cierra; forzado sí', () async {
    final (c, core) = await setup();
    store(c).adopt(PlaylistSnapshot.fromJson(await snap('running', (j) => j['isLive'] = true)));
    core.result('playlist.close', {'closed': false, 'live': true});
    final o = await store(c).close();
    expect(o.result?.live, isTrue);
    expect(st(c).snapshot, isNotNull);
    expect(st(c).sheetOpen, isTrue);
    expect(core.calls.last.params, {'force': false});

    core.result('playlist.close', {'closed': true, 'live': false});
    final f = await store(c).close(force: true);
    expect(f.result?.closed, isTrue);
    expect(core.calls.last.params, {'force': true});
    expect(st(c).snapshot, isNull);
    expect(st(c).sheetOpen, isFalse);
  });

  test('close con error lo devuelve', () async {
    final (c, core) = await setup();
    core.failWith('playlist.close', const CoreError('internal', 'x'));
    final o = await store(c).close();
    expect(o.error?.code, 'internal');
    expect(o.result, isNull);
  });

  test('tracks: recuentos y botones (Spotify busca, YouTube descarga)', () async {
    final (c, core) = await setup();
    await emitStep(c, core, 'tracks');
    expect(st(c).tracks, (total: 3, selected: 0, inLibrary: 0));
    var b = st(c).buttons;
    expect([b.markAll, b.markNone, b.showContinue, b.continueEnabled, b.continueIsSearch], [true, true, true, false, true]);
    await emitStep(c, core, 'tracks', (j) {
      (j['totals'] as Json)['selected'] = 2;
      (j['totals'] as Json)['inLibrary'] = 1;
      j['source'] = 'youtube';
    });
    expect(st(c).tracks, (total: 3, selected: 2, inLibrary: 1));
    b = st(c).buttons;
    expect([b.continueEnabled, b.continueCount, b.continueIsSearch], [true, 2, false]);
  });

  test('searching: progreso con «Buscando X de N» y fracción', () async {
    final (c, core) = await setup();
    await emitStep(c, core, 'searching', (j) {
      j['searchDone'] = 1;
      j['searchTotal'] = 4;
    });
    expect(st(c).search, (current: 2, done: 1, total: 4, fraction: 0.25));
    expect(st(c).buttons.showCancel, isTrue);
  });

  test('review: recuentos, N de Descargar y botón Seguir buscando', () async {
    final (c, core) = await setup();
    await emitStep(c, core, 'review');
    expect(st(c).review, (proposed: 1, doubtful: 1, skipped: 0));
    var b = st(c).buttons;
    expect([b.showStart, b.startEnabled, b.startCount, b.showSearchMore], [true, true, 1, false]);
    expect(st(c).reviewRows.length, 2);
    await emitStep(c, core, 'review', (j) {
      (j['totals'] as Json)['queued'] = 0;
      final items = j['items'] as List;
      (items[2] as Json)['selected'] = true;
    });
    b = st(c).buttons;
    expect([b.startEnabled, b.showSearchMore], [false, true]);
  });

  test('running: hechos de N, cancelar y tooltip de cerrar', () async {
    final (c, core) = await setup();
    await emitStep(c, core, 'running');
    expect(st(c).queue, (done: 0, total: 2));
    final b = st(c).buttons;
    expect([b.showCancel, b.closeKeepsQueue, b.showResume], [true, true, false]);
    expect(st(c).queueRows.length, 2);
  });

  test('stopped: extractor-broken ofrece actualizar; otro motivo, reanudar', () async {
    final (c, core) = await setup();
    await emitStep(c, core, 'stopped');
    var b = st(c).buttons;
    expect([b.showUpdateAndRetry, b.updateEnabled, b.showResume, b.showCancel], [true, true, false, false]);
    await emitStep(c, core, 'stopped', (j) => (j['update'] as Json)['updating'] = true);
    expect(st(c).buttons.updateEnabled, isFalse);
    await emitStep(c, core, 'stopped', (j) => (j['update'] as Json)['alreadyLatest'] = true);
    expect(st(c).buttons.showUpdateAndRetry, isFalse);
    await emitStep(c, core, 'stopped', (j) => (j['error'] as Json)['suggestsUpdate'] = false);
    b = st(c).buttons;
    expect([b.showUpdateAndRetry, b.showResume, b.resumeCount], [false, true, null]);
  });

  test('summary: cuatro cifras, Reanudar (N) solo si cancelada y Reintentar fallidos (N)', () async {
    final (c, core) = await setup();
    await emitStep(c, core, 'summary');
    expect(st(c).summary, (imported: 2, skipped: 0, inLibrary: 0, failed: 0));
    var b = st(c).buttons;
    expect([b.showResume, b.showRetryFailed], [false, false]);
    await emitStep(c, core, 'summary', (j) {
      (j['summary'] as Json)
        ..['cancelled'] = true
        ..['remaining'] = 3
        ..['failed'] = 1;
      ((j['items'] as List)[2] as Json)['status'] = 'failed';
    });
    b = st(c).buttons;
    expect([b.showResume, b.resumeCount, b.showRetryFailed, b.retryFailedCount], [true, 3, true, 1]);
    expect(st(c).summary?.failed, 1);
    expect(st(c).failedRows.length, 1);
  });

  test('error: solo «Probar con otro enlace»', () async {
    final (c, core) = await setup();
    await emitStep(c, core, 'error');
    final b = st(c).buttons;
    expect([b.showTryAnother, b.showCancel, b.showContinue], [true, false, false]);
  });
}
