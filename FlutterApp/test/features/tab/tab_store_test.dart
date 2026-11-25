import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/tab.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/tab/tab_store.dart';

import 'tab_test_support.dart';

Future<(MockCore, ProviderContainerHandle)> boot({String? project = projectId}) async {
  final core = await loadCore();
  final c = makeContainer(core, project: project);
  c.listen(tabStoreProvider, (_, _) {});
  await settle();
  return (core, ProviderContainerHandle(c));
}

void main() {
  setUpAll(findFixtures);

  List<String> methods(MockCore c) => [for (final m in c.calls) m.method];

  test('sin proyecto de estudio no abre la tablatura', () async {
    final (core, h) = await boot(project: null);
    expect(methods(core), isEmpty);
    expect(h.state.tab, isNull);
    expect(h.state.projectId, isNull);
  });

  test('con proyecto de estudio llama a tab.open y refleja el estado', () async {
    final (core, h) = await boot();
    expect(methods(core), ['tab.open']);
    expect((core.calls.single.params as Map)['projectId'], projectId);
    expect(h.state.tab!.phase, TabPhase.ready);
    expect(h.state.opening, isFalse);
    expect(h.state.projectId, projectId);
  });

  test('tab.open con error deja el error y ninguna tablatura', () async {
    final core = await loadCore();
    core.failWith('tab.open', const CoreError('internal', 'fallo'));
    final c = makeContainer(core);
    c.listen(tabStoreProvider, (_, _) {});
    await settle();
    final s = c.read(tabStoreProvider);
    expect(s.error!.code, 'internal');
    expect(s.tab, isNull);
    expect(s.opening, isFalse);
  });

  test('al cambiar o cerrar el estudio cierra la tablatura y abre la nueva', () async {
    final (core, h) = await boot();
    h.container.read(studyProjectProbe.notifier).set('otro');
    await settle();
    expect(methods(core), ['tab.open', 'tab.close', 'tab.open']);
    expect((core.calls.last.params as Map)['projectId'], 'otro');
    h.container.read(studyProjectProbe.notifier).set(null);
    await settle();
    expect(methods(core).last, 'tab.close');
    expect(h.state.tab, isNull);
    expect(h.state.projectId, isNull);
  });

  test('tab.state sustituye el estado; el de otro proyecto se ignora', () async {
    final (core, h) = await boot();
    core.emit('tab.state', {...fixture('tab.open.result.json'), 'revision': 4});
    await settle();
    expect(h.state.tab!.revision, 4);
    core.emit('tab.state',
        {...fixture('tab.open.result.json'), 'revision': 9, 'projectId': 'ajeno'});
    await settle();
    expect(h.state.tab!.revision, 4);
  });

  test('tab.progress: transcribing, failed con error y done/cancelled lo quitan', () async {
    final (core, h) = await boot();
    core.emitFixture('tab.progress');
    await settle();
    expect(h.state.progress['bass']!.fraction, closeTo(0.4, 1e-9));
    core.emit('tab.progress', fixture('tab.progress.event.failed.json'));
    await settle();
    expect(h.state.progress['bass']!.error, isNotNull);
    core.emit('tab.progress', fixture('tab.progress.event.done.json'));
    await settle();
    expect(h.state.progress, isEmpty);
  });

  test('tab.selection y tab.range; -1 = sin selección / sin tramo', () async {
    final (core, h) = await boot();
    core.emit('tab.selection', fixture('tab.selection.event.json'));
    core.emit('tab.range', fixture('tab.range.event.json'));
    await settle();
    expect(h.state.selection!.bar, 2);
    expect(h.state.range, isNotNull);
    core.emit('tab.selection', fixture('tab.selection.event.none.json'));
    core.emit('tab.range', fixture('tab.range.event.none.json'));
    await settle();
    expect(h.state.selection, isNull);
    expect(h.state.range, isNull);
  });

  testWidgets('el flash de tab.state dura 3 s', (tester) async {
    // El contenedor se crea dentro de la zona falsa para que el Timer del flash sea el del test.
    final core = (await tester.runAsync(loadCore))!;
    final h = ProviderContainerHandle(makeContainer(core));
    h.container.listen(tabStoreProvider, (_, _) {});
    await tester.pump();
    core.emit('tab.state', {...fixture('tab.open.result.json'), 'flash': 'Guardado X.gp.'});
    await tester.pump();
    expect(h.state.flash, 'Guardado X.gp.');
    await tester.pump(const Duration(milliseconds: 2900));
    expect(h.state.flash, 'Guardado X.gp.');
    await tester.pump(const Duration(milliseconds: 200));
    expect(h.state.flash, isNull);
  });

  test('dismissNotices llama al núcleo y aplica el TabState devuelto', () async {
    final (core, h) = await boot();
    core.emit('tab.state', {
      ...fixture('tab.open.result.json'),
      'notices': ['uno'],
    });
    await settle();
    expect(h.state.notices, ['uno']);
    final t = await h.notifier.dismissNotices();
    expect(core.calls.last.method, 'tab.dismissNotices');
    expect(core.calls.last.params, isEmpty);
    expect(t!.notices, isEmpty);
    expect(h.state.notices, isEmpty);
    core.emit('tab.state', {
      ...fixture('tab.open.result.json'),
      'notices': ['uno'],
    });
    await settle();
    expect(h.state.notices, ['uno']);
  });

  test('dismissNotices sin tablatura abierta deja el error not-open', () async {
    final (core, h) = await boot();
    core.failWith('tab.dismissNotices', const CoreError('not-open', 'sin tab'));
    expect(await h.notifier.dismissNotices(), isNull);
    expect(h.state.error!.code, 'not-open');
  });

  test('span clear con keepAnchor envía el parámetro', () async {
    final (core, h) = await boot();
    await h.notifier.span(TabSpanAction.clear, keepAnchor: true);
    expect(core.calls.last.params, {'action': 'clear', 'keepAnchor': true});
    await h.notifier.span(TabSpanAction.clear);
    expect(core.calls.last.params, {'action': 'clear'});
  });

  test('cada intención llama a su método con sus parámetros', () async {
    final (core, h) = await boot();
    final n = h.notifier;
    final state = fixture('tab.open.result.json');
    for (final m in [
      'tab.setSource', 'tab.selectTrack', 'tab.beatClick', 'tab.beatDrag', 'tab.noteClick',
      'tab.select', 'tab.span', 'tab.toggleMute', 'tab.toggleSolo', 'tab.setListening',
      'tab.setAllListening', 'tab.edit', 'tab.state',
    ]) {
      core.result(m, state);
    }
    core.calls.clear();
    await n.setSource(TabSource.automatic);
    await n.selectTrack('bass');
    await n.beatClick(const TabClickParams(track: 0, bar: 1, beat: 2, shift: true));
    await n.beatDrag(const TabClickParams(track: 0, bar: 1, beat: 3));
    await n.noteClick(const TabClickParams(track: 0, bar: 1, beat: 2, string: 4));
    await n.select(const TabSelectParams(track: 'bass', beat: 1, tick: 0));
    await n.span(TabSpanAction.extendBack);
    await n.toggleMute('bass');
    await n.toggleSolo('drums');
    await n.setListening('bass', on: true);
    await n.setAllListening(on: false);
    await n.edit(TabEditParams.digit(5));
    await n.setEditMode(on: true);
    await n.refresh();
    expect(methods(core), [
      'tab.setSource', 'tab.selectTrack', 'tab.beatClick', 'tab.beatDrag', 'tab.noteClick',
      'tab.select', 'tab.span', 'tab.toggleMute', 'tab.toggleSolo', 'tab.setListening',
      'tab.setAllListening', 'tab.edit', 'tab.edit', 'tab.state',
    ]);
    Map p(int i) => core.calls[i].params! as Map;
    expect(p(0), {'source': 'automatic'});
    expect(p(1), {'track': 'bass'});
    expect(p(2), {'track': 0, 'bar': 1, 'beat': 2, 'shift': true});
    expect(p(5)['tick'], 0);
    expect(p(6), {'action': 'extendBack'});
    expect(p(9), {'track': 'bass', 'on': true});
    expect(p(10), {'on': false});
    expect(p(11)['op'], 'digit');
    expect(p(12), {'op': 'editMode', 'on': true});
  });

  test('transcribe, cancel y score', () async {
    final (core, h) = await boot();
    // tab.open ya encola la transcripción; transcribe(track) reencola solo esa pista.
    final q = await h.notifier.transcribe(track: 'bass');
    expect(q!.queued, ['bass']);
    expect(core.calls.last.params, {'track': 'bass'});
    expect(await h.notifier.cancel(), isFalse);
    final s = await h.notifier.score(track: 'bass');
    expect(h.state.score!.revision, s!.revision);
    expect((core.calls.last.params as Map)['track'], 'bass');
  });

  test('exportName y export con la ruta de la interfaz', () async {
    final (core, h) = await boot();
    expect(await h.notifier.loadExportName(), 'Banda - Tema.gp');
    expect(h.state.exportName, 'Banda - Tema.gp');
    final r = await h.notifier.export(data: 'AAAA', path: '/x/tema.gp');
    expect(r!.saved, isTrue);
    expect(core.calls.last.params, {'data': 'AAAA', 'path': '/x/tema.gp'});
    expect(h.state.exporting, isFalse);
  });

  test('un error de llamada queda en el estado y clearError lo borra', () async {
    final (core, h) = await boot();
    core.failWithFixture('tab.state');
    expect(await h.notifier.refresh(), isNull);
    expect(h.state.error!.code, 'not-open');
    core.failWith('tab.export', const CoreError('not-ready', 'no listo'));
    expect(await h.notifier.export(data: 'x', path: '/p'), isNull);
    expect(h.state.error!.code, 'not-ready');
    expect(h.state.exporting, isFalse);
    h.notifier.clearError();
    expect(h.state.error, isNull);
  });

  test('tab.edit con op key devuelve handled', () async {
    final (core, h) = await boot();
    core.result('tab.edit', {...fixture('tab.open.result.json'), 'handled': true});
    final t = await h.notifier.edit(TabEditParams.key(key: 'z', ctrl: true));
    expect(t!.handled, isTrue);
  });
}
