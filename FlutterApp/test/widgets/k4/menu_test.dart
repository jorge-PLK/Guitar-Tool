import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_menu.dart';

import '../../support/harness.dart';

List<TfMenuEntry> _entries(List<String> log) => <TfMenuEntry>[
      TfMenuItem(label: 'Renombrar', onSelected: () => log.add('renombrar')),
      TfMenuItem(
        label: 'Duplicar',
        enabled: false,
        onSelected: () => log.add('duplicar'),
      ),
      TfMenuItem(label: 'Exportar', onSelected: () => log.add('exportar')),
      const TfMenuDivider(),
      TfMenuItem(
        label: 'Borrar',
        destructive: true,
        onSelected: () => log.add('borrar'),
      ),
    ];

Future<void> _mount(WidgetTester tester, List<String> log) async {
  await pumpK4(
    tester,
    Padding(
      padding: const EdgeInsets.all(TfSpace.s40),
      child: Align(
        alignment: Alignment.topLeft,
        child: TfMenu(
          entries: _entries(log),
          builder: (_, VoidCallback toggle) =>
              K4Button(label: 'Opciones', onTap: toggle),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Opciones'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadTfFonts);

  group('k4 menu', () {
    testWidgets('abajo salta la entrada deshabilitada e Intro elige', (tester) async {
      final List<String> log = <String>[];
      await _mount(tester, log);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(log, <String>['exportar']);
      expect(find.text('Renombrar'), findsNothing);
    });

    testWidgets('arriba desde el inicio va a la ultima y envuelve', (tester) async {
      final List<String> log = <String>[];
      await _mount(tester, log);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(log, <String>['borrar']);
    });

    testWidgets('Esc cierra sin elegir', (tester) async {
      final List<String> log = <String>[];
      await _mount(tester, log);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Renombrar'), findsNothing);
      expect(log, isEmpty);
    });

    testWidgets('la entrada deshabilitada no dispara con clic', (tester) async {
      final List<String> log = <String>[];
      await _mount(tester, log);
      await tester.tap(find.text('Duplicar'));
      await tester.pumpAndSettle();
      expect(log, isEmpty);
      expect(find.text('Duplicar'), findsOneWidget);
    });

    testWidgets('clic en una entrada la dispara y cierra', (tester) async {
      final List<String> log = <String>[];
      await _mount(tester, log);
      await tester.tap(find.text('Borrar'));
      await tester.pumpAndSettle();
      expect(log, <String>['borrar']);
      expect(find.text('Borrar'), findsNothing);
    });

    testWidgets('menu contextual con clic secundario', (tester) async {
      final List<String> log = <String>[];
      await pumpK4(
        tester,
        TfContextMenu(
          entries: _entries(log),
          child: const SizedBox.expand(),
        ),
      );
      await tester.tapAt(
        const Offset(100, 80),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Exportar'), findsOneWidget);
      await tester.tap(find.text('Exportar'));
      await tester.pumpAndSettle();
      expect(log, <String>['exportar']);
    });

    testWidgets('golden abierto con separador y destructiva', (tester) async {
      await _mount(tester, <String>[]);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await expectLater(
        find.byType(WidgetsApp),
        matchesGoldenFile('goldens/k4_menu.png'),
      );
    });
  });
}
