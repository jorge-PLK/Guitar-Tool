import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/study.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/launch_options.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/features/backing/widgets/chord_strip.dart';
import 'package:toneforge/features/backing/widgets/chords_area.dart';
import 'package:toneforge/features/backing/widgets/section_boxes.dart';
import 'package:toneforge/features/backing/widgets/section_popover.dart';
import 'package:toneforge/features/backing/widgets/section_popover_state.dart';
import 'package:toneforge/features/backing/widgets/section_selection.dart';
import 'package:toneforge/features/backing/widgets/timeline_card.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/selected_project.dart';
import 'package:toneforge/theme/tokens.dart';

import '../../../support/harness.dart';
import '../chords/chords_support.dart';

const String intro = '00000000-0000-0000-0000-000000000003';
const String solo = '00000000-0000-0000-0000-000000000004';

late MockCore core;
late ProviderContainer container;

Future<void> _pump(WidgetTester tester, {Widget? home, void Function(Json)? tweak}) async {
  await tester.runAsync(loadTfFonts);
  core = (await tester.runAsync(() async => MockCore.load((await DirectoryFixtureSource.find())!)))!;
  final open = (await tester.runAsync(openFixture))!;
  fourChords(open);
  final a = (open['analysis']! as Map).cast<String, Object?>();
  a['beats'] = <Object?>[for (int i = 0; i < 8; i++) i.toDouble()];
  a['bpm'] = 60.0;
  tweak?.call(open);
  core.result('study.open', open);
  core.result('study.updateSection', open);
  core.result('study.deleteSection', open);
  core.result('study.markSection', <String, Object?>{...open, 'added': solo});
  for (final String m in <String>['study.setLoop']) {
    core.result(m, open['transport']);
  }
  setTestSurface(tester, const Size(1100, 700));
  container = ProviderContainer(overrides: [
    coreClientProvider.overrideWithValue(core),
    launchOptionsProvider.overrideWithValue(const LaunchOptions()),
  ]);
  addTearDown(container.dispose);
  addTearDown(() => tester.pumpWidget(const SizedBox()));
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
          child: home ?? const ChordsArea(sectionsLayer: stripSectionBoxes),
        ),
      ),
    ),
  );
  await settleFrames(tester);
}

Finder _box(String id) => find.byWidgetPredicate(
    (Widget w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('section-box-$id-'));

Offset _header(WidgetTester t, String id) => t.getTopLeft(_box(id)) + const Offset(20, 10);

Iterable<MockCall> _calls(String m) => core.calls.where((c) => c.method == m);

StudySectionInfo _section(String id) =>
    container.read(studyStoreProvider).study!.sections.firstWhere((s) => s.id == id);

Future<void> _secondary(WidgetTester t, Offset p) async {
  final TestGesture g = await t.startGesture(p, kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
  await g.up();
  await settleFrames(t);
}

void main() {
  testWidgets('clic en la cabecera selecciona y abre la hoja anclada', (tester) async {
    await _pump(tester);
    expect(find.byType(SectionPopover), findsNothing);
    await tester.tapAt(_header(tester, intro));
    await settleFrames(tester);
    expect(container.read(sectionSelectionProvider), intro);
    expect(container.read(sectionPopoverProvider), intro);
    expect(find.byType(SectionPopover), findsOneWidget);
  });

  testWidgets('pulsación larga sin bucle: setLoop con los extremos y el nombre', (tester) async {
    await _pump(tester);
    final StudySectionInfo s = _section(intro);
    await tester.longPressAt(_header(tester, intro));
    await settleFrames(tester);
    final Map<Object?, Object?> p = _calls('study.setLoop').single.params! as Map<Object?, Object?>;
    expect(p['start'], s.start);
    expect(p['end'], s.end);
    expect(p['name'], s.name);
  });

  testWidgets('pulsación larga con el bucle igual a la sección: lo quita', (tester) async {
    await _pump(tester, tweak: (open) {
      (open['transport']! as Map)['loop'] = <String, Object?>{'start': 2.0, 'end': 4.0};
    });
    await tester.longPressAt(_header(tester, solo));
    await settleFrames(tester);
    final Map<Object?, Object?> p = _calls('study.setLoop').single.params! as Map<Object?, Object?>;
    expect(p['start'], isNull);
    expect(p['end'], isNull);
  });

  testWidgets('menú contextual: 4 entradas, marcar como solo y eliminar', (tester) async {
    await _pump(tester);
    await _secondary(tester, _header(tester, intro));
    expect(find.text('Renombrar y ajustar…'), findsOneWidget);
    expect(find.text('Marcar como solo'), findsOneWidget);
    expect(find.text('Quitar marca de solo'), findsNothing);
    expect(find.text('Eliminar sección'), findsOneWidget);
    await tester.tap(find.text('Marcar como solo'));
    await settleFrames(tester);
    final Map<Object?, Object?> p = _calls('study.updateSection').single.params! as Map<Object?, Object?>;
    expect(p['id'], intro);
    expect(p['solo'], true);

    await _secondary(tester, _header(tester, intro));
    await tester.tap(find.text('Eliminar sección'));
    await settleFrames(tester);
    expect(_calls('study.deleteSection').single.params, containsPair('id', intro));
    expect(container.read(sectionSelectionProvider), isNull);
  });

  testWidgets('menú contextual de un solo: «Quitar marca de solo»; renombrar abre la hoja', (tester) async {
    await _pump(tester);
    await _secondary(tester, _header(tester, solo));
    expect(find.text('Quitar marca de solo'), findsOneWidget);
    expect(find.text('Marcar como solo'), findsNothing);
    await tester.tap(find.text('Renombrar y ajustar…'));
    await settleFrames(tester);
    expect(container.read(sectionPopoverProvider), solo);
    expect(container.read(sectionSelectionProvider), solo);
  });

  testWidgets('onSectionMarked abre la hoja de la sección recién marcada', (tester) async {
    await _pump(tester, home: const TimelineCard(), tweak: (open) {
      (open['transport']! as Map)['loop'] = <String, Object?>{'start': 2.0, 'end': 4.0};
    });
    await tester.tap(find.text('Marcar sección'));
    await settleFrames(tester);
    expect(_calls('study.markSection'), isNotEmpty);
    expect(container.read(sectionPopoverProvider), solo);
    expect(container.read(sectionSelectionProvider), solo);
  });
}
