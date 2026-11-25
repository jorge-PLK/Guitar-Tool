import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/launch_options.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/features/backing/widgets/section_popover.dart';
import 'package:toneforge/features/backing/widgets/section_popover_rows.dart';
import 'package:toneforge/features/backing/widgets/section_popover_state.dart';
import 'package:toneforge/features/backing/widgets/section_selection.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/selected_project.dart';
import 'package:toneforge/theme/tokens.dart';

import '../../../support/harness.dart';
import '../screen/screen_support.dart';

const String intro = '00000000-0000-0000-0000-000000000003';

late MockCore core;
late ProviderContainer container;

Future<void> _pump(
  WidgetTester tester, {
  void Function(Map<String, Object?> open)? tweak,
  bool playing = false,
}) async {
  await tester.runAsync(loadTfFonts);
  core = (await tester.runAsync(() async => MockCore.load((await DirectoryFixtureSource.find())!)))!;
  final open = (await tester.runAsync(openFixture))!;
  (open['transport']! as Map<String, Object?>)['playing'] = playing;
  tweak?.call(open);
  core.result('study.open', open);
  core.result('study.updateSection', open);
  for (final String m in <String>['study.play', 'study.pause', 'study.seek', 'study.setLoop']) {
    core.result(m, open['transport']);
  }
  setTestSurface(tester, const Size(500, 700));
  container = ProviderContainer(overrides: [
    coreClientProvider.overrideWithValue(core),
    launchOptionsProvider.overrideWithValue(const LaunchOptions()),
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
      home: Align(
        alignment: Alignment.topLeft,
        child: Consumer(builder: (BuildContext c, WidgetRef ref, _) {
          final String? id = ref.watch(sectionPopoverProvider);
          return id == null ? const SizedBox() : SectionPopover(key: ValueKey<String>(id), sectionId: id);
        }),
      ),
    ),
  ));
  await settleFrames(tester);
  container.read(sectionPopoverProvider.notifier).open(intro);
  await settleFrames(tester);
}

Iterable<MockCall> _calls(String m) => core.calls.where((c) => c.method == m);
Map<Object?, Object?> _last(String m) => _calls(m).last.params! as Map<Object?, Object?>;

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.tap(f);
  await settleFrames(tester);
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

