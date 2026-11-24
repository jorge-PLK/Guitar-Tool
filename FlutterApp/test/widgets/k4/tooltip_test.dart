import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/widgets/tf_tooltip.dart';

import '../../support/harness.dart';

Future<TestGesture> _mount(WidgetTester tester) async {
  await pumpK4(
    tester,
    const Center(
      child: TfTooltip(
        message: 'Borra la cancion de la biblioteca',
        child: K4Button(label: 'Pasa el raton'),
      ),
    ),
  );
  final TestGesture mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: const Offset(5, 5));
  addTearDown(mouse.removePointer);
  await tester.pump();
  return mouse;
}

void main() {
  setUpAll(loadTfFonts);

  group('k4 tooltip', () {
    testWidgets('aparece tras 1 s y no antes', (tester) async {
      final TestGesture mouse = await _mount(tester);
      await mouse.moveTo(tester.getCenter(find.text('Pasa el raton')));
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.text('Borra la cancion de la biblioteca'), findsNothing);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Borra la cancion de la biblioteca'), findsOneWidget);
    });

    testWidgets('desaparece al salir el raton', (tester) async {
      final TestGesture mouse = await _mount(tester);
      await mouse.moveTo(tester.getCenter(find.text('Pasa el raton')));
      await tester.pump(const Duration(seconds: 2));
      await mouse.moveTo(const Offset(5, 5));
      await tester.pump();
      expect(find.text('Borra la cancion de la biblioteca'), findsNothing);
    });

    testWidgets('si sale antes del retardo no aparece', (tester) async {
      final TestGesture mouse = await _mount(tester);
      await mouse.moveTo(tester.getCenter(find.text('Pasa el raton')));
      await tester.pump(const Duration(milliseconds: 500));
      await mouse.moveTo(const Offset(5, 5));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Borra la cancion de la biblioteca'), findsNothing);
    });

    testWidgets('golden visible', (tester) async {
      final TestGesture mouse = await _mount(tester);
      await mouse.moveTo(tester.getCenter(find.text('Pasa el raton')));
      await tester.pump(const Duration(seconds: 2));
      await expectLater(
        find.byType(WidgetsApp),
        matchesGoldenFile('goldens/k4_tooltip.png'),
      );
    });
  });
}
