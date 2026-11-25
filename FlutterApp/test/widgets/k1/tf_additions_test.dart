import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_buttons.dart';

import '../../support/harness.dart';

const Key _frameKey = ValueKey<String>('f');

Widget _frame(Widget child) => Center(child: RepaintBoundary(key: _frameKey, child: child));

/// Alfa del pixel (x, y) del icono de 48x48.
Future<int> _alpha(WidgetTester tester, Widget icon, int x, int y) async {
  await pumpK4(tester, _frame(icon));
  final RenderRepaintBoundary b = tester.renderObject(find.byKey(_frameKey)) as RenderRepaintBoundary;
  final image = await tester.runAsync(() => b.toImage());
  final bytes = (await tester.runAsync(() => image!.toByteData()))!;
  return bytes.getUint8((y * 48 + x) * 4 + 3);
}

void main() {
  setUpAll(loadTfFonts);

  group('TfIconView filled', () {
    testWidgets('playFill: trazo por defecto (hueco en el centro), relleno con filled', (WidgetTester tester) async {
      expect(await _alpha(tester, const TfIconView(TfIcon.playFill, size: 48, color: TfColors.text), 22, 24), 0);
      expect(
        await _alpha(tester, const TfIconView(TfIcon.playFill, size: 48, color: TfColors.text, filled: false), 22, 24),
        0,
      );
      expect(
        await _alpha(tester, const TfIconView(TfIcon.playFill, size: 48, color: TfColors.text, filled: true), 22, 24),
        255,
      );
    });

    testWidgets('pauseFill relleno: centro de la barra izquierda', (WidgetTester tester) async {
      expect(
        await _alpha(tester, const TfIconView(TfIcon.pauseFill, size: 48, color: TfColors.text, filled: true), 15, 24),
        255,
      );
    });
  });

  group('TfSecondaryButton icon y color', () {
    testWidgets('con icono hay TfIconView y el color de etiqueta se aplica', (WidgetTester tester) async {
      int taps = 0;
      await pumpK4(
        tester,
        Center(
          child: TfSecondaryButton(
            label: 'Tablatura',
            height: 34,
            icon: TfIcon.musicQuarternote3,
            color: TfColors.accent,
            onPressed: () => taps++,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(TfIconView), findsOneWidget);
      expect(tester.widget<TfIconView>(find.byType(TfIconView)).color, TfColors.accent);
      expect(tester.widget<Text>(find.text('Tablatura')).style!.color, TfColors.accent);
      await tester.tap(find.text('Tablatura'));
      expect(taps, 1);
    });

    testWidgets('sin parametros nuevos: sin icono, color text; deshabilitado muted', (WidgetTester tester) async {
      await pumpK4(tester, const Center(child: TfSecondaryButton(label: 'Hola', onPressed: null)));
      expect(find.byType(TfIconView), findsNothing);
      expect(tester.widget<Text>(find.text('Hola')).style!.color, TfColors.muted);
      await pumpK4(tester, Center(child: TfSecondaryButton(label: 'Hola', onPressed: () {})));
      expect(tester.widget<Text>(find.text('Hola')).style!.color, TfColors.text);
    });
  });
}
