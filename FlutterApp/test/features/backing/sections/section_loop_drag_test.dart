import 'package:flutter/gestures.dart';
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
import 'package:toneforge/features/backing/widgets/chords_expanded.dart';
import 'package:toneforge/features/backing/widgets/section_boxes.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/selected_project.dart';
import 'package:toneforge/theme/tokens.dart';

import '../../../support/harness.dart';
import '../chords/chords_support.dart';
import '../screen/screen_support.dart' show pumpBacking;

const ValueKey<String> _gridContent = ValueKey<String>('chord-grid-content');
const ValueKey<String> _stripContent = ValueKey<String>('chord-strip-content');

late MockCore _core;
late ProviderContainer _container;

Future<void> _pump(WidgetTester tester, {required bool grid}) async {
  await tester.runAsync(loadTfFonts);
  _core = (await tester.runAsync(() async => MockCore.load((await DirectoryFixtureSource.find())!)))!;
  final Json open = (await tester.runAsync(openFixture))!;
  fourChords(open);
  final Json a = (open['analysis']! as Map).cast<String, Object?>();
  a['beats'] = <Object?>[for (int i = 0; i < 8; i++) i.toDouble()];
  a['bpm'] = 60.0;
  _core.result('study.open', open);
  _core.result('study.setLoop', open['transport']);
  setTestSurface(tester, const Size(1100, 400));
  _container = ProviderContainer(overrides: [
    coreClientProvider.overrideWithValue(_core),
    launchOptionsProvider.overrideWithValue(const LaunchOptions()),
  ]);
  addTearDown(_container.dispose);
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  _container.read(selectedProjectProvider.notifier).select(separatedId);
  _container.read(studyStoreProvider);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: _container,
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
}

Map<Object?, Object?> _last() =>
    _core.calls.lastWhere((MockCall c) => c.method == 'study.setLoop').params! as Map<Object?, Object?>;

Future<void> _drag(WidgetTester tester, Offset a, Offset b, {bool alt = false}) async {
  if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  final TestGesture g = await tester.startGesture(a);
  await g.moveTo(Offset.lerp(a, b, 0.5)!);
  await g.moveTo(b);
  await g.up();
  if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  await settleFrames(tester);
}

void main() {
  // Pantalla completa, expandida y con ratón: el flujo real.
  testWidgets('pantalla expandida, ratón y ⌥: bucle por compases y la cabecera ofrece marcar sección',
      (tester) async {
    late final Json transport;
    final rig = await pumpBacking(tester, size: const Size(1200, 1000), tweak: (open) {
      fourChords(open);
      transport = (open['transport']! as Map).cast<String, Object?>();
      final a = (open['analysis']! as Map).cast<String, Object?>();
      a['beats'] = <Object?>[for (int i = 0; i < 8; i++) i.toDouble()];
      a['bpm'] = 60.0;
    }, setup: (core) {
      core.handle('study.setLoop', (Json p) => <String, Object?>{
            ...transport,
            'loop': <String, Object?>{'start': p['start'], 'end': p['end']},
          });
    });
    await rig.container.read(chordsExpandedProvider.notifier).set(true);
    await settleFrames(tester);
    await tester.pump(const Duration(milliseconds: 400));
    final Offset o = tester.getTopLeft(find.byKey(_gridContent));
    final Offset a = o + const Offset(94, 41), b = o + const Offset(84 + 127 + 40, 41);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    final TestGesture g = await tester.startGesture(a, kind: PointerDeviceKind.mouse);
    await g.moveTo(Offset.lerp(a, b, 0.5)!);
    await g.moveTo(b);
    await g.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await settleFrames(tester);
    final MockCall c = rig.core.calls.lastWhere((MockCall c) => c.method == 'study.setLoop');
    expect((c.params! as Map)['snap'], 'bar');
    expect(find.text('Marcar sección'), findsOneWidget);
    await tester.tap(find.text('Marcar sección'));
    await settleFrames(tester);
    expect(rig.core.calls.where((MockCall c) => c.method == 'study.markSection'), isNotEmpty);
  });

  testWidgets('rejilla con secciones: arrastrar sobre las celdas crea un bucle', (tester) async {
    await _pump(tester, grid: true);
    expect(_container.read(studyStoreProvider).study!.sections, isNotEmpty);
    final Offset o = tester.getTopLeft(find.byKey(_gridContent));
    // Compás 0 pulso 0 → compás 1 pulso 1, fila 0, bajo la franja de cabeceras.
    await _drag(tester, o + const Offset(94, 41), o + const Offset(84 + 127 + 40, 41));
    // Causa del bug: la rejilla mandaba snap «beat» y el núcleo (none/chord/bar) responde bad-params.
    expect(const <String>{'none', 'chord', 'bar'}.contains(_last()['snap'] ?? 'none'), isTrue);
    expect(_last()['start'], 0);
  });

  testWidgets('rejilla con secciones y ⌥: snap bar', (tester) async {
    await _pump(tester, grid: true);
    final Offset o = tester.getTopLeft(find.byKey(_gridContent));
    await _drag(tester, o + const Offset(94, 41), o + const Offset(84 + 127 + 40, 41), alt: true);
    expect(_last()['snap'], 'bar');
  });

  testWidgets('tira con secciones: arrastrar sobre los chips crea un bucle; con ⌥, snap bar', (tester) async {
    await _pump(tester, grid: false);
    final Offset o = tester.getTopLeft(find.byKey(_stripContent));
    await _drag(tester, o + const Offset(20, 50), o + const Offset(150, 50));
    expect(_core.calls.where((MockCall c) => c.method == 'study.setLoop'), isNotEmpty);
    await _drag(tester, o + const Offset(20, 50), o + const Offset(150, 50), alt: true);
    expect(_last()['snap'], 'bar');
  });
}
