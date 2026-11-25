import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/study.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/backing/study_position.dart';
import 'package:toneforge/features/tab/tab_canvas_controller.dart';
import 'package:toneforge/features/tab/tab_header.dart';
import 'package:toneforge/features/tab/tab_shortcuts.dart' show WebKey, tabWebKeysProvider;
import 'package:toneforge/features/tab/tab_store.dart';

import '../../../support/fake_web_view.dart';
import '../tab_test_support.dart';

class PosProbe extends StudyPositionNotifier {
  @override
  StudyPositionEvent build() => const StudyPositionEvent(seconds: 0, playing: false);
  void set(StudyPositionEvent e) => state = e;
}

class Rig {
  Rig(this.core, this.container, this.web);
  final MockCore core;
  final ProviderContainer container;
  final FakeWebViewController web;

  List<String> get js => [for (final c in web.calls) if (c.startsWith('run:')) c.substring(4)];
  List<String> get methods => [for (final c in core.calls) c.method];
  int count(String method) => methods.where((m) => m == method).length;
  void msg(Map<String, Object?> m) => web.simulateMessage(m);

  /// `tab.state` con las pistas listas y la pista visible `bass`.
  Future<void> state({int revision = 1}) async {
    final base = fixture('tab.open.result.json');
    core.emit('tab.state', {
      ...base,
      'revision': revision,
      'selectedTrack': 'bass',
      'tracks': [
        for (final t in (base['tracks'] as List).cast<Map<String, Object?>>()) {...t, 'transcription': 'ready'},
      ],
    });
    await settle();
  }

  void position(double s, {bool playing = false}) =>
      (container.read(studyPositionProvider.notifier) as PosProbe).set(StudyPositionEvent(seconds: s, playing: playing));
}

