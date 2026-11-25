import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/launch_options.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/features/backing/widgets/chord_editor.dart';
import 'package:toneforge/features/backing/widgets/chord_grid.dart';
import 'package:toneforge/features/backing/widgets/chord_grid_geometry.dart';
import 'package:toneforge/features/backing/widgets/chord_grid_painter.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/selected_project.dart';
import 'package:toneforge/theme/tokens.dart';

import '../../../support/harness.dart';
import '../chords/chords_support.dart';

const ValueKey<String> paintKey = ValueKey<String>('chord-grid-paint');
const ValueKey<String> contentKey = ValueKey<String>('chord-grid-content');

/// Cuatro acordes de 2 s, pulsos cada 1 s (60 bpm), compases en 0 y 4.
void withBeats(Json open, {double position = 0}) {
  fourChords(open, position: position);
  final a = (open['analysis']! as Map).cast<String, Object?>();
  a['beats'] = <Object?>[for (int i = 0; i < 8; i++) i.toDouble()];
  a['bpm'] = 60.0;
}

Future<(MockCore, ProviderContainer)> pumpGrid(
  WidgetTester tester, {
  void Function(Json open)? tweak,
  Size size = const Size(1100, 400),
  void Function(int)? onEdit,
}) async {
  await tester.runAsync(loadTfFonts);
  final core = (await tester.runAsync(() async => MockCore.load((await DirectoryFixtureSource.find())!)))!;
  final open = (await tester.runAsync(openFixture))!;
  tweak?.call(open);
  core.result('study.open', open);
  setTestSurface(tester, size);
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
        home: Align(alignment: Alignment.topLeft, child: ChordGrid(onEditChord: onEdit)),
      ),
    ),
  );
  await settleFrames(tester);
  return (core, container);
}

ChordGridPainter painterOf(WidgetTester t) => (t.widget<CustomPaint>(find.byKey(paintKey))).painter! as ChordGridPainter;
Offset at(WidgetTester t, double x, double y) => t.getTopLeft(find.byKey(contentKey)) + Offset(x, y);
Map<String, dynamic> call(MockCore c, String m) => c.calls.lastWhere((x) => x.method == m).params! as Map<String, dynamic>;

// Con 1100 de ancho caben 8 compases por fila: barWidth 127, drawn 123, celda 30,75.
// Pulso k del compás c: x = 84 + 127·c + 30,75·k + 10; fila 0: y = 18 + 23.
double cx(int bar, int beat) => 84 + 127.0 * bar + 30.75 * beat + 10;
const double cy = 41;

