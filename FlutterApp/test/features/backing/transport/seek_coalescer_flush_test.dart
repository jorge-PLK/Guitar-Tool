import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/features/backing/widgets/loop_marking.dart';
import 'package:toneforge/features/backing/widgets/position_bar.dart';

void main() {
  testWidgets('flush sends the pending seek at once, without waiting for the interval', (
    WidgetTester tester,
  ) async {
    final List<double> sent = <double>[];
    final SeekCoalescer seek = SeekCoalescer((double s) async => sent.add(s));

    seek.request(1);
    await tester.pump(const Duration(milliseconds: 1));
    seek.request(2);
    seek.request(3);
    await tester.pump(const Duration(milliseconds: 10));
    expect(sent, <double>[1]);

    seek.flush();
    expect(sent, <double>[1, 3]);

    await tester.pump(const Duration(milliseconds: 500));
    expect(sent, <double>[1, 3]);
  });

  testWidgets('flush without a pending value sends nothing duplicated', (
    WidgetTester tester,
  ) async {
    final List<double> sent = <double>[];
    final SeekCoalescer seek = SeekCoalescer((double s) async => sent.add(s));

    seek.request(5);
    await tester.pump(const Duration(milliseconds: 1));
    seek.flush();
    seek.flush();
    await tester.pump(const Duration(milliseconds: 500));
    expect(sent, <double>[5]);
  });

  testWidgets('releasing a drag on PositionBar flushes the final seek immediately', (
    WidgetTester tester,
  ) async {
    final List<double> sent = <double>[];
    final SeekCoalescer seek = SeekCoalescer((double s) async => sent.add(s));

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 200,
            child: PositionBar(
              position: 0,
              duration: 100,
              onSeek: seek.request,
              onSeekEnd: seek.flush,
            ),
          ),
        ),
      ),
    );

    final Offset origin = tester.getTopLeft(find.byType(PositionBar));
    final TestGesture gesture = await tester.startGesture(origin + const Offset(20, 11));
    await tester.pump();
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();

    // Dentro de la ventana de 120 ms: solo ha salido el primer seek, el final está pendiente.
    final int sentBeforeRelease = sent.length;
    expect(sent.last, isNot(50.0));

    await gesture.up();
    await tester.pump();

    // Final x=100 de 200 px sobre duración 100 → 50 s, enviado sin avanzar el reloj.
    expect(sent.length, sentBeforeRelease + 1);
    expect(sent.last, 50.0);

    await tester.pump(const Duration(milliseconds: 500));
    expect(sent.length, sentBeforeRelease + 1);
  });
}