Future<Rig> boot({bool ready = true}) async {
  final core = await loadCore();
  final factory = FakeWebViewFactory();
  final container = ProviderContainer(
    overrides: [
      coreClientProvider.overrideWithValue(core),
      tabStudyProjectProvider.overrideWith((ref) => projectId),
      factory.override,
      tabCanvasHtmlPathProvider.overrideWithValue('/x/tab.html'),
      studyPositionProvider.overrideWith(PosProbe.new),
    ],
  );
  addTearDown(container.dispose);
  container.listen(tabStoreProvider, (_, _) {});
  container.listen(tabCanvasProvider, (_, _) {});
  await settle();
  final rig = Rig(core, container, factory.created.single);
  if (ready) {
    rig.msg({'event': 'ready', 'alphaTab': 'object'});
    await settle();
  }
  return rig;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(findFixtures);

  test('el mensaje key de la página llega al canal de atajos', () async {
    final r = await boot();
    final got = <WebKey>[];
    final sub = r.container.read(tabWebKeysProvider).stream.listen(got.add);
    addTearDown(sub.cancel);
    r.msg({'event': 'key', 'key': ' ', 'code': 'Space', 'shift': false, 'meta': true});
    await settle();
    expect(got.single.key, ' ');
    expect(got.single.code, 'Space');
    expect(got.single.meta, isTrue);
    expect(got.single.shift, isFalse);
  });

  test('ready + tab.state cargan la partitura una sola vez (TF.load)', () async {
    final r = await boot();
    await r.state();
    await settle();
    expect(r.js.where((j) => j.startsWith('TF.load(')).length, 1);
  });

  test('carga tab.html del paquete', () async {
    final r = await boot(ready: false);
    expect(r.web.calls.first, 'loadFile:/x/tab.html');
  });

  test('ready no carga nada sin pistas listas; con pistas listas pide tab.score y hace load', () async {
    final r = await boot();
    expect(r.count('tab.score'), 0);
    await r.state();
    expect(r.count('tab.score'), 1);
    expect(r.js.where((j) => j.startsWith('TF.load(')).length, 1);
    expect(r.js.last, matches(RegExp(r'^TF\.load\(".*", \d+\);$')));
  });

  test('revision nueva recarga; la misma no', () async {
    final r = await boot();
    await r.state();
    await r.state();
    expect(r.count('tab.score'), 1);
    await r.state(revision: 2);
    expect(r.count('tab.score'), 2);
    expect(r.js.where((j) => j.startsWith('TF.load(')).length, 2);
  });

  test('mensajes reenviados: beatClick, noteClick sin fret y noteClick con shift descartado', () async {
    final r = await boot();
    r.msg({'event': 'beatClick', 'track': 0, 'bar': 2, 'beat': 1, 'shift': true});
    r.msg({'event': 'noteClick', 'track': 0, 'bar': 2, 'beat': 1, 'string': 3, 'fret': 7, 'shift': false});
    r.msg({'event': 'noteClick', 'track': 0, 'bar': 2, 'beat': 1, 'string': 3, 'fret': 7, 'shift': true});
    r.msg({'event': 'cursor', 'bar': 1, 'x': 3, 'y': 4});
    await settle();
    expect(r.methods.where((m) => m.startsWith('tab.beat') || m.startsWith('tab.note')), ['tab.beatClick', 'tab.noteClick']);
    final click = r.core.calls.firstWhere((c) => c.method == 'tab.beatClick').params as Map;
    expect(click, {'track': 0, 'bar': 2, 'beat': 1, 'shift': true});
    final note = r.core.calls.firstWhere((c) => c.method == 'tab.noteClick').params as Map;
    expect(note.containsKey('fret'), isFalse);
    expect(note['string'], 3);
  });

  test('beatDrag: una petición viva y gana la última', () async {
    final r = await boot();
    for (var b = 0; b < 5; b++) {
      r.msg({'event': 'beatDrag', 'track': 0, 'bar': 1, 'beat': b});
    }
    await settle();
    final beats = [
      for (final c in r.core.calls) if (c.method == 'tab.beatDrag') (c.params as Map)['beat'],
    ];
    expect(beats, [0, 4]);
  });

  test('error de la página y de carga quedan en webError; rendered lo borra', () async {
    final r = await boot();
    r.msg({'event': 'error', 'message': 'alphaTab: fallo'});
    expect(r.container.read(tabCanvasProvider).webError, 'alphaTab: fallo');
    r.msg({'event': 'rendered'});
    expect(r.container.read(tabCanvasProvider).webError, isNull);
    expect(r.container.read(tabCanvasProvider).rendered, isTrue);
    r.web.simulateRawMessage('no json');
    expect(r.container.read(tabCanvasProvider).webError, contains('no JSON'));
  });

  test('cursor: solo se llama al lienzo si la hora cambia y tras rendered', () async {
    final r = await boot();
    r.position(1.0);
    expect(r.js.where((j) => j.startsWith('TF.setCursorTime')), isEmpty);
    r.msg({'event': 'rendered'});
    expect(r.js.where((j) => j.startsWith('TF.setCursorTime')), ['TF.setCursorTime(1.0, true);']);
    r.position(1.0);
    expect(r.js.where((j) => j.startsWith('TF.setCursorTime')).length, 1);
    r.position(2.5);
    expect(r.js.last, 'TF.setCursorTime(2.5, true);');
  });

  test('tab.selection y tab.range llegan al lienzo; sin selección = -1', () async {
    final r = await boot();
    r.core.emit('tab.selection', {'bar': 3, 'fraction': 0.5});
    await settle();
    expect(r.js, contains('TF.setSelection(3, 0.5);'));
    r.core.emit('tab.selection', {'bar': -1, 'fraction': 0});
    await settle();
    expect(r.js.last, 'TF.setSelection(-1, 0);');
    r.core.emit('tab.range', {'startBar': 1, 'startFraction': 0.0, 'endBar': 2, 'endFraction': 0.5});
    await settle();
    expect(r.js.last, 'TF.setRange(1, 0.0, 2, 0.5);');
  });

  test('export devuelve el base64 del lienzo; sin lienzo, null', () async {
    final r = await boot();
    r.web.evalResults['TF.exportGpBase64({})'] = 'UEsDBA==';
    expect(await r.container.read(tabCanvasProvider.notifier).exportGpBase64(), 'UEsDBA==');
    expect(await r.container.read(tabExportDataProvider)!(), 'UEsDBA==');
    r.web.evalResults['TF.exportGpBase64({})'] = null;
    expect(await r.container.read(tabCanvasProvider.notifier).exportGpBase64(), isNull);
  });

  testWidgets('cursor en reproducción: interpola entre eventos', (tester) async {
    late Rig r;
    await tester.runAsync(() async => r = await boot());
    r.msg({'event': 'rendered'});
    r.position(1.0, playing: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    final times = r.js.where((j) => j.startsWith('TF.setCursorTime')).toList();
    expect(times.length, greaterThan(1));
    expect(times.last, isNot(times.first));
    r.position(1.2, playing: false);
    await tester.pump(const Duration(milliseconds: 50));
    expect(r.js.last, 'TF.setCursorTime(1.2, true);');
    final n = r.js.length;
    await tester.pump(const Duration(milliseconds: 100));
    expect(r.js.length, n);
  });
}
