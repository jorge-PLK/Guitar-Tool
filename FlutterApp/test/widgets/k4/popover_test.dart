import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_popover.dart';

import '../../support/harness.dart';

Future<TfPopoverController> _mount(WidgetTester tester) async {
  final TfPopoverController controller = TfPopoverController();
  await pumpK4(
    tester,
    Padding(
      padding: const EdgeInsets.all(TfSpace.s40),
      child: Align(
        alignment: Alignment.topLeft,
        child: TfPopover(
          controller: controller,
          popoverBuilder: (_) => Padding(
            padding: const EdgeInsets.all(TfSpace.s16),
            child: Text(
              'Contenido del popover',
              style: TfText.body(13).copyWith(color: TfColors.text),
            ),
          ),
          child: K4Button(label: 'Anclar', onTap: controller.toggle),
        ),
      ),
    ),
  );
  return controller;
}

void main() {
  setUpAll(loadTfFonts);

  group('k4 popover', () {
    testWidgets('se abre y se cierra con Esc', (tester) async {
      final TfPopoverController c = await _mount(tester);
      await tester.tap(find.text('Anclar'));
      await tester.pumpAndSettle();
      expect(find.text('Contenido del popover'), findsOneWidget);
      expect(c.isShowing, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Contenido del popover'), findsNothing);
    });

    testWidgets('se cierra con clic fuera sin pulsar lo de debajo', (tester) async {
      final TfPopoverController c = await _mount(tester);
      await tester.tap(find.text('Anclar'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(500, 300));
      await tester.pumpAndSettle();
      expect(c.isShowing, isFalse);
      expect(find.text('Contenido del popover'), findsNothing);
    });

    testWidgets('un clic dentro no lo cierra', (tester) async {
      final TfPopoverController c = await _mount(tester);
      await tester.tap(find.text('Anclar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Contenido del popover'));
      await tester.pumpAndSettle();
      expect(c.isShowing, isTrue);
    });

    testWidgets('golden abierto', (tester) async {
      await _mount(tester);
      await tester.tap(find.text('Anclar'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(WidgetsApp),
        matchesGoldenFile('goldens/k4_popover.png'),
      );
    });
  });
}
