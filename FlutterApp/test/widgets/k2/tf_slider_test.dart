import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/widgets/tf_slider.dart';

import '../../support/harness.dart';

// Ancho 116 con pomo de 16: carril útil de 100, así dx = 8 + valor%.
Offset _at(WidgetTester tester, double dx) =>
    tester.getTopLeft(find.byType(TfSlider)) + Offset(dx, 10);

void main() {
  setUpAll(loadTfFonts);

  group('k2 TfSlider', () {
    testWidgets('tap fija el valor y cuantiza al paso', (tester) async {
      final List<double> log = <double>[];
      await pumpK2(
        tester,
        TfSlider(value: 0, min: 0, max: 100, step: 5, width: 116, onChanged: log.add),
      );
      await tester.tapAt(_at(tester, 8 + 52));
      expect(log.last, 50);
    });

    testWidgets('arrastre actualiza y no sale del rango', (tester) async {
      final List<double> log = <double>[];
      await pumpK2(
        tester,
        TfSlider(value: 0, min: 0, max: 100, step: 1, width: 116, onChanged: log.add),
      );
      final TestGesture g = await tester.startGesture(_at(tester, 8));
      await g.moveTo(_at(tester, 8 + 30));
      await g.moveTo(_at(tester, 400));
      await g.up();
      expect(log, isNotEmpty);
      expect(log.every((double v) => v >= 0 && v <= 100), isTrue);
      expect(log.last, 100);
    });

    testWidgets('imán a 0 dentro de la tolerancia', (tester) async {
      final List<double> log = <double>[];
      await pumpK2(
        tester,
        TfSlider(
          value: -20,
          min: -60,
          max: 6,
          snapTo: 0,
          snapTolerance: 1.5,
          width: 116,
          onChanged: log.add,
        ),
      );
      await tester.tapAt(_at(tester, 8 + 92)); // ≈ +1,3 dB
      expect(log.last, 0);
      await tester.tapAt(_at(tester, 8 + 80)); // ≈ -7 dB, fuera del imán
      expect(log.last, isNot(0));
    });

    testWidgets('flechas, Inicio y Fin con el foco', (tester) async {
      final List<double> log = <double>[];
      await pumpK2(
        tester,
        TfSlider(value: 50, min: 0, max: 100, step: 5, width: 116, onChanged: log.add),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      expect(log, <double>[55, 45, 0, 100]);
    });

    testWidgets('deshabilitado no avisa', (tester) async {
      await pumpK2(tester, const TfSlider(value: 0.5, onChanged: null, width: 116));
      await tester.tapAt(_at(tester, 60));
      expect(tester.takeException(), isNull);
    });

    testWidgets('k2 golden deslizador', (tester) async {
      await pumpK2(
        tester,
        Column(
          children: <Widget>[
            k2Row('0 %', TfSlider(value: 0, width: 140, onChanged: (_) {})),
            k2Row('50 %', TfSlider(value: 0.5, width: 140, onChanged: (_) {})),
            k2Row('100 %', TfSlider(value: 1, width: 140, onChanged: (_) {})),
            k2Row('deshabilitado', const TfSlider(value: 0.5, width: 140, onChanged: null)),
          ],
        ),
        size: const Size(300, 180),
      );
      await expectLater(k2Screen(), matchesGoldenFile('goldens/tf_slider.png'));
    });
  });
}
