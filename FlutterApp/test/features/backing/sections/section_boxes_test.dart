import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/launch_options.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/features/backing/widgets/chord_grid.dart';
import 'package:toneforge/features/backing/widgets/chord_strip.dart';
import 'package:toneforge/features/backing/widgets/chords_area.dart';
import 'package:toneforge/features/backing/widgets/section_boxes.dart';
import 'package:toneforge/features/backing/widgets/section_boxes_painter.dart';
import 'package:toneforge/features/backing/widgets/section_selection.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/selected_project.dart';
import 'package:toneforge/theme/tokens.dart';

import '../../../support/harness.dart';
import '../chords/chords_support.dart';

const String intro = '00000000-0000-0000-0000-000000000003';
const String solo = '00000000-0000-0000-0000-000000000004';

Future<ProviderContainer> _pump(WidgetTester tester, {required bool grid, void Function(Json)? tweak}) async {
  await tester.runAsync(loadTfFonts);
  final core = (await tester.runAsync(() async => MockCore.load((await DirectoryFixtureSource.find())!)))!;
  final open = (await tester.runAsync(openFixture))!;
  fourChords(open);
  final a = (open['analysis']! as Map).cast<String, Object?>();
  a['beats'] = <Object?>[for (int i = 0; i < 8; i++) i.toDouble()];
  a['bpm'] = 60.0;
  tweak?.call(open);
  core.result('study.open', open);
  setTestSurface(tester, const Size(1100, 400));
  final container = ProviderContainer(overrides: [
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
  return container;
}

Finder _boxes(String id) =>
    find.byWidgetPredicate((Widget w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('section-box-$id-'));

SectionBoxPainter _painter(WidgetTester t, String id) => t
    .widget<CustomPaint>(find.descendant(of: _boxes(id), matching: find.byType(CustomPaint)).first)
    .painter! as SectionBoxPainter;

Rect _rel(WidgetTester t, Finder box, String contentKey) {
  final Offset origin = t.getTopLeft(find.byKey(ValueKey<String>(contentKey)));
  return t.getRect(box).shift(-origin);
}

void main() {
  testWidgets('tira: una caja por sección con x y ancho de los chips, 63 de alto', (tester) async {
    await _pump(tester, grid: false);
    final ChordStripLayout l = ChordStripLayout.compute(<String>['Cm', 'Cm(maj7)', 'G', 'Am']);
    final Rect a = _rel(tester, _boxes(intro), 'chord-strip-content');
    final Rect b = _rel(tester, _boxes(solo), 'chord-strip-content');
    expect(a.left, closeTo(l.rects[0].left - 2, 0.01));
    expect(a.right, closeTo(l.rects[0].right + 2, 0.01));
    expect(b.left, closeTo(l.rects[1].left - 2, 0.01));
    expect(b.right, closeTo(l.rects[1].right + 2, 0.01));
    expect(a.top, 0);
    expect(a.height, 63);
  });

  testWidgets('estilo: normal con color de paleta, solo con accent y cabecera accentBg', (tester) async {
    await _pump(tester, grid: false);
    final SectionBoxPainter n = _painter(tester, intro);
    final SectionBoxPainter s = _painter(tester, solo);
    expect(n.color, TfColors.sectionPalette[0]);
    expect(n.solo, isFalse);
    expect(n.headerHeight, 22);
    expect(s.color, TfColors.accent);
    expect(s.solo, isTrue);
    expect(find.text('Solo'), findsOneWidget);
    expect(find.text('Intro'), findsOneWidget);
  });

  testWidgets('clic en la cabecera selecciona; la seleccionada se pinta como tal', (tester) async {
    final c = await _pump(tester, grid: false);
    expect(c.read(sectionSelectionProvider), isNull);
    await tester.tapAt(tester.getTopLeft(_boxes(intro)) + const Offset(20, 10));
    await settleFrames(tester);
    expect(c.read(sectionSelectionProvider), intro);
    expect(_painter(tester, intro).selected, isTrue);
    expect(_painter(tester, solo).selected, isFalse);
    c.read(sectionSelectionProvider.notifier).clear();
    await settleFrames(tester);
    expect(_painter(tester, intro).selected, isFalse);
  });

  testWidgets('el bucle igual a la sección la marca como activa', (tester) async {
    await _pump(tester, grid: false, tweak: (open) {
      (open['transport']! as Map)['loop'] = <String, Object?>{'start': 2.0, 'end': 4.0};
    });
    expect(_painter(tester, solo).loopActive, isTrue);
    expect(_painter(tester, intro).loopActive, isFalse);
  });

  testWidgets('se deselecciona al cambiar de tema', (tester) async {
    final c = await _pump(tester, grid: false);
    c.read(sectionSelectionProvider.notifier).select(intro);
    c.read(selectedProjectProvider.notifier).select(null);
    await settleFrames(tester);
    expect(c.read(sectionSelectionProvider), isNull);
  });

  testWidgets('rejilla: una caja por fila con x y ancho de las celdas', (tester) async {
    await _pump(tester, grid: true);
    // 1100 de ancho: 8 por fila, barWidth 127, drawn 123, celda 30,75; Intro = pulsos 0 y 1 del compás 0.
    final Rect a = _rel(tester, _boxes(intro), 'chord-grid-content');
    final Rect b = _rel(tester, _boxes(solo), 'chord-grid-content');
    expect(a.left, closeTo(82, 0.01));
    expect(a.width, closeTo(65.5, 0.01));
    expect(a.top, 0);
    expect(a.height, 66);
    expect(b.left, closeTo(84 + 61.5 - 2, 0.01));
    expect(_painter(tester, intro).headerHeight, 18);
    expect(_painter(tester, solo).solo, isTrue);
    await tester.tapAt(tester.getTopLeft(_boxes(solo)) + const Offset(20, 8));
    await settleFrames(tester);
    expect(_painter(tester, solo).selected, isTrue);
  });
}
