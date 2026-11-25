import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/study.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/launch_options.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/features/backing/widgets/chord_grid.dart';
import 'package:toneforge/features/backing/widgets/chords_area.dart';
import 'package:toneforge/features/backing/widgets/section_boxes.dart';
import 'package:toneforge/features/backing/widgets/section_edge_drag.dart';
import 'package:toneforge/features/backing/widgets/section_selection.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/selected_project.dart';
import 'package:toneforge/theme/tokens.dart';

import '../../../support/harness.dart';
import '../chords/chords_support.dart';

const String intro = '00000000-0000-0000-0000-000000000003';
const String solo = '00000000-0000-0000-0000-000000000004';

class _Rig {
  _Rig(this.core, this.container);
  final MockCore core;
  final ProviderContainer container;

  List<MockCall> calls(String m) => core.calls.where((MockCall c) => c.method == m).toList();
}

Json _json(StudySectionInfo s, {double? start}) => <String, Object?>{
      'id': s.id,
      'name': s.name,
      'start': start ?? s.start,
      'end': s.end,
      'solo': s.solo,
      'color': s.color,
      'paletteIndex': s.paletteIndex,
    }..removeWhere((String k, Object? v) => v == null);

Future<_Rig> _pump(WidgetTester tester, {required bool grid}) async {
  await tester.runAsync(loadTfFonts);
  final MockCore core = (await tester.runAsync(() async => MockCore.load((await DirectoryFixtureSource.find())!)))!;
  final Json open = (await tester.runAsync(openFixture))!;
  fourChords(open);
  final Json a = (open['analysis']! as Map).cast<String, Object?>();
  a['beats'] = <Object?>[for (int i = 0; i < 8; i++) i.toDouble()];
  a['bpm'] = 60.0;
  core.result('study.open', open);
  setTestSurface(tester, const Size(1100, 400));
  final ProviderContainer container = ProviderContainer(overrides: [
    coreClientProvider.overrideWithValue(core),
    launchOptionsProvider.overrideWithValue(const LaunchOptions()),
  ]);
  addTearDown(container.dispose);
  container.read(selectedProjectProvider.notifier).select(separatedId);
  container.read(studyStoreProvider);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: WidgetsApp(
        color: TfColors.bg,
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        debugShowCheckedModeBanner: false,
        pageRouteBuilder: <T>(RouteSettings s, WidgetBuilder b) => PageRouteBuilder<T>(
          settings: s,
          pageBuilder: (BuildContext c, Animation<double> a, Animation<double> b2) => b(c),
        ),
        home: Align(
          alignment: Alignment.topLeft,
          child: grid
              ? const ChordGrid(sectionsLayer: gridSectionBoxes)
              : const ChordsArea(sectionsLayer: stripSectionBoxes),
        ),
      ),
    ),
  );
  await settleFrames(tester);
  final _Rig rig = _Rig(core, container);
  // Vista previa del núcleo: el borde de inicio de la sección pedida se mueve a `to`.
  core.handle('study.previewSectionEdge', (Json p) => <String, Object?>{
        'sections': <Object?>[
          for (final StudySectionInfo s in container.read(studyStoreProvider).study!.sections)
            _json(s, start: s.id == p['id'] && p['start'] == true ? (p['to']! as num).toDouble() : null),
        ],
      });
  return rig;
}

final Finder _start = find.byKey(const ValueKey<String>('section-edge-start'));
final Finder _end = find.byKey(const ValueKey<String>('section-edge-end'));

class _Linear implements EdgeTimeMapper {
  @override
  double? timeAt(Offset p) => p.dx / 10;
}

