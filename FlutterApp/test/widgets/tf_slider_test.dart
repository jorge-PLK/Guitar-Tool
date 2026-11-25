import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/widgets/tf_slider.dart';

// Ancho 116, pomo 16 => recorrido útil 100: valor v (0..100) está en dx = 8 + v.
void main() {
  final List<double> changed = <double>[];
  final List<double> ended = <double>[];

  Future<void> pump(WidgetTester t, {double value = 0, double? step}) async {
    await t.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: TfSlider(
            value: value,
            min: 0,
            max: 100,
            step: step,
            width: 116,
            onChanged: changed.add,
            onChangeEnd: ended.add,
          ),
        ),
      ),
    );
  }

  double knobLeft(WidgetTester t) {
    final Iterable<Positioned> ps = t.widgetList<Positioned>(find.byType(Positioned));
    return ps.last.left!;
  }

  setUp(() {
    changed.clear();
    ended.clear();
  });

  // El arrastre arranca tras superar el umbral (18 px), por eso se mueve en dos tramos de 20.
  Offset at(WidgetTester t, double v) {
    final Offset c = t.getCenter(find.byType(TfSlider));
    return Offset(c.dx - 58 + 8 + v, c.dy);
  }

  testWidgets('el arrastre pinta el valor del puntero aunque el padre no cambie value',
      (WidgetTester t) async {
    await pump(t, step: 1);
    final TestGesture g = await t.startGesture(at(t, 10));
    await g.moveBy(const Offset(20, 0)); // el primer movimiento solo acepta el gesto
    await g.moveBy(const Offset(20, 0));
    await t.pump();
    expect(knobLeft(t), closeTo(50, 0.01));
    expect(changed.last, 50);
    await g.up();
    await t.pump();
    expect(ended, <double>[50]);
    expect(knobLeft(t), closeTo(50, 0.01)); // no salta atrás de inmediato
    await t.pump(const Duration(milliseconds: 400));
    expect(knobLeft(t), closeTo(0, 0.01)); // tope: vuelve al valor del padre
  });

  testWidgets('onChanged no se repite con el mismo valor', (WidgetTester t) async {
    await pump(t, step: 10);
    final TestGesture g = await t.startGesture(at(t, 10));
    await g.moveBy(const Offset(20, 0)); // el primer movimiento solo acepta el gesto
    await g.moveBy(const Offset(20, 0));
    await g.moveBy(const Offset(1, 0));
    await g.moveBy(const Offset(1, 0));
    await g.moveBy(const Offset(1, 0));
    await t.pump();
    expect(changed, <double>[50]);
    await g.moveBy(const Offset(10, 0));
    expect(changed, <double>[50, 60]);
    await g.up();
    await t.pump(const Duration(milliseconds: 400));
  });

  testWidgets('un value nuevo del padre libera el valor retenido', (WidgetTester t) async {
    await pump(t, step: 1);
    final Offset c = t.getCenter(find.byType(TfSlider));
    final TestGesture g = await t.startGesture(Offset(c.dx - 58 + 8 + 30, c.dy));
    await g.up();
    await t.pump();
    await pump(t, value: 30, step: 1);
    expect(knobLeft(t), closeTo(30, 0.01));
  });

  testWidgets('cancelar el arrastre termina igual que soltar', (WidgetTester t) async {
    await pump(t, step: 1);
    final TestGesture g = await t.startGesture(at(t, 20));
    await g.moveBy(const Offset(20, 0)); // el primer movimiento solo acepta el gesto
    await g.moveBy(const Offset(20, 0));
    await g.cancel();
    await t.pump();
    expect(ended, <double>[60]);
    await t.pump(const Duration(milliseconds: 400));
  });
}
