import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/widgets/tf_alert.dart';

import '../../support/harness.dart';

const String _msg = 'Esta accion no se puede deshacer.';

Future<void> _mountAlert(WidgetTester tester, List<String> log) async {
  await pumpK4(
    tester,
    Center(
      child: Builder(
        builder: (BuildContext context) => K4Button(
          label: 'Abrir',
          onTap: () async {
            await showTfAlert(
              context: context,
              title: 'Aviso',
              message: _msg,
              okLabel: 'Aceptar',
            );
            log.add('cerrada');
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

Future<void> _mountConfirm(
  WidgetTester tester,
  List<bool> log, {
  bool destructive = true,
}) async {
  await pumpK4(
    tester,
    Center(
      child: Builder(
        builder: (BuildContext context) => K4Button(
          label: 'Abrir',
          onTap: () async {
            log.add(
              await showTfConfirm(
                context: context,
                title: 'Borrar cancion',
                message: _msg,
                confirmLabel: 'Borrar',
                cancelLabel: 'Cancelar',
                destructive: destructive,
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadTfFonts);

  group('k4 alerta', () {
    testWidgets('Esc e Intro cierran la alerta', (tester) async {
      for (final LogicalKeyboardKey key in <LogicalKeyboardKey>[
        LogicalKeyboardKey.escape,
        LogicalKeyboardKey.enter,
      ]) {
        final List<String> log = <String>[];
        await _mountAlert(tester, log);
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
        expect(log, <String>['cerrada']);
        expect(find.text('Aviso'), findsNothing);
      }
    });

    testWidgets('confirmar: Intro devuelve true y Esc false', (tester) async {
      final List<bool> log = <bool>[];
      await _mountConfirm(tester, log);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(log, <bool>[true, false]);
    });

    testWidgets('los botones devuelven su valor', (tester) async {
      final List<bool> log = <bool>[];
      await _mountConfirm(tester, log);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Borrar').last);
      await tester.pumpAndSettle();
      expect(log, <bool>[false, true]);
    });

    testWidgets('golden alerta', (tester) async {
      await _mountAlert(tester, <String>[]);
      await expectLater(
        find.byType(WidgetsApp),
        matchesGoldenFile('goldens/k4_alert.png'),
      );
    });

    testWidgets('golden confirmacion destructiva', (tester) async {
      await _mountConfirm(tester, <bool>[]);
      await expectLater(
        find.byType(WidgetsApp),
        matchesGoldenFile('goldens/k4_confirm.png'),
      );
    });
  });
}
