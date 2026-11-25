import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/launch_options.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/features/backing/widgets/chords_area.dart';
import 'package:toneforge/features/backing/widgets/info_row.dart';
import 'package:toneforge/features/backing/widgets/mixer_card.dart';
import 'package:toneforge/features/backing/widgets/section_boxes.dart';
import 'package:toneforge/features/backing/widgets/section_selection.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/selected_project.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_tooltip.dart';

import '../../support/harness.dart';
import 'chords/chords_support.dart';
import 'mixer/mixer_support.dart';

const String _intro = '00000000-0000-0000-0000-000000000003';

Future<ProviderContainer> _pump(WidgetTester tester, Widget home) async {
  await tester.runAsync(loadTfFonts);
  final core = (await tester.runAsync(() async => MockCore.load((await DirectoryFixtureSource.find())!)))!;
  final open = (await tester.runAsync(openFixture))!;
  fourChords(open);
  final a = (open['analysis']! as Map).cast<String, Object?>();
  a['beats'] = <Object?>[for (int i = 0; i < 8; i++) i.toDouble()];
  a['bpm'] = 60.0;
  core.result('study.open', open);
  setTestSurface(tester, const Size(1100, 700));
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
        home: Align(alignment: Alignment.topLeft, child: home),
      ),
    ),
  );
  await settleFrames(tester);
  return container;
}

void main() {
  testWidgets('cabecera de sección: semantics con etiqueta y pista, y tooltip', (tester) async {
    final SemanticsHandle h = tester.ensureSemantics();
    await _pump(tester, const ChordsArea(sectionsLayer: stripSectionBoxes));
    expect(find.bySemanticsLabel(RegExp(r'^(Sección|Solo) .*, \d+:\d\d a \d+:\d\d$')), findsWidgets);
    final SemanticsNode node = tester.getSemantics(find.bySemanticsLabel(RegExp(r'^Sección ')).first);
    expect(node.hint, 'Clic para editarla; mantener pulsado para repetirla en bucle');
    expect(find.byType(TfTooltip), findsWidgets);
    expect(
      tester.widgetList<TfTooltip>(find.byType(TfTooltip)).any((TfTooltip t) => t.message.contains('clic: editar, mantener: bucle')),
      isTrue,
    );
    h.dispose();
  });

  testWidgets('asas de borde: semantics de inicio y fin con la sección seleccionada', (tester) async {
    final SemanticsHandle h = tester.ensureSemantics();
    final ProviderContainer c = await _pump(tester, const ChordsArea(sectionsLayer: stripSectionBoxes));
    c.read(sectionSelectionProvider.notifier).select(_intro);
    await settleFrames(tester);
    expect(find.bySemanticsLabel('Borde de inicio'), findsOneWidget);
    expect(find.bySemanticsLabel('Borde de fin'), findsOneWidget);
    h.dispose();
  });

  testWidgets('canal de guitarra: tooltip de renombrar', (tester) async {
    await pumpMixer(tester, const SizedBox(width: 1000, height: 346, child: MixerCard(compact: false, lowHeight: false)));
    final Iterable<TfTooltip> tips = tester.widgetList<TfTooltip>(find.byType(TfTooltip));
    expect(tips.where((TfTooltip t) => t.message == 'Doble clic para cambiar el nombre').length, 2);
  });

  testWidgets('fila de info: «Tempo detectado:» con los dos puntos del ARB', (tester) async {
    await _pump(tester, const InfoRow());
    expect(find.text('Tempo detectado:'), findsOneWidget);
  });
}
