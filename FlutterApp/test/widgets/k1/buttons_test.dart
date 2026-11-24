import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_buttons.dart';

import '../../support/harness.dart';

void main() {
  setUpAll(loadTfFonts);

  Future<void> golden(WidgetTester t, String name) =>
      expectLater(find.byKey(const ValueKey<String>('k1')), matchesGoldenFile('goldens/$name.png'));

  final Map<String, Widget Function(VoidCallback?)> cases = <String, Widget Function(VoidCallback?)>{
    'primary': (VoidCallback? f) => TfPrimaryButton(label: 'Guardar', onPressed: f),
    'apply': (VoidCallback? f) => TfPrimaryButton.apply(label: 'Aplicar', onPressed: f),
    'secondary': (VoidCallback? f) => TfSecondaryButton(label: 'Cancelar', onPressed: f),
    'secondary36': (VoidCallback? f) => TfSecondaryButton(label: 'Cancelar', height: TfSize.controlMd, onPressed: f),
    'icon_row': (VoidCallback? f) => TfIconButton(icon: TfIcon.trash, onPressed: f),
    'icon_secondary': (VoidCallback? f) =>
        TfIconButton(icon: TfIcon.folder, kind: TfIconButtonKind.secondary, onPressed: f),
    'icon_nudge': (VoidCallback? f) => TfIconButton(icon: TfIcon.chevronRight, kind: TfIconButtonKind.nudge, onPressed: f),
  };

  group('k1 botones', () {
    for (final MapEntry<String, Widget Function(VoidCallback?)> e in cases.entries) {
      testWidgets('${e.key}: reposo', (WidgetTester t) async {
        await t.pumpWidget(k1Frame(e.value(() {})));
        await golden(t, 'k1_${e.key}_rest');
      });
      testWidgets('${e.key}: pulsado', (WidgetTester t) async {
        await t.pumpWidget(k1Frame(e.value(() {})));
        final TestGesture g = await pressOn(t, find.byType(GestureDetector));
        await golden(t, 'k1_${e.key}_pressed');
        await g.up();
      });
      testWidgets('${e.key}: deshabilitado', (WidgetTester t) async {
        await t.pumpWidget(k1Frame(e.value(null)));
        await golden(t, 'k1_${e.key}_disabled');
      });
    }

    testWidgets('icon_row: hover pinta danger', (WidgetTester t) async {
      await t.pumpWidget(k1Frame(TfIconButton(icon: TfIcon.trash, onPressed: () {})));
      final TestGesture g = await hoverOn(t, find.byType(GestureDetector));
      await golden(t, 'k1_icon_row_hover');
      await g.removePointer();
    });

    testWidgets('medidas: primario 44, apply 28, secundario 44/36, iconos', (WidgetTester t) async {
      Future<Size> size(Widget w) async {
        await t.pumpWidget(k1Frame(w));
        return t.getSize(find.byType(GestureDetector));
      }

      expect((await size(cases['primary']!(() {}))).height, 44);
      expect((await size(cases['apply']!(() {}))).height, 28);
      expect((await size(cases['secondary']!(() {}))).height, 44);
      expect((await size(cases['secondary36']!(() {}))).height, 36);
      expect(await size(cases['icon_row']!(() {})), const Size(36, 36));
      expect(await size(cases['icon_nudge']!(() {})), const Size(30, 24));
      expect(await size(cases['icon_secondary']!(() {})), const Size(46, 36));
    });

    testWidgets('toque llama; deshabilitado no', (WidgetTester t) async {
      int n = 0;
      await t.pumpWidget(k1Frame(TfPrimaryButton(label: 'Ok', onPressed: () => n++)));
      await t.tap(find.byType(TfPrimaryButton));
      expect(n, 1);
      await t.pumpWidget(k1Frame(const TfPrimaryButton(label: 'Ok', onPressed: null)));
      await t.tap(find.byType(TfPrimaryButton));
      expect(n, 1);
    });

    testWidgets('Intro y Espacio activan con foco; sin anillo', (WidgetTester t) async {
      int n = 0;
      await t.pumpWidget(k1Frame(TfSecondaryButton(label: 'Ok', onPressed: () => n++)));
      Focus.of(t.element(find.byType(GestureDetector))).requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      expect(n, 2);
    });

    testWidgets('deshabilitado no recibe foco', (WidgetTester t) async {
      await t.pumpWidget(k1Frame(const TfSecondaryButton(label: 'Ok', onPressed: null)));
      final FocusNode node = Focus.of(t.element(find.byType(GestureDetector)));
      node.requestFocus();
      await t.pump();
      expect(node.hasPrimaryFocus, isFalse);
    });
  });
}
