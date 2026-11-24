import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/widgets/tf_sheet.dart';

import '../../support/harness.dart';

const String _body =
    'Elige la carpeta donde guardar tus proyectos. Podras cambiarla despues en Ajustes.';

Widget _sheet(double width, {double padding = 24}) => TfSheetScaffold(
      width: width,
      padding: padding,
      title: 'Bienvenido',
      body: const Text(_body),
      actions: const <Widget>[
        K4Button(label: 'Cancelar'),
        K4Button(label: 'Continuar', primary: true),
      ],
    );

Future<void> _open(
  WidgetTester tester, {
  double width = 480,
  VoidCallback? onCancel,
  VoidCallback? onPrimary,
  FocusNode? behind,
}) async {
  await pumpK4(
    tester,
    Center(
      child: Builder(
        builder: (BuildContext context) => K4Button(
          label: 'Abrir',
          focusNode: behind,
          onTap: () => showTfSheet<void>(
            context: context,
            onCancel: onCancel,
            onPrimary: onPrimary,
            builder: (_) => _sheet(width),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadTfFonts);

  group('k4 hoja', () {
    testWidgets('Esc llama a onCancel e Intro a onPrimary', (tester) async {
      int cancels = 0;
      int primaries = 0;
      await _open(
        tester,
        onCancel: () => cancels++,
        onPrimary: () => primaries++,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(cancels, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(primaries, 1);
    });

    testWidgets('Esc sin callback cierra la hoja', (tester) async {
      await _open(tester);
      expect(find.byType(TfSheetScaffold), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(TfSheetScaffold), findsNothing);
    });

    testWidgets('el foco queda atrapado dentro de la hoja', (tester) async {
      final FocusNode behind = FocusNode();
      addTearDown(behind.dispose);
      await _open(tester, behind: behind);
      for (int i = 0; i < 6; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(behind.hasFocus, isFalse);
        final BuildContext? ctx = FocusManager.instance.primaryFocus?.context;
        expect(ctx, isNotNull);
        expect(ctx!.findAncestorWidgetOfExactType<TfSheetScaffold>(), isNotNull);
      }
    });

    testWidgets('golden 480', (tester) async {
      await _open(tester, width: 480);
      await expectLater(
        find.byType(WidgetsApp),
        matchesGoldenFile('goldens/k4_sheet_480.png'),
      );
    });

    testWidgets('golden 540', (tester) async {
      await _open(tester, width: 540);
      await expectLater(
        find.byType(WidgetsApp),
        matchesGoldenFile('goldens/k4_sheet_540.png'),
      );
    });
  });
}
