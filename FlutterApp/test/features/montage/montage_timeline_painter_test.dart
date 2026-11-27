import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/features/montage/widgets/montage_timeline_painter.dart';
import 'package:toneforge/theme/tokens.dart';

const _lanes = [
  MontageLaneData(
    take: TimeSpan(10, 100),
    presence: [TimeSpan(10, 40), TimeSpan(60, 100)],
    colorIndex: 0,
  ),
  MontageLaneData(
    take: TimeSpan(20, 90),
    presence: [TimeSpan(20, 55)],
    colorIndex: 1,
    hasVideo: false,
  ),
  MontageLaneData(
    take: TimeSpan(45, 70),
    presence: [TimeSpan(48, 66)],
    solo: true,
  ),
];

const _sections = [
  MontageSectionData(name: 'Intro', start: 0, end: 40),
  MontageSectionData(name: 'Solo', start: 40, end: 70, solo: true),
  MontageSectionData(name: 'Final', start: 70, end: 110),
];

MontageTimelineData _data({
  bool plane = false,
  List<MontageCutMark> cuts = const [],
  List<MontagePlaneShot> shots = const [],
  List<TimeSpan> gaps = const [],
}) {
  final axis = MontageTimelineData.axisFor(spanStart: 10, spanEnd: 100, songDuration: 110, barDuration: 2);
  return MontageTimelineData(
    axisStart: axis.start,
    axisEnd: axis.end,
    spanStart: 10,
    spanEnd: 100,
    barDuration: 2,
    fadeIn: true,
    fadeOut: true,
    sections: _sections,
    lanes: _lanes,
    missingCount: 1,
    showPlane: plane,
    planeShots: shots,
    cuts: cuts,
    gaps: gaps,
    cursor: 52,
  );
}

Future<void> _pump(WidgetTester tester, MontageTimelineData d, {double width = 600}) async {
  final h = MontageTimelineGeometry(d, width).totalHeight;
  tester.view.physicalSize = Size(width + 20, h + 20);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          child: ColoredBox(
            color: TfColors.card,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: CustomPaint(size: Size(width, h), painter: MontageTimelinePainter(d)),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('geometría', () {
    test('eje: margen del 10 % con mínimo de un compás, acotado al tema', () {
      final a = MontageTimelineData.axisFor(spanStart: 10, spanEnd: 100, songDuration: 110, barDuration: 2);
      expect(a.start, 1);
      expect(a.end, 109);
      final b = MontageTimelineData.axisFor(spanStart: 10, spanEnd: 20, songDuration: 200, barDuration: 4);
      expect((b.start, b.end), (6, 24));
      final c = MontageTimelineData.axisFor(spanStart: 0, spanEnd: 100, songDuration: 100);
      expect((c.start, c.end), (0, 100));
    });

    test('timeToX y xToTime son inversos y xToTime acota', () {
      final g = MontageTimelineGeometry(_data(), 540);
      expect(g.timeToX(1), 0);
      expect(g.timeToX(109), 540);
      expect(g.timeToX(55), 270);
      expect(g.xToTime(270), 55);
      expect(g.xToTime(-50), 1);
      expect(g.xToTime(9999), 109);
    });

    test('filas: banda, secciones, plano, carriles y vacíos', () {
      final g = MontageTimelineGeometry(_data(plane: true), 540);
      expect(g.bandRect.height, 8);
      expect(g.sectionsRect.top, 14);
      expect(g.planeRect!.top, 14 + 24 + 6);
      expect(g.laneRect(0).top, g.planeRect!.top + 36);
      expect(g.laneRect(2).top, g.planeRect!.top + 36 * 3);
      expect(g.missingRect(0).top, g.planeRect!.top + 36 * 4);
      expect(g.totalHeight, 8 + 24 + 5 * 30 + 6 * 6);
      expect(g.missingRect(0).bottom, g.totalHeight);
      final sin = MontageTimelineGeometry(_data(), 540);
      expect(sin.planeRect, isNull);
      expect(sin.laneRect(0).top, 14 + 24 + 6);
      expect(sin.totalHeight, 8 + 24 + 4 * 30 + 5 * 6);
    });

    test('marcas de corte: 8 de ancho, centradas, hit-test', () {
      final d = _data(plane: true, cuts: const [MontageCutMark(time: 55, covered: true), MontageCutMark(time: 80, covered: false)]);
      final g = MontageTimelineGeometry(d, 540);
      final r = g.cutMarkRect(0);
      expect(r.width, 8);
      expect(r.height, 30);
      expect(r.center.dx, 270);
      expect(r.top, g.planeRect!.top);
      expect(g.cutMarkRect(0, time: 1).center.dx, 0);
      expect(g.cutAt(r.center), 0);
      expect(g.cutAt(g.cutMarkRect(1).center), 1);
      expect(g.cutAt(const Offset(10, 60)), isNull);
      expect(MontageTimelineGeometry(_data(), 540).cutAt(r.center), isNull);
    });
  });

  testWidgets('3 carriles (sin toma, solista, huecos rayados) y cursor (golden)', (tester) async {
    await _pump(tester, _data(gaps: const [TimeSpan(40, 60)]));
    await expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile('goldens/montage_timeline_lanes.png'));
  });

  testWidgets('carril Plano con dos cortes, uno cubierto y otro no (golden)', (tester) async {
    await _pump(
      tester,
      _data(
        plane: true,
        shots: const [
          MontagePlaneShot(start: 10, end: 40, laneIndex: 0),
          MontagePlaneShot(start: 40, end: 70, laneIndex: 2),
          MontagePlaneShot(start: 70, end: 85),
          MontagePlaneShot(start: 85, end: 100, laneIndex: 1, black: true),
        ],
        cuts: const [MontageCutMark(time: 40, covered: true), MontageCutMark(time: 70, covered: false)],
      ),
    );
    await expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile('goldens/montage_timeline_plane.png'));
  });
}