void main() {
  for (final bool grid in <bool>[false, true]) {
    final String kind = grid ? 'rejilla' : 'tira';
    testWidgets('$kind: solo la sección seleccionada muestra dos asas', (tester) async {
      final _Rig r = await _pump(tester, grid: grid);
      expect(_start, findsNothing);
      expect(_end, findsNothing);
      r.container.read(sectionSelectionProvider.notifier).select(intro);
      await settleFrames(tester);
      expect(_start, findsOneWidget);
      expect(_end, findsOneWidget);
      expect(tester.getSize(_start).width, 16);
      r.container.read(sectionSelectionProvider.notifier).select(solo);
      await settleFrames(tester);
      expect(_start, findsOneWidget);
      expect(_end, findsOneWidget);
      r.container.read(sectionSelectionProvider.notifier).clear();
      await settleFrames(tester);
      expect(_start, findsNothing);
    });
  }

  testWidgets('arrastre: vista previa con snap chord y con Alt snap bar; las cajas usan la vista previa',
      (tester) async {
    final _Rig r = await _pump(tester, grid: false);
    r.container.read(sectionSelectionProvider.notifier).select(solo);
    await settleFrames(tester);
    final Offset from = tester.getCenter(_end);
    final TestGesture g = await tester.startGesture(from);
    await g.moveBy(const Offset(-30, 0));
    await settleFrames(tester);
    List<MockCall> p = r.calls('study.previewSectionEdge');
    expect(p, isNotEmpty);
    expect((p.last.params! as Map)['snap'], 'chord');
    expect((p.last.params! as Map)['start'], false);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await g.moveBy(const Offset(-10, 0));
    await settleFrames(tester);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    p = r.calls('study.previewSectionEdge');
    expect((p.last.params! as Map)['snap'], 'bar');
    await g.cancel();
  });

  testWidgets('arrastrar fuera y volver al punto de agarre deja el borde donde estaba (ancla)', (tester) async {
    final _Rig r = await _pump(tester, grid: false);
    r.container.read(sectionSelectionProvider.notifier).select(solo);
    await settleFrames(tester);
    final StudySectionInfo s = r.container.read(studyStoreProvider).study!.sections.firstWhere((e) => e.id == solo);
    final Offset from = tester.getCenter(_start) + const Offset(5, 0);
    final TestGesture g = await tester.startGesture(from);
    await g.moveBy(const Offset(12, 0));
    await g.moveBy(const Offset(-12, 0));
    await settleFrames(tester);
    final Map last = r.calls('study.previewSectionEdge').last.params! as Map;
    expect((last['to']! as num).toDouble(), closeTo(s.start, 0.001));
    await g.up();
    await settleFrames(tester);
  });

  testWidgets('soltar llama a updateSection y limpia la vista previa; cancelar no llama', (tester) async {
    final _Rig r = await _pump(tester, grid: false);
    r.container.read(sectionSelectionProvider.notifier).select(solo);
    await settleFrames(tester);
    TestGesture g = await tester.startGesture(tester.getCenter(_end));
    await g.moveBy(const Offset(-20, 0));
    await settleFrames(tester);
    expect(r.container.read(sectionEdgePreviewProvider), isNotNull);
    await g.cancel();
    await settleFrames(tester);
    expect(r.calls('study.updateSection'), isEmpty);
    expect(r.container.read(sectionEdgePreviewProvider), isNull);

    g = await tester.startGesture(tester.getCenter(_start));
    await g.moveBy(const Offset(25, 0));
    await settleFrames(tester);
    expect(r.container.read(sectionEdgePreviewProvider), isNotNull);
    await g.up();
    await settleFrames(tester);
    final List<MockCall> u = r.calls('study.updateSection');
    expect(u, hasLength(1));
    final Map p = u.single.params! as Map;
    expect(p['id'], solo);
    expect(p['snap'], 'chord');
    expect(p.containsKey('start'), isTrue);
    expect(p.containsKey('end'), isFalse);
    expect(r.container.read(sectionEdgePreviewProvider), isNull);
  });

  group('controlador', () {
    late List<Completer<List<StudySectionInfo>?>> pending;
    late List<StudyPreviewSectionEdgeParams> sent;
    late List<StudyUpdateSectionParams> commits;
    late int cleared;
    late List<List<StudySectionInfo>> shown;

    SectionEdgeDragController make({bool isStart = true}) {
      pending = <Completer<List<StudySectionInfo>?>>[];
      sent = <StudyPreviewSectionEdgeParams>[];
      commits = <StudyUpdateSectionParams>[];
      shown = <List<StudySectionInfo>>[];
      cleared = 0;
      return SectionEdgeDragController(
        id: 'a',
        isStart: isStart,
        mapper: _Linear(),
        anchor: const Offset(20, 0),
        grab: const Offset(25, 0),
        preview: (StudyPreviewSectionEdgeParams p) {
          sent.add(p);
          final Completer<List<StudySectionInfo>?> c = Completer<List<StudySectionInfo>?>();
          pending.add(c);
          return c.future;
        },
        commit: (StudyUpdateSectionParams p) async => commits.add(p),
        onPreview: shown.add,
        onClear: () => cleared++,
      );
    }

    test('sin moverse desde el agarre el borde no salta', () {
      final SectionEdgeDragController d = make();
      d.update(const Offset(25, 0), bar: false);
      expect(sent.single.to, 2.0);
      expect(sent.single.snap, StudySnap.chord);
    });

    test('una llamada en vuelo y gana la última posición', () async {
      final SectionEdgeDragController d = make();
      d.update(const Offset(30, 0), bar: false);
      d.update(const Offset(40, 0), bar: false);
      d.update(const Offset(50, 0), bar: true);
      expect(sent, hasLength(1));
      pending[0].complete(const <StudySectionInfo>[]);
      await Future<void>.delayed(Duration.zero);
      expect(sent, hasLength(2));
      expect(sent[1].to, 4.5);
      expect(sent[1].snap, StudySnap.bar);
      pending[1].complete(const <StudySectionInfo>[]);
      await Future<void>.delayed(Duration.zero);
      expect(sent, hasLength(2));
      expect(shown, hasLength(2));
    });

    test('soltar: updateSection con el borde y snap; cancelar: sin llamada', () async {
      SectionEdgeDragController d = make(isStart: false);
      await d.end(const Offset(45, 0), bar: false);
      expect(commits.single.end, 4.0);
      expect(commits.single.start, isNull);
      expect(commits.single.snap, StudySnap.chord);
      expect(cleared, 1);
      d = make();
      d.update(const Offset(30, 0), bar: false);
      d.cancel();
      pending[0].complete(const <StudySectionInfo>[]);
      await Future<void>.delayed(Duration.zero);
      expect(commits, isEmpty);
      expect(shown, isEmpty);
      expect(cleared, 1);
    });
  });
}
