import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/launch_options.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/features/backing/widgets/chord_chip.dart';
import 'package:toneforge/features/backing/widgets/chord_editor.dart';
import 'package:toneforge/features/backing/widgets/chord_grid.dart';
import 'package:toneforge/features/backing/widgets/chords_area.dart';
import 'package:toneforge/features/backing/widgets/chords_expanded.dart';
import 'package:toneforge/features/backing/widgets/chords_header.dart';
import 'package:toneforge/features/backing/widgets/mixer_card.dart';
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

const String _intro = '00000000-0000-0000-0000-000000000003';
const String _solo = '00000000-0000-0000-0000-000000000004';

/// Todos los goldens corren como macOS para que los atajos salgan con ⌥/⌘.
final TargetPlatformVariant _macOS = TargetPlatformVariant.only(TargetPlatform.macOS);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget home, {
  Size size = const Size(1100, 400),
  void Function(Json open)? tweak,
}) async {
  await tester.runAsync(loadTfFonts);
  final MockCore core = (await tester.runAsync(() async => MockCore.load((await DirectoryFixtureSource.find())!)))!;
  final Json open = (await tester.runAsync(openFixture))!;
  fourChords(open);
  final Json a = (open['analysis']! as Map).cast<String, Object?>();
  a['beats'] = <Object?>[for (int i = 0; i < 8; i++) i.toDouble()];
  a['bpm'] = 60.0;
  tweak?.call(open);
  core.result('study.open', open);
  setTestSurface(tester, size);
  final ProviderContainer container = ProviderContainer(overrides: [
    coreClientProvider.overrideWithValue(core),
    launchOptionsProvider.overrideWithValue(const LaunchOptions()),
    chordsExpandedPrefStoreProvider.overrideWithValue(MemPrefs()),
  ]);
  addTearDown(container.dispose);
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  container.read(selectedProjectProvider.notifier).select(separatedId);
  container.read(studyStoreProvider);
  await tester.pumpWidget(UncontrolledProviderScope(
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
      home: ColoredBox(color: TfColors.bg, child: Align(alignment: Alignment.topLeft, child: home)),
    ),
  ));
  await settleFrames(tester);
  return container;
}

void _loop(Json open) {
  (open['transport']! as Map)['loop'] = <String, Object?>{'start': 2.0, 'end': 4.0};
}

Future<void> _golden(String name) =>
    expectLater(find.byType(WidgetsApp), matchesGoldenFile('$name.png'));

void main() {
  testWidgets(
    'golden tira de acordes con cajas de sección y bucle en Solo',
    (tester) async {
      await _pump(tester, const ChordsArea(sectionsLayer: stripSectionBoxes),
          size: const Size(700, 130), tweak: _loop);
      await _golden('chord_strip_sections_loop');
    },
    variant: _macOS,
  );

  testWidgets(
    'golden rejilla con cajas de sección y Solo seleccionada con asas',
    (tester) async {
      final ProviderContainer c = await _pump(tester, const ChordGrid(sectionsLayer: gridSectionBoxes),
          size: const Size(1100, 160));
      c.read(sectionSelectionProvider.notifier).select(_solo);
      await settleFrames(tester);
      await _golden('chord_grid_sections_selected');
    },
    variant: _macOS,
  );

  testWidgets(
    'golden mezclador normal',
    (tester) async {
      await _pump(tester, const SizedBox(width: 1000, height: 346, child: MixerCard(compact: false, lowHeight: false)), size: const Size(1000, 346));
      await _golden('mixer_card_normal');
    },
    variant: _macOS,
  );

  testWidgets(
    'golden mezclador compacto',
    (tester) async {
      await _pump(tester, const SizedBox(width: 1000, child: MixerCard(compact: true, lowHeight: true)),
          size: const Size(1000, 200));
      await _golden('mixer_card_compact');
    },
    variant: _macOS,
  );

  testWidgets(
    'golden hoja Sección / Solo',
    (tester) async {
      final ProviderContainer c = await _pump(tester, const SizedBox(), size: const Size(500, 520));
      c.read(sectionPopoverProvider.notifier).open(_intro);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
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
          home: const ColoredBox(
            color: TfColors.bg,
            child: Align(alignment: Alignment.topLeft, child: SectionPopover(sectionId: _intro)),
          ),
        ),
      ));
      await settleFrames(tester);
      await _golden('section_popover');
    },
    variant: _macOS,
  );

  testWidgets(
    'golden hoja Acorde',
    (tester) async {
      final ChordsRig rig = await pumpChords(tester, size: const Size(1100, 900), tweak: (Json o) {
        fourChords(o, position: 3);
        final Json a = (o['analysis']! as Map).cast<String, Object?>();
        a['beats'] = <Object?>[for (int i = 0; i < 8; i++) i.toDouble()];
        (a['chords']! as List).cast<Map<String, Object?>>()[1]['shown'] = <String, Object?>{'root': 0, 'quality': 7};
      });
      rig.container.read(studyStoreProvider.notifier).setEditMode(true);
      await settleFrames(tester);
      await tester.tap(find.byType(ChordChip).at(1));
      await settleFrames(tester);
      expect(find.byType(ChordEditor), findsOneWidget);
      await _golden('chord_editor');
    },
    variant: _macOS,
  );

  testWidgets(
    'golden tarjeta de tiempo completa con bucle',
    (tester) async {
      await _pump(tester, const TimelineCard(), size: const Size(1100, 420), tweak: _loop);
      expect(find.byType(ChordsHeader), findsWidgets);
      await _golden('timeline_card');
    },
    variant: _macOS,
  );
}
