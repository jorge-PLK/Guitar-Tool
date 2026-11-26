import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/tab.dart';
import 'package:toneforge/features/tab/tab_timing_map.dart';

void main() {
  // compases de 1, 2 y 4 pulsos; pulsos no uniformes
  final m = TabTimingMap(const TabTiming(
    beats: [0, 1, 1.5, 3, 3.5, 4, 5],
    beatsPerBar: [1, 2, 4],
    end: 6,
  ));

  void expectAt(double t, int bar, double f) {
    final p = m.at(t);
    expect(p.bar, bar, reason: 't=$t');
    expect(p.fraction, closeTo(f, 1e-9), reason: 't=$t');
  }

  test('pulso exacto cae en su fracción', () {
    expectAt(0, 0, 0);
    expectAt(1, 1, 0);
    expectAt(1.5, 1, 0.5);
    expectAt(3, 2, 0);
    expectAt(4, 2, 0.5);
    expectAt(5, 2, 0.75);
  });

  test('interpola dentro de un pulso no uniforme', () {
    expectAt(0.5, 0, 0.5);
    expectAt(2.25, 1, 0.75); // mitad del pulso 1.5..3
    expectAt(5.5, 2, 0.875); // último pulso hasta end
  });

  test('límite de compás', () {
    expectAt(0.999, 0, 0.999);
    expectAt(2.999, 1, 0.9996666666666667);
    expectAt(3, 2, 0);
  });

  test('antes del primer pulso y después del fin se fijan', () {
    expectAt(-3, 0, 0);
    expectAt(100, 2, 1.0);
  });

  test('pulso de duración cero no divide por cero', () {
    final z = TabTimingMap(const TabTiming(beats: [0, 0], beatsPerBar: [2], end: 0));
    expect(z.at(5).fraction, 0.5);
  });
}
