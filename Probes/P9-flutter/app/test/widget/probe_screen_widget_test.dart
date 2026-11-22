import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tf_probe/probe6_snapshot.dart';

void main() {
  testWidgets('la pantalla de prueba muestra el título y 32 celdas', (t) async {
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: ProbeScreen(),
      ),
    );
    expect(find.text('ToneForge Afinador 0123'), findsOneWidget);
    expect(find.text('31'), findsOneWidget);
  });
}
