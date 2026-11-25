import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/tab/songsterr_choosing.dart';
import 'package:toneforge/features/tab/songsterr_issue_box.dart';
import 'package:toneforge/features/tab/songsterr_sheet.dart';
import 'package:toneforge/features/tab/songsterr_store.dart';
import 'package:toneforge/features/tab/tab_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_progress.dart';

import '../../../support/harness.dart';
import '../tab_test_support.dart';

const _slot = ValueKey<String>('songsterr-preview-slot');

class Rig {
  Rig(this.core, this.container);
  final MockCore core;
  final ProviderContainer container;
  List<String> get methods => [for (final c in core.calls) c.method];
}

Future<Rig> boot(
  WidgetTester tester, {
  Widget child = const SongsterrSheet(),
  Map<String, Object?> patch = const {},
  Size size = const Size(1400, 800),
  bool open = true,
}) async {
  setTestSurface(tester, size);
  final core = (await tester.runAsync(loadCore))!;
  final container = ProviderContainer(overrides: [
    coreClientProvider.overrideWithValue(core),
    tabStudyProjectProvider.overrideWith((ref) => ref.watch(studyProjectProbe)),
  ]);
  addTearDown(container.dispose);
  container.listen(songsterrStoreProvider, (_, _) {});
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
        pageBuilder: (c, a, b) => builder(c),
      ),
      home: DefaultTextStyle(
        style: const TextStyle(),
        child: Align(alignment: Alignment.topCenter, child: child),
      ),
    ),
  ));
  if (open) {
    core.emit('tab.songsterr.state',
        {...fixture('tab.songsterr.state.result.results.json'), ...patch});
    await tester.runAsync(settle);
    await tester.pump();
  }
  return Rig(core, container);
}

Finder _button(String label) => find.widgetWithText(TfSecondaryButton, label);

