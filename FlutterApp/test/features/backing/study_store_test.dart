import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/study.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/launch_options.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/backing/study_position.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/shell/selected_project.dart';

const _a = '00000000-0000-0000-0000-00000000000a';
const _b = '00000000-0000-0000-0000-00000000000b';

late MockCore core;
late ProviderContainer c;
late Json openJson;

Future<void> pump() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> setup({String? project = _a}) async {
  final src = (await DirectoryFixtureSource.find())!;
  core = await MockCore.load(src);
  final path = (await src.list()).firstWhere((p) => p.endsWith('study.open.result.json'));
  openJson = (json.decode(await src.read(path)) as Map).cast<String, Object?>();
  c = ProviderContainer(overrides: [
    coreClientProvider.overrideWithValue(core),
    launchOptionsProvider.overrideWithValue(const LaunchOptions()),
  ]);
  addTearDown(c.dispose);
  if (project != null) c.read(selectedProjectProvider.notifier).select(project);
  c.listen(studyStoreProvider, (_, _) {});
  c.listen(studyPositionProvider, (_, _) {});
  await pump();
}

StudyStoreState get st => c.read(studyStoreProvider);
StudyStore get store => c.read(studyStoreProvider.notifier);
List<String> get methods => [for (final m in core.calls) m.method];
Json paramsOf(String method) => (core.calls.lastWhere((m) => m.method == method).params! as Map).cast();

