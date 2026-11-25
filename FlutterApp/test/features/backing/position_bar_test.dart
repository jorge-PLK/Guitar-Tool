import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/features/backing/widgets/position_bar.dart';
import 'package:toneforge/theme/tokens.dart';

import '../../support/harness.dart';

void main() {
  test('x(t) en extremos y clamp', () {
    expect(PositionBarPainter.xOf(0, 100, 400), 0);
    expect(PositionBarPainter.xOf(50, 100, 400), 200);
    expect(PositionBarPainter.xOf(100, 100, 400), 400);
    expect(PositionBarPainter.xOf(-5, 100, 400), 0);
    expect(PositionBarPainter.xOf(150, 100, 400), 400);
    expect(PositionBarPainter.xOf(10, 0, 400), 0);
  });

  testWidgets('onSeek traduce posición a tiempo', (WidgetTester tester) async {
    final List<double> seeks = <double>[];
    await pumpK5(
      tester,
      SizedBox(
        width: 400,
        child: PositionBar(position: 0, duration: 100, onSeek: seeks.add),
      ),
      size: const Size(440, 60),
    );
    final Rect r = tester.getRect(find.byType(PositionBar));
    expect(r.height, 22);
    await tester.tapAt(Offset(r.left + 100, r.center.dy));
    expect(seeks.last, closeTo(25, 1e-9));
    final TestGesture g = await tester.startGesture(Offset(r.left + 200, r.center.dy));
    await g.moveTo(Offset(r.right + 50, r.center.dy));
    await g.up();
    expect(seeks.last, 100);
  });

  testWidgets('golden con y sin bucle', (WidgetTester tester) async {
    Widget bar(double? ls, double? le) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: TfSpace.s12, vertical: TfSpace.s8),
          child: SizedBox(
            width: 360,
            child: PositionBar(position: 40, duration: 100, loopStart: ls, loopEnd: le),
          ),
        );
    await pumpK5(
      tester,
      Column(mainAxisSize: MainAxisSize.min, children: <Widget>[bar(null, null), bar(25, 70)]),
      size: const Size(400, 90),
    );
    await expectLater(find.byKey(k5Boundary), matchesGoldenFile('goldens/position_bar.png'));
  });
}