void main() {
  test('el compás se rellena con pulsos y el acorde se sonda tras el pulso', () {
    final open = <String, Object?>{};
    expect(open, isEmpty);
    final l = ChordGridLayout.build(
      beats: [for (int i = 0; i < 8; i++) i.toDouble()],
      downbeats: [0, 4],
      bpm: 60,
      chords: const [],
    )!;
    expect(l.bars.length, 2);
    expect(l.bars[0].cells.length, 4);
    expect(l.bars[0].cells.first.name, 'N');
    expect(ChordGridLayout.build(beats: const [], downbeats: const [0.0], bpm: 60, chords: const []), isNull);
  });

  testWidgets('compás actual en acento; pasados y futuros en campo', (tester) async {
    await pumpGrid(tester, tweak: (o) => withBeats(o, position: 2.5));
    // El painter pinta con estas mismas funciones: actual = compás 0 y pulso de t = 2.
    final p = painterOf(tester);
    expect(p.rows.single.length, 2);
    expect(p.seconds, 2.5);
    expect(p.rows[0][0].contains(p.seconds), isTrue);
    expect(p.rows[0][1].contains(p.seconds), isFalse);
    expect(p.rows[0][0].cells.where((c) => c.contains(p.seconds)).single.time, 2);
  });

  testWidgets('compases pasados quedan en campo al avanzar', (tester) async {
    await pumpGrid(tester, tweak: (o) => withBeats(o, position: 5.5));
    final p = painterOf(tester);
    expect(p.rows[0][0].contains(p.seconds), isFalse); // pasado
    expect(p.rows[0][1].contains(p.seconds), isTrue); // actual
  });

  testWidgets('el bucle tiñe las celdas dentro; sin bucle no hay tinte', (tester) async {
    await pumpGrid(tester, tweak: (o) {
      withBeats(o);
      (o['transport']! as Map)['loop'] = <String, Object?>{'start': 4.0, 'end': 6.0};
    });
    final p = painterOf(tester);
    expect(p.loop, (4.0, 6.0));
    final inside = [for (final c in p.rows[0][1].cells) gridCellInLoop(c, p.loop)];
    expect(inside, <bool>[true, true, false, false]);
    expect(gridCellInLoop(p.rows[0][0].cells[0], p.loop), isFalse);
    await pumpGrid(tester, tweak: withBeats);
    expect(painterOf(tester).loop, isNull);
  });

  testWidgets('sin ancho para 8, 4 compases por fila', (tester) async {
    await pumpGrid(tester, tweak: withBeats, size: const Size(600, 400));
    expect(painterOf(tester).geometry.perRow, 4);
    expect(painterOf(tester).rows.single.length, 2);
  });

  testWidgets('sin rejilla de pulso, mensaje', (tester) async {
    await pumpGrid(tester, tweak: (o) {
      withBeats(o);
      ((o['analysis']! as Map)['beats'] as List).clear();
    });
    expect(find.text(es.backing_noGrid), findsOneWidget);
  });

  testWidgets('clic en una celda salta a su pulso', (tester) async {
    final (core, _) = await pumpGrid(tester, tweak: withBeats);
    await tester.tapAt(at(tester, cx(0, 2), cy));
    await settleFrames(tester);
    expect(call(core, 'study.seek')['seconds'], 2);
  });

  testWidgets('arrastre: bucle con imán al pulso', (tester) async {
    final (core, _) = await pumpGrid(tester, tweak: withBeats);
    final g = await tester.startGesture(at(tester, cx(0, 0), cy));
    await g.moveTo(at(tester, cx(1, 0) - 20, cy));
    await g.moveTo(at(tester, cx(1, 1), cy));
    await g.up();
    await settleFrames(tester);
    final p = call(core, 'study.setLoop');
    expect(p['start'], 0);
    expect(p['end'], 6);
    expect(p['snap'], isNot('beat')); // el núcleo solo admite none/chord/bar
    expect(p['name'], es.backing_loopNameChords);
    expect(core.calls.any((c) => c.method == 'study.seek'), isFalse);
  });

  testWidgets('arrastre con alt: imán al compás', (tester) async {
    final (core, _) = await pumpGrid(tester, tweak: withBeats);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    final g = await tester.startGesture(at(tester, cx(0, 0), cy));
    await g.moveTo(at(tester, cx(1, 0) - 20, cy));
    await g.moveTo(at(tester, cx(1, 1), cy));
    await g.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await settleFrames(tester);
    final p = call(core, 'study.setLoop');
    expect(p['snap'], 'bar');
    expect(p['name'], es.backing_loopNameBars);
  });

  testWidgets('en edición no hay bucle y el clic abre el acorde', (tester) async {
    final edited = <int>[];
    final (core, c) = await pumpGrid(tester, tweak: withBeats, onEdit: edited.add);
    c.read(studyStoreProvider.notifier).setEditMode(true);
    await settleFrames(tester);
    final g = await tester.startGesture(at(tester, cx(0, 0), cy));
    await g.moveTo(at(tester, cx(1, 1), cy));
    await g.up();
    await tester.tapAt(at(tester, cx(1, 2), cy));
    await settleFrames(tester);
    expect(core.calls.any((x) => x.method == 'study.setLoop'), isFalse);
    expect(core.calls.any((x) => x.method == 'study.seek'), isFalse);
    expect(edited, <int>[3]);
  });

  testWidgets('la hoja Acorde solo se abre en edición y parte en el pulso de la celda', (tester) async {
    final (core, c) = await pumpGrid(tester, tweak: withBeats, size: const Size(1100, 900));
    await tester.tapAt(at(tester, cx(1, 1), cy));
    await settleFrames(tester);
    expect(find.byType(ChordEditor), findsNothing);
    c.read(studyStoreProvider.notifier).setEditMode(true);
    await settleFrames(tester);
    await tester.tapAt(at(tester, cx(1, 1), cy));
    await settleFrames(tester);
    expect(find.byType(ChordEditor), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(ChordEditor), matching: find.text(es.backing_chordSplit)));
    await settleFrames(tester);
    expect(call(core, 'study.splitChord')['at'], 5.0);
    expect(find.byType(ChordEditor), findsOneWidget);
    c.read(studyStoreProvider.notifier).setEditMode(false);
    await settleFrames(tester);
    expect(find.byType(ChordEditor), findsNothing);
  });

  test('una sola geometría', () {
    const g = ChordGridGeometry(1100);
    expect(g.hitTest(Offset(cx(1, 1), cy), rows: 1, beats: 4), const GridCell(0, 1, 1));
  });
}