void main() {
  test('abre el estudio del proyecto elegido', () async {
    await setup();
    expect(st.status, StudyLoadStatus.open);
    expect(st.openProjectId, isNotNull);
    expect(st.study!.title, isNotEmpty);
    expect(methods, ['study.open']);
    expect(paramsOf('study.open'), {'projectId': _a});
  });

  test('sin proyecto no abre nada', () async {
    await setup(project: null);
    expect(st.status, StudyLoadStatus.idle);
    expect(st.openProjectId, isNull);
    expect(core.calls, isEmpty);
  });

  test('error de apertura deja status error con el error del núcleo y retryOpen reabre', () async {
    final src = (await DirectoryFixtureSource.find())!;
    core = await MockCore.load(src);
    core.failWith('study.open', const CoreError('not-found', 'No existe'));
    c = ProviderContainer(overrides: [
      coreClientProvider.overrideWithValue(core),
      launchOptionsProvider.overrideWithValue(const LaunchOptions()),
    ]);
    addTearDown(c.dispose);
    c.read(selectedProjectProvider.notifier).select(_a);
    c.listen(studyStoreProvider, (_, _) {});
    await pump();
    expect(st.status, StudyLoadStatus.error);
    expect(st.error!.code, 'not-found');
    expect(st.openProjectId, isNull);
    core.result('study.open', openJson);
    await store.retryOpen();
    expect(st.status, StudyLoadStatus.open);
    expect(st.error, isNull);
  });

  test('study.state actualiza el transporte', () async {
    await setup();
    final t = Map<String, Object?>.of((openJson['transport']! as Map).cast());
    t['rate'] = 1.5;
    t['playing'] = true;
    core.emit('study.state', t);
    await pump();
    expect(st.transport!.rate, 1.5);
    expect(st.transport!.playing, isTrue);
  });

  test('study.analysis guarda el evento y con ready relee el snapshot', () async {
    await setup();
    core.emit('study.analysis', {'state': 'analyzing'});
    await pump();
    expect(st.analysisEvent!.state, StudyAnalysisState.analyzing);
    expect(methods, isNot(contains('study.snapshot')));
    core.emit('study.analysis', {'state': 'ready'});
    await pump();
    expect(st.analysisEvent!.state, StudyAnalysisState.ready);
    expect(methods, contains('study.snapshot'));
  });

  test('study.analysis con analysis sustituye el análisis sin snapshot', () async {
    await setup();
    final src = (await DirectoryFixtureSource.find())!;
    core.emit(
      'study.analysis',
      (json.decode(await src.read('study/study.analysis.event.withChords.json')) as Map)
          .cast<String, Object?>(),
    );
    await pump();
    expect(st.study!.analysis.chords.first.display, 'A#m');
    expect(st.study!.analysis.key.display!.tonic, 'A#');
    expect(st.analysisEvent!.analysis, isNotNull);
    expect(methods, isNot(contains('study.snapshot')));
  });

  test('setKeyShown envía shown y chordShape devuelve la forma', () async {
    await setup();
    await store.setKeyShown(const StudyShownKey(tonic: 'G', mode: 'min'));
    expect(paramsOf('study.setKey'), {
      'shown': {'tonic': 'G', 'mode': 'min'},
    });
    final r = await store.chordShape(15, capo: 3);
    expect(paramsOf('study.chordShape'), {'index': 15, 'capo': 3});
    expect(r!.display, 'B');
    expect(r.shape!.barre, isNotNull);
  });

  test('study.guitars guarda el evento y relee el snapshot', () async {
    await setup();
    core.emitFixture('study.guitars');
    await pump();
    expect(st.guitarsEvent, isNotNull);
    expect(methods, contains('study.snapshot'));
  });

  test('un error de llamada deja el error y no cambia el estado; not-open se ignora', () async {
    await setup();
    core.failWith('study.play', const CoreError('load-failed', 'Sin stems'));
    await store.play();
    expect(st.status, StudyLoadStatus.open);
    expect(st.error!.code, 'load-failed');
    core.failWith('study.pause', const CoreError('not-open', 'x'));
    store.clearError();
    await store.pause();
    expect(st.error, isNull);
    core.result('study.seek', openJson['transport']);
    await store.seek(3);
    expect(st.error, isNull);
    expect(paramsOf('study.seek'), {'seconds': 3.0});
  });

  test('edición: markSection aplica el estado y devuelve el id nuevo', () async {
    await setup();
    final added = await store.markSection(1, 2, snap: StudySnap.bar);
    expect(methods.last, 'study.markSection');
    expect(paramsOf('study.markSection'), {'start': 1.0, 'end': 2.0, 'snap': 'bar'});
    expect(added, isNotNull);
    expect(st.study!.sections.any((s) => s.id == added), isTrue);
  });

  test('cambiar de proyecto cierra y reabre', () async {
    await setup();
    c.read(selectedProjectProvider.notifier).select(_b);
    await pump();
    expect(methods, ['study.open', 'study.close', 'study.open']);
    expect(paramsOf('study.open'), {'projectId': _b});
    expect(st.status, StudyLoadStatus.open);
    c.read(selectedProjectProvider.notifier).select(null);
    await pump();
    expect(methods.last, 'study.close');
    expect(st.status, StudyLoadStatus.idle);
  });

  test('al disponerse cierra el estudio', () async {
    await setup();
    c.dispose();
    await pump();
    expect(methods.last, 'study.close');
  });

  test('Sin guitarras manda un setMix mute por guitarra y la segunda pulsación restaura', () async {
    await setup();
    final t = Map<String, Object?>.of((openJson['transport']! as Map).cast());
    final chans = [for (final ch in t['channels']! as List) Map<String, Object?>.of((ch as Map).cast())];
    t['channels'] = chans;
    core.handle('study.setMix', (p) {
      for (final ch in chans) {
        if (ch['id'] == p['channel']) ch['muted'] = p['mute'];
      }
      return t;
    });
    await store.toggleNoGuitars();
    var mixes = core.calls.where((m) => m.method == 'study.setMix').map((m) => m.params).toList();
    expect(mixes, [
      {'channel': 'guitar_L', 'mute': true},
      {'channel': 'guitar_R', 'mute': true},
    ]);
    await store.toggleNoGuitars();
    mixes = core.calls.where((m) => m.method == 'study.setMix').map((m) => m.params).toList();
    expect(mixes.sublist(2), [
      {'channel': 'guitar_L', 'mute': false},
      {'channel': 'guitar_R', 'mute': false},
    ]);
  });

  test('setLoop manda snap y name; clearLoop manda {}', () async {
    await setup();
    core.result('study.setLoop', openJson['transport']);
    await store.setLoop(1, 4, name: 'Estribillo', snap: StudySnap.bar);
    expect(paramsOf('study.setLoop'), {'start': 1.0, 'end': 4.0, 'name': 'Estribillo', 'snap': 'bar'});
    await store.clearLoop();
    expect(paramsOf('study.setLoop'), <String, Object?>{});
  });

  test('setMetronome no manda gainDB; setTranspose solo lo que cambia', () async {
    await setup();
    core.result('study.setMetronome', openJson['transport']);
    core.result('study.setTranspose', openJson['transport']);
    await store.setMetronome(true);
    expect(paramsOf('study.setMetronome'), {'on': true});
    await store.setTranspose(fineCents: 20);
    expect(paramsOf('study.setTranspose'), {'fineCents': 20.0});
  });

  test('study.position llega al provider aparte', () async {
    await setup();
    core.emitFixture('study.position');
    await pump();
    expect(c.read(studyPositionProvider).playing, isTrue);
    final before = st;
    core.emit('study.position', {'seconds': 7.5, 'playing': true});
    await pump();
    expect(c.read(studyPositionProvider).seconds, 7.5);
    expect(identical(st, before), isTrue);
  });
}