void main() {
  testWidgets('estado inicial: título, nombre enfocado, tiempos m:ss.d', (tester) async {
    await _pump(tester);
    expect(find.text('Sección'), findsOneWidget);
    expect(tester.widget<EditableText>(find.byType(EditableText)).controller.text, 'Intro');
    expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isTrue);
    expect(tester.widget<Text>(_key('section-start-time')).data, '0:00.0');
    expect(tester.widget<Text>(_key('section-end-time')).data, '0:02.0');
    expect(sectionPreciseTime(75.26), '1:15.3');
  });

  testWidgets('Hecho renombra con el borrador y cierra', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(EditableText), 'Puente');
    await _tap(tester, find.text('Hecho'));
    expect(_calls('study.updateSection').length, 1);
    expect(_last('study.updateSection')['name'], 'Puente');
    expect(container.read(sectionPopoverProvider), isNull);
  });

  testWidgets('Intro en el campo renombra y cierra', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(EditableText), 'Final');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settleFrames(tester);
    expect(_calls('study.updateSection').length, 1);
    expect(_last('study.updateSection')['name'], 'Final');
    expect(container.read(sectionPopoverProvider), isNull);
  });

  testWidgets('la sugerencia rellena el borrador', (tester) async {
    await _pump(tester);
    await _tap(tester, find.text('Estribillo'));
    expect(tester.widget<EditableText>(find.byType(EditableText)).controller.text, 'Estribillo');
  });

  testWidgets('Esc en el campo cierra sin renombrar', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(EditableText), 'Nada');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settleFrames(tester);
    expect(container.read(sectionPopoverProvider), isNull);
    expect(_calls('study.updateSection'), isEmpty);
  });

  testWidgets('cerrar desde fuera renombra con el borrador', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(EditableText), 'Puente');
    container.read(sectionPopoverProvider.notifier).close();
    await settleFrames(tester);
    expect(_calls('study.updateSection').length, 1);
    expect(_last('study.updateSection')['name'], 'Puente');
  });

  testWidgets('color: elegir uno y, con color propio, volver a automático', (tester) async {
    await _pump(tester, tweak: (open) {
      final s = ((open['sections']! as List)[0] as Map<String, Object?>);
      s['color'] = 1;
      s['paletteIndex'] = 1;
    });
    await _tap(tester, _key('section-swatch-3'));
    expect(_last('study.updateSection')['color'], 3);
    await _tap(tester, _key('section-swatch-1'));
    final Map<Object?, Object?> p = _last('study.updateSection');
    expect(p.containsKey('color'), isTrue);
    expect(p['color'], isNull);
  });

  testWidgets('en solo: círculo naranja y nota, sin paleta', (tester) async {
    await _pump(tester);
    container.read(sectionPopoverProvider.notifier).open('00000000-0000-0000-0000-000000000004');
    await settleFrames(tester);
    expect(find.text('Solo'), findsWidgets);
    expect(find.text('Los solos van en naranja'), findsOneWidget);
    expect(_key('section-swatch-0'), findsNothing);
  });

  Future<void> soloResult(WidgetTester tester) async {
    final open = (await tester.runAsync(openFixture))!;
    final edit = <String, Object?>{...open};
    final s = ((edit['sections']! as List)[0] as Map<String, Object?>);
    edit['sections'] = <Object?>[
      <String, Object?>{...s, 'solo': true, 'name': 'Solo 2'},
      (edit['sections']! as List)[1],
    ];
    core.result('study.updateSection', edit);
  }

  testWidgets('Solo: el nombre por defecto sigue a la marca si no se tocó', (tester) async {
    await _pump(tester);
    await soloResult(tester);
    await _tap(tester, _key('section-solo'));
    expect(_last('study.updateSection')['solo'], true);
    expect(tester.widget<EditableText>(find.byType(EditableText)).controller.text, 'Solo 2');
    expect(find.text('Solo'), findsWidgets);
  });

  testWidgets('Solo: un nombre escrito a mano se conserva', (tester) async {
    await _pump(tester);
    await soloResult(tester);
    await tester.enterText(find.byType(EditableText), 'Mi parte');
    await _tap(tester, _key('section-solo'));
    expect(tester.widget<EditableText>(find.byType(EditableText)).controller.text, 'Mi parte');
  });

  testWidgets('◀ ▶ empujan el borde; con Alt, por compás', (tester) async {
    await _pump(tester);
    await _tap(tester, _key('section-start-forward'));
    var p = _last('study.nudgeSectionEdge');
    expect([p['id'], p['start'], p['forward']], [intro, true, true]);
    expect(p['bar'], isNot(true));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await _tap(tester, _key('section-end-back'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    p = _last('study.nudgeSectionEdge');
    expect([p['start'], p['forward'], p['bar']], [false, false, true]);
  });

  testWidgets('Escuchar en bucle: setLoop, seek al inicio y play si estaba parado', (tester) async {
    await _pump(tester);
    await _tap(tester, _key('section-listen'));
    final order = <String>[for (final c in core.calls) c.method];
    expect(order.where((m) => m == 'study.setLoop' || m == 'study.seek' || m == 'study.play'),
        ['study.setLoop', 'study.seek', 'study.play']);
    expect(_last('study.setLoop')['name'], 'Intro');
    expect(_last('study.seek')['seconds'], 0);
    expect(container.read(sectionPopoverProvider), intro);
  });

  testWidgets('Escuchar en bucle no pulsa play si ya sonaba', (tester) async {
    await _pump(tester, playing: true);
    await _tap(tester, _key('section-listen'));
    expect(_calls('study.setLoop'), isNotEmpty);
    expect(_calls('study.play'), isEmpty);
  });

  testWidgets('Eliminar deselecciona, borra y cierra sin renombrar', (tester) async {
    await _pump(tester);
    container.read(sectionSelectionProvider.notifier).select(intro);
    await _tap(tester, find.text('Eliminar'));
    expect(_last('study.deleteSection')['id'], intro);
    expect(container.read(sectionSelectionProvider), isNull);
    expect(container.read(sectionPopoverProvider), isNull);
    expect(_calls('study.updateSection'), isEmpty);
  });
}
