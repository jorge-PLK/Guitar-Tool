import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/widgets/tf_alert.dart';

import '../../support/harness.dart';

Future<void> _open(WidgetTester tester, {required String confirm, bool destructive = false}) async {
  await pumpK4(
    tester,
    Center(
      child: Builder(
        builder: (BuildContext context) => K4Button(
          label: 'Abrir',
          onTap: () => showTfConfirm(
            context: context,
            title: 'Titulo',
            confirmLabel: confirm,
            cancelLabel: 'Cancelar',
            destructive: destructive,
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

  group('TfAlert: la fila de botones no desborda con fuentes reales', () {
    for (final (String, bool) c in <(String, bool)>[
      ('Pasar a automática', false),
      ('Eliminar', true),
      ('Confirmar', false),
    ]) {
      testWidgets('confirmar "${c.$1}"', (WidgetTester tester) async {
        await _open(tester, confirm: c.$1, destructive: c.$2);
        expect(tester.takeException(), isNull);
        expect(find.text(c.$1), findsOneWidget);
      });
    }
  });
}
