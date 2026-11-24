import 'dart:ui' as ui;

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/widgets/tf_fader.dart';
import 'package:toneforge/widgets/tf_level_bar.dart';
import 'package:toneforge/widgets/tf_toggle_button.dart';

import '../../support/harness.dart';

String _fmt(double d) => '${d.toStringAsFixed(1)} dB';

void main() {
  group('k3 fader', () {
    test('dbAt: extremos, centro e imán', () {
      expect(TfFader.dbAt(-50, 150), 6);
      expect(TfFader.dbAt(999, 150), -60);
      expect(TfFader.dbAt(0, 150), 6);
      expect(TfFader.dbAt(150, 150), -60);
      // 0 dB está a 6/66 del alto desde arriba: 150 * 6 / 66.
      const double y0 = 150 * 6 / 66;
      expect(TfFader.dbAt(y0, 150), 0);
      expect(TfFader.dbAt(y0 + 3, 150), 0); // ~ -1,3 dB: dentro del imán
      expect(TfFader.dbAt(y0 + 5, 150), isNot(0)); // ~ -2,2 dB: fuera
    });

    testWidgets('arrastre sin tolerancia: sigue al puntero desde el primer píxel', (t) async {
      final List<double> got = <double>[];
      await pumpK3(t, TfFader(dB: -20, onChanged: got.add, semanticLabel: 'Volumen', semanticValue: _fmt));
      final Rect r = t.getRect(find.byType(TfFader));
      final TestGesture g = await t.startGesture(Offset(r.center.dx, r.top + 75));
      expect(got.last, closeTo(-27, 0.01)); // mitad del carril: −27 dB
      await g.moveBy(const Offset(0, 3)); // por debajo de la tolerancia de arrastre de Flutter
      expect(got, hasLength(2));
      expect(got.last, lessThan(-27));
      await g.moveTo(Offset(r.center.dx, r.top - 40));
      expect(got.last, 6);
      await g.moveTo(Offset(r.center.dx, r.bottom + 40));
      expect(got.last, -60);
      await g.up();
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('doble clic = 0 dB', (t) async {
      final List<double> got = <double>[];
      await pumpK3(t, TfFader(dB: -20, onChanged: got.add, semanticLabel: 'Volumen', semanticValue: _fmt));
      final Offset c = t.getCenter(find.byType(TfFader));
      await t.tapAt(c);
      await t.pump(const Duration(milliseconds: 50));
      await t.tapAt(c);
      await t.pump(const Duration(seconds: 1));
      expect(got.last, 0);
    });

    testWidgets('teclado: flechas ±1 dB y límites', (t) async {
      double v = 5.5;
      await pumpK3(
        t,
        StatefulBuilder(
          builder: (_, StateSetter set) => TfFader(
            dB: v,
            autofocus: true,
            onChanged: (double d) => set(() => v = d),
            semanticLabel: 'Volumen',
            semanticValue: _fmt,
          ),
        ),
      );
      await t.pump();
      Future<void> key(LogicalKeyboardKey k) async {
        await t.sendKeyEvent(k);
        await t.pump();
      }

      await key(LogicalKeyboardKey.arrowUp);
      expect(v, 6); // tope
      await key(LogicalKeyboardKey.arrowUp);
      expect(v, 6);
      await key(LogicalKeyboardKey.arrowDown);
      expect(v, 5);
      await key(LogicalKeyboardKey.arrowLeft);
      expect(v, 4);
      for (int i = 0; i < 70; i++) {
        await key(LogicalKeyboardKey.arrowDown);
      }
      expect(v, -60);
    });

    testWidgets('semántica: valor, incremento y decremento de 1 dB', (t) async {
      final SemanticsHandle h = t.ensureSemantics();
      final List<double> got = <double>[];
      await pumpK3(t, TfFader(dB: -6, onChanged: got.add, semanticLabel: 'Volumen', semanticValue: _fmt));
      final SemanticsNode n = t.getSemantics(find.byType(TfFader));
      expect(n.label, 'Volumen');
      expect(n.value, '-6.0 dB');
      expect(n.increasedValue, '-5.0 dB');
      expect(n.decreasedValue, '-7.0 dB');
      t.semantics.performAction(find.semantics.byLabel('Volumen'), SemanticsAction.increase);
      t.semantics.performAction(find.semantics.byLabel('Volumen'), SemanticsAction.decrease);
      expect(got, <double>[-5, -7]);
      h.dispose();
    });
  });

  group('k3 level bar', () {
    test('fracción a -60 / -30 / 0 dB, sin medidor y dim', () {
      expect(TfLevelBar.fractionFor(-60), 0);
      expect(TfLevelBar.fractionFor(-30), 0.5);
      expect(TfLevelBar.fractionFor(0), 1);
      expect(TfLevelBar.fractionFor(6), 1);
      expect(TfLevelBar.fractionFor(-80), 0);
      expect(TfLevelBar.fractionFor(null), 0);
      expect(TfLevelBar.fractionFor(-10, dim: true), 0);
    });
  });

  group('k3 toggle', () {
    testWidgets('tamaños 36 y 28, pulsación y semántica', (t) async {
      final SemanticsHandle h = t.ensureSemantics();
      int taps = 0;
      await pumpK3(
        t,
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TfToggleButton(text: 'M', on: true, onPressed: () => taps++, semanticLabel: 'Silenciar'),
            TfToggleButton(
              text: 'S',
              on: false,
              onPressed: () => taps++,
              semanticLabel: 'Solo',
              size: TfToggleSize.small,
            ),
          ],
        ),
      );
      expect(t.getSize(find.byType(TfToggleButton).first), const Size(36, 36));
      expect(t.getSize(find.byType(TfToggleButton).last), const Size(28, 28));
      await t.tap(find.text('M'));
      await t.tap(find.text('S'));
      expect(taps, 2);
      expect(t.getSemantics(find.byType(TfToggleButton).first).label, 'Silenciar');
      expect(t.getSemantics(find.byType(TfToggleButton).first).flagsCollection.isToggled, ui.Tristate.isTrue);
      h.dispose();
    });
  });
}
