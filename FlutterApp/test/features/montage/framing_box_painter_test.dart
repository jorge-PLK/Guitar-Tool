import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/features/montage/widgets/framing_box_painter.dart';
import 'package:toneforge/theme/tokens.dart';

Future<void> _pump(WidgetTester tester, FramingBoxData d) async {
  tester.view.physicalSize = const Size(320, 180);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          child: ColoredBox(
            color: TfColors.previewDeep,
            child: CustomPaint(size: const Size(320, 180), painter: FramingBoxPainter(d)),
          ),
        ),
      ),
    ),
  );
}

void main() {
  const box = Rect.fromLTWH(0.25, 0.1, 0.4, 0.7);

  test('geometría: rect de la caja y punto de escala en la esquina inferior derecha', () {
    const g = FramingBoxGeometry(box, Size(320, 180));
    expect(g.boxRect, const Rect.fromLTWH(80, 18, 128, 126));
    expect(g.handleCenter, const Offset(208, 144));
    expect(g.handleRect, const Rect.fromLTWH(201, 137, 14, 14));
    expect(g.hitsHandle(const Offset(220, 150)), isTrue);
    expect(g.hitsHandle(const Offset(240, 150)), isFalse);
  });

  testWidgets('modo fijo: caja con punto de escala (golden)', (tester) async {
    await _pump(tester, const FramingBoxData(box: box, showScaleHandle: true));
    await expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile('goldens/framing_box_fixed.png'));
  });

  testWidgets('modo seguir: caja sin punto (golden)', (tester) async {
    await _pump(tester, const FramingBoxData(box: box, showScaleHandle: false));
    await expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile('goldens/framing_box_follow.png'));
  });
}
