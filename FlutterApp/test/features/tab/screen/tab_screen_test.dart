import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/library.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/backing/separated_projects.dart';
import 'package:toneforge/features/tab/songsterr_sheet.dart';
import 'package:toneforge/features/tab/tab_card.dart';
import 'package:toneforge/features/tab/tab_header.dart';
import 'package:toneforge/features/tab/tab_screen.dart';
import 'package:toneforge/features/tab/tab_store.dart';
import 'package:toneforge/features/tab/tab_theme_chooser.dart';
import 'package:toneforge/features/tab/tab_transport.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/selected_project.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_notice.dart';
import 'package:toneforge/widgets/tf_progress.dart';

import '../../../support/harness.dart';
import '../tab_test_support.dart';

const _otherId = '00000000-0000-0000-0000-000000000002';

class Rig {
  Rig(this.core, this.container);
  final MockCore core;
  final ProviderContainer container;
  List<String> get methods => [for (final c in core.calls) c.method];
  Object? lastParams(String method) =>
      core.calls.lastWhere((c) => c.method == method).params;
}

Future<Rig> boot(
  WidgetTester tester, {
  Map<String, Object?> patch = const {},
  bool select = true,
  String? study = projectId,
  List<TabChooserTheme> themes = const [],
  void Function(MockCore core)? prepare,
}) async {
  setTestSurface(tester, const Size(1100, 700));
  final core = (await tester.runAsync(loadCore))!;
  prepare?.call(core);
  final container = ProviderContainer(overrides: [
    coreClientProvider.overrideWithValue(core),
    tabStudyProjectProvider.overrideWith((ref) => ref.watch(studyProjectProbe)),
    launchProjectIdProvider.overrideWith((ref) async => null),
    separatedProjectsProvider.overrideWith((ref) async => [
          for (final t in themes)
            ProjectSummary.fromJson({
              'id': t.id,
              'title': t.title,
              'folderName': t.title,
              'duration': 1.0,
              'sampleRate': 44100.0,
              'createdAt': '2026-01-01T00:00:00Z',
              'updatedAt': '2026-01-01T00:00:00Z',
              'separationState': 'done',
              'stemCount': 4,
              'takeCount': 0,
              'rigCount': 0,
              'hasAnalysis': true,
              'guitars': <Object?>[],
            }),
        ]),
    tabExportDataProvider.overrideWith((ref) => () async => 'AAAA'),
    tabSavePathProvider.overrideWith((ref) => (name) async => '/tmp/$name'),
  ]);
  addTearDown(container.dispose);
  container.listen(tabStoreProvider, (_, _) {});
  if (study != null) container.read(studyProjectProbe.notifier).set(study);
  if (select) container.read(selectedProjectProvider.notifier).select(projectId);
  // Las localizaciones van por encima del Navigator: la hoja de Songsterr se monta en una ruta.
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: WidgetsApp(
      color: TfColors.bg,
      debugShowCheckedModeBanner: false,
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) =>
          PageRouteBuilder<T>(
        settings: settings,
        pageBuilder: (BuildContext c, Animation<double> a, Animation<double> b) => builder(c),
      ),
      home: const DefaultTextStyle(style: TextStyle(), child: TabScreen()),
    ),
  ));
  await tester.runAsync(settle);
  await tester.pump();
  if (patch.isNotEmpty) {
    core.emit('tab.state', {...fixture('tab.open.result.json'), ...patch});
    await tester.runAsync(settle);
    await tester.pump();
  }
  return Rig(core, container);
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text), warnIfMissed: false);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Botón de cabecera por semántica (no por hit test): la hoja puede taparlo.
Finder _semanticButton(String label, {required bool enabled}) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.label == label && w.properties.enabled == enabled);

Finder _exportButton({required bool enabled}) => find.byWidgetPredicate((w) =>
    w is TfSecondaryButton &&
    w.label == 'Exportar a Guitar Pro' &&
    (w.onPressed != null) == enabled);

