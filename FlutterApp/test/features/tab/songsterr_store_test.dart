import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/tab.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/tab/songsterr_store.dart';
import 'package:toneforge/features/tab/tab_store.dart';

import 'tab_test_support.dart';

Future<(MockCore, ProviderContainerHandle)> boot() async {
  final core = await loadCore();
  final c = makeContainer(core);
  c.listen(tabStoreProvider, (_, _) {});
  c.listen(songsterrStoreProvider, (_, _) {});
  await settle();
  return (core, ProviderContainerHandle(c));
}

void main() {
  setUpAll(findFixtures);

  SongsterrStoreState sheet(ProviderContainerHandle h) => h.container.read(songsterrStoreProvider);
  SongsterrStore store(ProviderContainerHandle h) =>
      h.container.read(songsterrStoreProvider.notifier);

  test('estado inicial: sin hoja, etapa choosing', () async {
    final (_, h) = await boot();
    expect(sheet(h).sheet, isNull);
    expect(sheet(h).isOpen, isFalse);
    expect(sheet(h).stage, TabSongsterrStage.choosing);
  });

  test('open refleja la hoja y el evento tab.songsterr.state la actualiza', () async {
    final (core, h) = await boot();
    final s = await store(h).open();
    expect(s!.open, isTrue);
    expect(sheet(h).isOpen, isTrue);
    expect(core.calls.last.method, 'tab.songsterr.open');
    core.emit('tab.songsterr.state', fixture('tab.songsterr.state.result.results.json'));
    await settle();
    expect(sheet(h).sheet!.results, isNotEmpty);
  });

  test('flujo choosing -> working -> pairing -> accept', () async {
    final (core, h) = await boot();
    final n = store(h);
    await n.open();
    await n.select(7);
    expect((core.calls.last.params as Map)['songId'], 7);
    await n.link('https://www.songsterr.com/a/wsa/x-tab-s1');
    expect((core.calls.last.params as Map)['link'], startsWith('https://'));

    core.result('tab.songsterr.use', fixture('tab.songsterr.use.result.working.json'));
    await n.use();
    expect(sheet(h).stage, TabSongsterrStage.working);
    expect(sheet(h).sheet!.workingText, isNotNull);

    core.emit('tab.songsterr.state', fixture('tab.songsterr.state.result.pairing.json'));
    await settle();
    expect(sheet(h).stage, TabSongsterrStage.pairing);
    expect(sheet(h).sheet!.pairing, isNotNull);

    await n.assign(const SongsterrAssignParams(stemId: 'bass', track: 1));
    expect(core.calls.last.params, {'stemId': 'bass', 'track': 1});
    await n.allAutomatic();
    expect(core.calls.last.method, 'tab.songsterr.allAutomatic');

    core.result('tab.songsterr.accept', {...fixture('tab.songsterr.accept.result.json'), 'revision': 5});
    final t = await n.accept();
    expect(t!.revision, 5);
    expect(sheet(h).isOpen, isFalse);
    expect(sheet(h).sheet, isNull);
    expect(h.state.tab!.revision, 5);
  });

  test('automatic cierra la hoja y pasa el estado a Tablatura', () async {
    final (core, h) = await boot();
    await store(h).open();
    core.result('tab.songsterr.automatic', {...fixture('tab.songsterr.accept.result.json'), 'revision': 7});
    await store(h).automatic();
    expect(sheet(h).sheet, isNull);
    expect(h.state.tab!.revision, 7);
  });

  test('cancelar: close deja la hoja cerrada; back vuelve a choosing', () async {
    final (core, h) = await boot();
    final n = store(h);
    await n.open();
    core.emit('tab.songsterr.state', fixture('tab.songsterr.state.result.pairing.json'));
    await settle();
    await n.back();
    expect(sheet(h).stage, TabSongsterrStage.choosing);
    await n.close();
    expect(sheet(h).isOpen, isFalse);
    expect(core.calls.last.method, 'tab.songsterr.close');
  });

  test('failed: retryImport y review llaman a su método', () async {
    final (core, h) = await boot();
    core.emit('tab.songsterr.state', {
      ...fixture('tab.songsterr.state.result.searchFailed.json'),
      'stage': 'failed',
      'failure': {'kind': 'other', 'message': 'No se pudo leer.', 'canRetry': true},
    });
    await settle();
    expect(sheet(h).stage, TabSongsterrStage.failed);
    expect(sheet(h).sheet!.failure, isNotNull);
    await store(h).retryImport();
    await store(h).review();
    await store(h).retry();
    await store(h).search();
    await store(h).refresh();
    expect([for (final c in core.calls.skip(1)) c.method], [
      'tab.songsterr.retryImport',
      'tab.songsterr.review',
      'tab.songsterr.retry',
      'tab.songsterr.search',
      'tab.songsterr.state',
    ]);
  });

  test('error de llamada: queda en el estado, la hoja no cambia; accept fallido no cierra', () async {
    final (core, h) = await boot();
    await store(h).open();
    core.failWithFixture('tab.songsterr.retry');
    expect(await store(h).retry(), isNull);
    expect(sheet(h).error!.code, 'not-open');
    expect(sheet(h).isOpen, isTrue);
    core.failWith('tab.songsterr.accept', const CoreError('not-ready', 'no'));
    expect(await store(h).accept(), isNull);
    expect(sheet(h).error!.code, 'not-ready');
    expect(sheet(h).isOpen, isTrue);
    store(h).clearError();
    expect(sheet(h).error, isNull);
  });
}
