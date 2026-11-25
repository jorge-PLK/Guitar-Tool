import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/features/backing/widgets/position_bar.dart';

import 'transport_test.dart' show core, pumpRows;

double _barPosition(WidgetTester tester) => tester.widget<PositionBar>(find.byType(PositionBar)).position;

Future<void> _emit(WidgetTester tester, double s, {required bool playing}) async {
  core.emit('study.position', <String, Object?>{'seconds': s, 'playing': playing});
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  void longStudy(Map<String, Object?> o) {
    o['duration'] = 200;
    (o['transport']! as Map<String, Object?>)['duration'] = 200;
    (o['transport']! as Map<String, Object?>)['rate'] = 1.0;
  }

  testWidgets('avanza entre eventos mientras suena', (tester) async {
    await pumpRows(tester, tweak: longStudy);
    await _emit(tester, 10, playing: true);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 500));
    expect(_barPosition(tester), closeTo(10.5, 0.05));
    expect(find.textContaining('0:10 / 3:20', findRichText: true), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.textContaining('0:11 / 3:20', findRichText: true), findsOneWidget);
  });

  testWidgets('se para con pausa', (tester) async {
    await pumpRows(tester, tweak: longStudy);
    await _emit(tester, 10, playing: true);
    await tester.pump(const Duration(milliseconds: 300));
    await _emit(tester, 10.3, playing: false);
    await tester.pump(const Duration(seconds: 2));
    expect(_barPosition(tester), 10.3);
  });

  testWidgets('el jitter pequeño hacia atrás no retrocede el cabezal', (tester) async {
    await pumpRows(tester, tweak: longStudy);
    await _emit(tester, 10, playing: true);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 500));
    final double before = _barPosition(tester);
    await _emit(tester, before - 0.03, playing: true);
    expect(_barPosition(tester), greaterThanOrEqualTo(before));
  });

  testWidgets('no pasa del final del bucle', (tester) async {
    await pumpRows(tester, tweak: (o) {
      longStudy(o);
      (o['transport']! as Map<String, Object?>)['loop'] = <String, Object?>{'start': 5.0, 'end': 8.0};
    });
    await _emit(tester, 7.9, playing: true);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(seconds: 2));
    expect(_barPosition(tester), 8.0);
  });

  testWidgets('el arrastre muestra la posición del puntero sin respuesta del núcleo', (tester) async {
    late Object? transport;
    await pumpRows(tester, tweak: (o) {
      longStudy(o);
      transport = o['transport'];
    });
    core.result('study.seek', transport);
    final Rect r = tester.getRect(find.byType(PositionBar));
    final TestGesture g = await tester.startGesture(Offset(r.left + r.width * 0.25, r.center.dy));
    await g.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(_barPosition(tester), closeTo(70, 1));
    await tester.pump(const Duration(milliseconds: 200));
    await g.moveBy(Offset(r.width * 0.5 - 40, 0));
    await tester.pump(const Duration(milliseconds: 200));
    expect(_barPosition(tester), closeTo(150, 1));
    await g.up();
  });
}
