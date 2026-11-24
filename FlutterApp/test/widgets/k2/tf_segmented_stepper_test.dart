import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/widgets/tf_segmented.dart';
import 'package:toneforge/widgets/tf_stepper.dart';

import '../../support/harness.dart';

const List<TfSegment<int>> _segs = <TfSegment<int>>[
  TfSegment<int>(value: 1, label: 'Uno'),
  TfSegment<int>(value: 2, label: 'Dos'),
  TfSegment<int>(value: 3, label: 'Tres'),
];

void main() {
  setUpAll(loadTfFonts);

  group('k2 TfSegmented', () {
    testWidgets('tap elige segmento', (tester) async {
      final List<int> log = <int>[];
      await pumpK2(tester, TfSegmented<int>(segments: _segs, value: 1, onChanged: log.add));
      await tester.tap(find.text('Tres'));
      expect(log, <int>[3]);
    });

    testWidgets('flechas mueven y no pasan de los extremos', (tester) async {
      final List<int> log = <int>[];
      await pumpK2(tester, TfSegmented<int>(segments: _segs, value: 3, onChanged: log.add));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(log, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(log, <int>[2]);
    });

    testWidgets('deshabilitado ignora tap', (tester) async {
      await pumpK2(tester, const TfSegmented<int>(segments: _segs, value: 1, onChanged: null));
      await tester.tap(find.text('Dos'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('ancho fijo reparte a partes iguales', (tester) async {
      await pumpK2(
        tester,
        TfSegmented<int>(segments: _segs, value: 2, onChanged: (_) {}, width: 220),
      );
      expect(tester.getSize(find.byType(TfSegmented<int>)).width, 220);
    });

    testWidgets('k2 golden segmentado', (tester) async {
      await pumpK2(
        tester,
        Column(
          children: <Widget>[
            k2Row('contenido', TfSegmented<int>(segments: _segs, value: 1, onChanged: (_) {})),
            k2Row('220 fijo', TfSegmented<int>(segments: _segs, value: 2, onChanged: (_) {}, width: 160)),
            k2Row('deshabilitado', const TfSegmented<int>(segments: _segs, value: 3, onChanged: null)),
          ],
        ),
        size: const Size(340, 140),
      );
      await expectLater(k2Screen(), matchesGoldenFile('goldens/tf_segmented.png'));
    });
  });

  group('k2 TfStepper', () {
    testWidgets('tap en ▲ y ▼ cambian el valor', (tester) async {
      final List<double> log = <double>[];
      await pumpK2(tester, TfStepper(value: 5, step: 2, onChanged: log.add));
      final Rect r = tester.getRect(find.byType(TfStepper));
      await tester.tapAt(r.topCenter + const Offset(0, 4));
      await tester.tapAt(r.bottomCenter - const Offset(0, 4));
      expect(log, <double>[7, 3]);
    });

    testWidgets('flechas con foco y límites', (tester) async {
      final List<double> log = <double>[];
      await pumpK2(tester, TfStepper(value: 10, max: 10, onChanged: log.add));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      expect(log, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      expect(log, <double>[9]);
    });

    testWidgets('deshabilitado no avisa', (tester) async {
      await pumpK2(tester, const TfStepper(value: 1, onChanged: null));
      await tester.tap(find.byType(TfStepper));
      expect(tester.takeException(), isNull);
    });

    testWidgets('k2 golden stepper', (tester) async {
      await pumpK2(
        tester,
        Column(
          children: <Widget>[
            k2Row('reposo', TfStepper(value: 1, onChanged: (_) {})),
            k2Row('en el máximo', TfStepper(value: 1, max: 1, onChanged: (_) {})),
            k2Row('deshabilitado', const TfStepper(value: 1, onChanged: null)),
          ],
        ),
        size: const Size(220, 140),
      );
      await expectLater(k2Screen(), matchesGoldenFile('goldens/tf_stepper.png'));
    });
  });
}