void main() {
  setUpAll(() async {
    await loadTfFonts();
    await findFixtures();
  });

  testWidgets('choosing con resultados: ficha con pistas y afinación, otros resultados',
      (tester) async {
    await boot(tester);
    expect(find.text('Tablatura de Songsterr'), findsOneWidget);
    expect(find.text('Búsqueda: Banda · Tema'), findsOneWidget);
    expect(find.text('Banda · Tema 7'), findsOneWidget);
    expect(find.text('Rítmica'), findsOneWidget);
    expect(find.text('E A D G B E'), findsOneWidget);
    expect(find.text('E A D G'), findsOneWidget);
    expect(find.text('-'), findsOneWidget);
    expect(find.text('Otros resultados'), findsOneWidget);
    expect(find.text('Banda · Tema (live)'), findsOneWidget);
    expect(find.byKey(_slot), findsNothing);
  });

  testWidgets('ancho 660 sin vista previa', (tester) async {
    await boot(tester);
    expect(tester.getSize(find.byType(SongsterrSheet)).width, 660);
  });

  testWidgets('marcar un resultado llama a select y abre la vista previa', (tester) async {
    final rig = await boot(tester);
    await tester.tap(find.text('Banda · Tema (live)'));
    await tester.runAsync(settle);
    await tester.pump();
    expect(rig.methods, contains('tab.songsterr.select'));
    expect((rig.core.calls.last.params as Map)['songId'], 8);
    expect(find.byKey(_slot), findsOneWidget);
    expect(_button('Vista previa'), findsNothing);
  });

  testWidgets('con vista previa: ancho 1320 y lista de 612', (tester) async {
    await boot(tester, size: const Size(1500, 800));
    await tester.tap(_button('Vista previa'));
    await tester.pump();
    expect(tester.getSize(find.byType(SongsterrSheet)).width, 1320);
    expect(tester.getSize(find.byKey(_slot)).width, 640);
    expect(tester.getSize(find.byType(SongsterrChoosing)).width, 612);
  });

  testWidgets('con vista previa en ventana de 1100: min(1320, ventana − márgenes)',
      (tester) async {
    await boot(tester, size: const Size(1100, 800));
    await tester.tap(_button('Vista previa'));
    await tester.pump();
    final w = tester.getSize(find.byType(SongsterrSheet)).width;
    expect(w, songsterrSheetWidth(1100, preview: true));
    expect(w, lessThan(1100));
    expect(tester.getSize(find.byType(SongsterrChoosing)).width, 612);
    expect(tester.getSize(find.byKey(_slot)).width, w - 48 - 612 - 20);
  });

  testWidgets('buscando: spinner y texto', (tester) async {
    await boot(tester, patch: {
      'search': {'phase': 'searching'},
      'results': <Object?>[],
      'selected': null,
    });
    expect(find.byType(TfSpinner), findsOneWidget);
    expect(find.text('Buscando en Songsterr…'), findsOneWidget);
    expect(find.text('Otros resultados'), findsNothing);
  });

  testWidgets('fallo de búsqueda: caja de problema con Reintentar', (tester) async {
    final rig = await boot(tester, patch: {
      'search': {
        'phase': 'failed',
        'issue': {
          'kind': 'offline',
          'message': 'x',
          'canRetry': true,
        },
      },
      'results': <Object?>[],
      'selected': null,
    });
    expect(find.byType(SongsterrIssueBox), findsOneWidget);
    expect(find.text('No se pudo conectar con Songsterr. Comprueba la conexión.'),
        findsOneWidget);
    await tester.tap(_button('Reintentar'));
    await tester.runAsync(settle);
    expect(rig.methods, contains('tab.songsterr.retry'));
  });

  testWidgets('enlace vacío deshabilitado; Enter envía link', (tester) async {
    final rig = await boot(tester);
    final use = find.widgetWithText(TfSecondaryButton, 'Usar enlace');
    expect(tester.widget<TfSecondaryButton>(use).onPressed, isNull);
    await tester.tap(find.byType(EditableText));
    await tester.enterText(find.byType(EditableText), ' https://www.songsterr.com/a/wsa/x-tab-s1 ');
    await tester.pump();
    expect(tester.widget<TfSecondaryButton>(use).onPressed, isNotNull);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.runAsync(settle);
    expect(rig.methods, contains('tab.songsterr.link'));
    expect((rig.core.calls.last.params as Map)['link'], 'https://www.songsterr.com/a/wsa/x-tab-s1');
  });

  testWidgets('linkIssue en danger', (tester) async {
    await boot(tester, patch: {
      'linkIssue': {'kind': 'invalidLink', 'message': 'x', 'canRetry': false},
    });
    expect(find.text('Ese enlace no es de Songsterr.'), findsOneWidget);
  });

  testWidgets('Cancelar llama a close', (tester) async {
    final rig = await boot(tester);
    await tester.tap(_button('Cancelar'));
    await tester.runAsync(settle);
    expect(rig.methods, contains('tab.songsterr.close'));
  });

  testWidgets('Usar esta llama a use y Transcribir automáticamente a automatic', (tester) async {
    final rig = await boot(tester);
    await tester.tap(find.text('Usar esta'));
    await tester.runAsync(settle);
    expect(rig.methods, contains('tab.songsterr.use'));
    await tester.tap(_button('Transcribir automáticamente'));
    await tester.runAsync(settle);
    expect(rig.methods, contains('tab.songsterr.automatic'));
  });

  testWidgets('host: abre la hoja con isOpen y la cierra al dejar de estarlo', (tester) async {
    final rig = await boot(tester, child: const SongsterrSheetHost(), open: false);
    expect(find.byType(SongsterrSheet), findsNothing);
    rig.core.emit('tab.songsterr.state', fixture('tab.songsterr.state.result.results.json'));
    await tester.runAsync(settle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(SongsterrSheet), findsOneWidget);
    rig.core.emit('tab.songsterr.state', {
      ...fixture('tab.songsterr.state.result.results.json'),
      'open': false,
    });
    await tester.runAsync(settle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(SongsterrSheet), findsNothing);
  });
}
