import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/widgets/tf_checkbox.dart';
import 'package:toneforge/widgets/tf_switch.dart';

import '../../support/harness.dart';

void main() {
  setUpAll(loadTfFonts);

  group('k2 TfSwitch', () {
    testWidgets('tap conmuta y avisa', (tester) async {
      final List<bool> log = <bool>[];
      await pumpK2(tester, TfSwitch(value: false, onChanged: log.add));
      await tester.tap(find.byType(TfSwitch));
      expect(log, <bool>[true]);
    });

    testWidgets('Tab enfoca y Espacio conmuta', (tester) async {
      final List<bool> log = <bool>[];
      await pumpK2(tester, TfSwitch(value: true, onChanged: log.add, small: true));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(log, <bool>[false]);
    });

    testWidgets('deshabilitado ignora tap y teclado', (tester) async {
      await pumpK2(tester, const TfSwitch(value: false, onChanged: null));
      await tester.tap(find.byType(TfSwitch));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(tester.takeException(), isNull);
    });

    testWidgets('k2 golden interruptor', (tester) async {
      await pumpK2(
        tester,
        Column(
          children: <Widget>[
            k2Row('reposo', TfSwitch(value: false, onChanged: (_) {})),
            k2Row('encendido', TfSwitch(value: true, onChanged: (_) {})),
            k2Row('pequeño off', TfSwitch(value: false, onChanged: (_) {}, small: true)),
            k2Row('pequeño on', TfSwitch(value: true, onChanged: (_) {}, small: true)),
            k2Row('deshabilitado', const TfSwitch(value: true, onChanged: null)),
          ],
        ),
        size: const Size(240, 220),
      );
      await expectLater(k2Screen(), matchesGoldenFile('goldens/tf_switch.png'));
    });
  });

  group('k2 TfCheckbox', () {
    testWidgets('tap en la etiqueta conmuta', (tester) async {
      final List<bool> log = <bool>[];
      await pumpK2(tester, TfCheckbox(value: false, onChanged: log.add, label: 'Metrónomo'));
      await tester.tap(find.text('Metrónomo'));
      expect(log, <bool>[true]);
    });

    testWidgets('Tab y Espacio conmutan', (tester) async {
      final List<bool> log = <bool>[];
      await pumpK2(tester, TfCheckbox(value: true, onChanged: log.add, label: 'x'));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(log, <bool>[false]);
    });

    testWidgets('deshabilitada no avisa', (tester) async {
      await pumpK2(tester, const TfCheckbox(value: false, onChanged: null, label: 'x'));
      await tester.tap(find.text('x'));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(tester.takeException(), isNull);
    });

    testWidgets('k2 golden casilla', (tester) async {
      await pumpK2(
        tester,
        Column(
          children: <Widget>[
            k2Row('reposo', TfCheckbox(value: false, onChanged: (_) {}, label: 'Cuenta atrás')),
            k2Row('marcada', TfCheckbox(value: true, onChanged: (_) {}, label: 'Cuenta atrás')),
            k2Row('sin etiqueta', TfCheckbox(value: true, onChanged: (_) {})),
            k2Row('deshabilitada', const TfCheckbox(value: true, onChanged: null, label: 'Cuenta atrás')),
          ],
        ),
        size: const Size(300, 180),
      );
      await expectLater(k2Screen(), matchesGoldenFile('goldens/tf_checkbox.png'));
    });
  });
}
