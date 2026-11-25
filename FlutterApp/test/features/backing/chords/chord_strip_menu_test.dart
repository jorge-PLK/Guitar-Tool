import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/launch_options.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/features/backing/widgets/chord_strip.dart';
import 'package:toneforge/features/backing/widgets/chords_area.dart';
import 'package:toneforge/features/backing/widgets/section_boxes.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/selected_project.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_menu.dart';

import '../../../support/harness.dart';
import 'chords_support.dart';

const String _intro = '00000000-0000-0000-0000-000000000003';
const Map<String, Object?> _loop = <String, Object?>{'start': 4.0, 'end': 6.0};

late MockCore _core;
late ProviderContainer _container;

Future<void> _pump(WidgetTester tester, {Map<String, Object?>? loop}) async {
  await tester.runAsync(loadTfFonts);
  _core = (await tester.runAsync(() async => MockCore.load((await DirectoryFixtureSource.find())!)))!;
  final open = (await tester.runAsync(openFixture))!;
  fourChords(open);
  (open['transport']! as Map)['loop'] = loop;
  _core.result('study.open', open);
  _core.result('study.markSection', <String, Object?>{...open, 'added': _intro});
  setTestSurface(tester, const Size(1100, 700));
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
        home: const Align(alignment: Alignment.topLeft, child: ChordsArea(sectionsLayer: stripSectionBoxes)),
      ),
    ),
  );
  await settleFrames(tester);
}

Finder _chord(String name) => find.descendant(of: find.byType(ChordStrip), matching: find.text(name));

Finder _box(String id) => find.byWidgetPredicate(
    (Widget w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('section-box-$id-'));

bool _seeked() => _core.calls.any((c) => c.method == 'study.seek');

Future<void> _secondary(WidgetTester t, Offset p) async {
  final TestGesture g = await t.startGesture(p, kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
  await g.up();
  await settleFrames(t);
}

/// Entradas del menú abierto (divisores incluidos); null si no hay menú.
int? _menuEntries(WidgetTester t) {
  final Finder f = find.byType(TfMenuPanel);
  return f.evaluate().isEmpty ? null : t.widget<TfMenuPanel>(f).entries.length;
}

void main() {
  testWidgets('clic en la cabecera de sección no hace seek ni bucle', (tester) async {
    await _pump(tester);
    await tester.tapAt(tester.getTopLeft(_box(_intro)) + const Offset(20, 10));
    await settleFrames(tester);
    expect(_seeked(), isFalse);
    final g = await tester.startGesture(tester.getTopLeft(_box(_intro)) + const Offset(20, 10));
    await g.moveBy(const Offset(80, 0));
    await g.up();
    await settleFrames(tester);
    expect(_core.calls.any((c) => c.method == 'study.setLoop'), isFalse);
    expect(_seeked(), isFalse);
  });

  testWidgets('clic en la franja superior sin sección debajo sí hace seek', (tester) async {
    await _pump(tester);
    final Offset am = tester.getCenter(_chord('Am'));
    await tester.tapAt(Offset(am.dx, tester.getTopLeft(_box(_intro)).dy + 10));
    await settleFrames(tester);
    expect(_seeked(), isTrue);
  });

  testWidgets('clic en un acorde sigue saltando',(tester) async {
    await _pump(tester);
    await tester.tap(_chord('Am'));
    await settleFrames(tester);
    expect(_seeked(), isTrue);
  });

  testWidgets('con bucle y fuera de sección: Marcar sección y Marcar como solo', (tester) async {
    await _pump(tester, loop: _loop);
    await _secondary(tester, tester.getCenter(_chord('Am')));
    expect(_menuEntries(tester), 2);
    expect(find.text('Marcar sección'), findsOneWidget);
    await tester.tap(find.text('Marcar como solo'));
    await settleFrames(tester);
    final p = _core.calls.lastWhere((c) => c.method == 'study.markSection').params! as Map;
    expect(p['start'], 4);
    expect(p['end'], 6);
    expect(p['solo'], true);
  });

  testWidgets('acorde dentro de una sección: marcar + divisor + 4 del menú de sección', (tester) async {
    await _pump(tester, loop: _loop);
    await _secondary(tester, tester.getCenter(_chord('Cm')));
    expect(_menuEntries(tester), 2 + 1 + 4);
  });

  testWidgets('sin bucle y dentro de una sección: solo el menú de sección', (tester) async {
    await _pump(tester);
    await _secondary(tester, tester.getCenter(_chord('Cm')));
    expect(_menuEntries(tester), 4);
  });

  testWidgets('sin bucle ni sección: sin menú', (tester) async {
    await _pump(tester);
    await _secondary(tester, tester.getCenter(_chord('Am')));
    expect(_menuEntries(tester), isNull);
  });

  testWidgets('modo edición: sin menú', (tester) async {
    await _pump(tester, loop: _loop);
    _container.read(studyStoreProvider.notifier).setEditMode(true);
    await settleFrames(tester);
    await _secondary(tester, tester.getCenter(_chord('Cm')));
    expect(_menuEntries(tester), isNull);
  });
}