/// La hoja se abre en un frame posterior y su ruta tarda en montarse (transición de 150 ms).
Future<void> _settleSheet(WidgetTester tester) async {
  await tester.runAsync(settle);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  setUpAll(() async {
    await findFixtures();
    await loadTfFonts();
  });

  group('selector de tema', () {
    testWidgets('vacío', (tester) async {
      await boot(tester, select: false);
      expect(find.text('Tablatura'), findsOneWidget);
      expect(find.text('Aún no hay temas separados. Importa uno y sepáralo en la biblioteca.'),
          findsOneWidget);
    });

    testWidgets('con temas: elegir uno lo selecciona', (tester) async {
      final r = await boot(tester, select: false, themes: [
        (id: _otherId, title: 'Tema uno'),
        (id: projectId, title: 'Tema dos'),
      ]);
      expect(find.text('Elige un tema'), findsOneWidget);
      expect(find.text('Tema uno'), findsOneWidget);
      await tapText(tester, 'Tema dos');
      expect(r.container.read(selectedProjectProvider), projectId);
    });
  });

  testWidgets('controlador sin crear: cabecera y Spacer, sin spinner ni tarjeta', (tester) async {
    await boot(tester, study: null);
    expect(find.byType(TabHeader), findsOneWidget);
    expect(find.byType(TfSpinner), findsNothing);
    expect(find.byType(TabCard), findsNothing);
    expect(find.byType(TabTransport), findsNothing);
  });

  testWidgets('sin tab y con error: mensaje del error', (tester) async {
    await boot(tester, prepare: (c) => c.failWith('tab.open', const CoreError('internal', 'fallo')));
    expect(find.text('fallo'), findsOneWidget);
    expect(find.byType(TfSpinner), findsNothing);
  });

  group('cabecera', () {
    for (final phase in ['waitingAnalysis', 'empty', 'choosingSource', 'working']) {
      testWidgets('Editar y Exportar deshabilitados en $phase', (tester) async {
        final r = await boot(tester, patch: {'phase': phase});
        // En choosingSource la hoja se abre sola (TC:389-392) y puede tapar la cabecera.
        if (phase == 'choosingSource') {
          await _settleSheet(tester);
          expect(find.byType(SongsterrSheet), findsOneWidget);
        }
        expect(_semanticButton('Editar notas', enabled: false), findsOneWidget);
        expect(_exportButton(enabled: false), findsOneWidget);
        await tapText(tester, 'Editar notas');
        await tapText(tester, 'Exportar a Guitar Pro');
        expect(r.methods, isNot(contains('tab.edit')));
        expect(r.methods, isNot(contains('tab.exportName')));
      });
    }

    for (final phase in ['waitingAnalysis', 'empty']) {
      testWidgets('Fuente deshabilitado en $phase', (tester) async {
        await boot(tester, patch: {'phase': phase, 'source': 'songsterr'});
        await tapText(tester, 'Fuente: Songsterr');
        expect(find.text('Buscar en Songsterr…'), findsNothing);
      });
    }

    for (final phase in ['choosingSource', 'working', 'failed']) {
      testWidgets('Fuente habilitado en $phase', (tester) async {
        await boot(tester, patch: {'phase': phase, 'source': 'songsterr'});
        if (phase == 'choosingSource') {
          // La hoja abierta sola tapa la cabecera: se comprueba el botón por semántica.
          await _settleSheet(tester);
          expect(find.byType(SongsterrSheet), findsOneWidget);
          expect(_semanticButton('Fuente: Songsterr', enabled: true), findsOneWidget);
          return;
        }
        await tapText(tester, 'Fuente: Songsterr');
        expect(find.text('Buscar en Songsterr…'), findsOneWidget);
      });
    }

    testWidgets('habilitada en ready', (tester) async {
      final r = await boot(tester);
      await tapText(tester, 'Editar notas');
      expect(r.methods, contains('tab.edit'));
      await tapText(tester, 'Exportar a Guitar Pro');
      expect(r.methods, containsAllInOrder(['tab.exportName', 'tab.export']));
      expect((r.lastParams('tab.export') as Map)['data'], 'AAAA');
      await tapText(tester, 'Fuente: ${_sourceLabel(r)}');
      expect(find.text('Buscar en Songsterr…'), findsOneWidget);
    });

    testWidgets('Exportar deshabilitado sin pistas', (tester) async {
      final r = await boot(tester, patch: {'tracks': <Object?>[]});
      await tapText(tester, 'Exportar a Guitar Pro');
      expect(r.methods, isNot(contains('tab.exportName')));
    });
  });

  group('aviso', () {
    testWidgets('visible con notices y la X llama a tab.dismissNotices', (tester) async {
      final r = await boot(tester, patch: {'notices': ['Aviso uno']});
      expect(find.text('Aviso uno'), findsOneWidget);
      await tester.tap(find.descendant(
          of: find.byType(TfNotice), matching: find.byType(TfIconView)).last);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(r.methods, contains('tab.dismissNotices'));
      expect(find.text('Aviso uno'), findsNothing);
      expect(find.byType(TfNotice), findsNothing);
    });

    testWidgets('sin notices no hay aviso', (tester) async {
      await boot(tester, patch: {'notices': <Object?>[]});
      expect(find.byType(TfNotice), findsNothing);
    });
  });

  group('menú Fuente', () {
    testWidgets('Songsterr: emparejamiento, diálogo y setSource(automatic)', (tester) async {
      final r = await boot(tester, patch: {'source': 'songsterr'});
      await tapText(tester, 'Fuente: Songsterr');
      expect(find.text('Cambiar emparejamiento…'), findsOneWidget);
      await tapText(tester, 'Transcripción automática');
      expect(find.text('¿Pasar a transcripción automática?'), findsOneWidget);
      expect(r.methods, isNot(contains('tab.setSource')));
      await tapText(tester, 'Pasar a automática');
      expect((r.lastParams('tab.setSource') as Map)['source'], 'automatic');
    });

    testWidgets('Songsterr: Cancelar no cambia la fuente', (tester) async {
      final r = await boot(tester, patch: {'source': 'songsterr'});
      await tapText(tester, 'Fuente: Songsterr');
      await tapText(tester, 'Transcripción automática');
      await tapText(tester, 'Cancelar');
      expect(r.methods, isNot(contains('tab.setSource')));
    });

    testWidgets('automática: sin emparejamiento y la entrada automática inerte', (tester) async {
      final r = await boot(tester, patch: {'source': 'automatic'});
      await tapText(tester, 'Fuente: Transcripción automática');
      expect(find.text('Cambiar emparejamiento…'), findsNothing);
      await tapText(tester, 'Transcripción automática');
      expect(r.methods, isNot(contains('tab.setSource')));
      expect(find.text('¿Pasar a transcripción automática?'), findsNothing);
    });

    testWidgets('sin elegir: pasa a automática sin diálogo', (tester) async {
      final r = await boot(tester, patch: {'source': null});
      await tapText(tester, 'Fuente: Sin elegir');
      expect(find.text('Cambiar emparejamiento…'), findsNothing);
      await tapText(tester, 'Transcripción automática');
      expect((r.lastParams('tab.setSource') as Map)['source'], 'automatic');
    });
  });
}

String _sourceLabel(Rig r) {
  final src = r.container.read(tabStoreProvider).tab?.source?.wire;
  return switch (src) {
    'songsterr' => 'Songsterr',
    'automatic' => 'Transcripción automática',
    _ => 'Sin elegir',
  };
}
