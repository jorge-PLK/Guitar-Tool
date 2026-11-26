import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/features/record/input_meter.dart';
import 'package:toneforge/features/record/record_audio_actions.dart';
import 'package:toneforge/features/record/widgets/horizontal_level_painter.dart';
import 'package:toneforge/features/record/widgets/vertical_level_painter.dart';
import 'package:toneforge/theme/tokens.dart';

/// Color del pixel (x, y) del primer RepaintBoundary tras pintar [meter].
Future<Color> _pixel(WidgetTester t, Widget meter, int x, int y) async {
  final GlobalKey key = GlobalKey();
  await t.pumpWidget(Directionality(
    textDirection: TextDirection.ltr,
    child: Align(alignment: Alignment.topLeft, child: RepaintBoundary(key: key, child: meter)),
  ));
  return (await t.runAsync<Color>(() async {
    final RenderRepaintBoundary b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final ui.Image img = await b.toImage();
    final ByteData d = (await img.toByteData())!;
    final int o = (y * img.width + x) * 4;
    return Color.fromARGB(d.getUint8(o + 3), d.getUint8(o), d.getUint8(o + 1), d.getUint8(o + 2));
  }))!;
}

bool _same(Color a, Color b) =>
    (a.r - b.r).abs() < 0.01 && (a.g - b.g).abs() < 0.01 && (a.b - b.b).abs() < 0.01;

void main() {
  group('guitarInputPeakDB', () {
    test('máximo sobre los canales asignados (1-based)', () {
      expect(guitarInputPeakDB(<int>[1, 3], <double>[-20, -1, -6]), -6);
      expect(guitarInputPeakDB(<int>[2], <double>[-20, -1, -6]), -1);
    });
    test('sin canales válidos: -infinito', () {
      expect(guitarInputPeakDB(<int>[], <double>[-3]), double.negativeInfinity);
      expect(guitarInputPeakDB(<int>[0, 5], <double>[-3]), double.negativeInfinity);
    });
  });

  group('ClipHold (M-6)', () {
    final DateTime t0 = DateTime(2026);
    DateTime at(int ms) => t0.add(Duration(milliseconds: ms));
    test('umbral: -3 dBFS enciende, -3,1 no', () {
      expect(ClipHold().update(-3.1, t0), isFalse);
      expect(ClipHold().update(-3, t0), isTrue);
      expect(ClipHold().update(0, t0), isTrue);
    });
    test('se mantiene 1 s tras la última muestra caliente y cae después', () {
      final ClipHold h = ClipHold();
      expect(h.update(-1, t0), isTrue);
      expect(h.update(-40, at(50)), isTrue);
      expect(h.update(-40, at(999)), isTrue);
      expect(h.update(-40, at(1000)), isFalse);
    });
    test('una nueva muestra caliente reinicia el mantenimiento', () {
      final ClipHold h = ClipHold();
      h.update(-1, t0);
      expect(h.update(-2, at(900)), isTrue);
      expect(h.update(-40, at(1800)), isTrue);
      expect(h.update(-40, at(1900)), isFalse);
    });
    test('-infinito nunca enciende', () {
      expect(ClipHold().update(double.negativeInfinity, t0), isFalse);
    });
  });

  group('medidor horizontal', () {
    testWidgets('relleno ok; caliente accent', (t) async {
      expect(_same(await _pixel(t, const HorizontalLevelMeter(level: 1), 3, 4), TfColors.ok), isTrue);
      expect(_same(await _pixel(t, const HorizontalLevelMeter(level: 1, hot: true), 3, 4), TfColors.accent), isTrue);
    });
    test('shouldRepaint considera hot', () {
      expect(const HorizontalLevelPainter(0.5).shouldRepaint(const HorizontalLevelPainter(0.5, hot: true)), isTrue);
      expect(const HorizontalLevelPainter(0.5).shouldRepaint(const HorizontalLevelPainter(0.5)), isFalse);
    });
  });

  group('medidor vertical', () {
    const double h = 150;
    testWidgets('al 50% el relleno es verde, sin naranja', (t) async {
      final Color top = await _pixel(t, const VerticalLevelMeter(level: 0.5, height: h), 6, 76);
      expect(_same(top, TfColors.ok), isTrue);
    });
    testWidgets('al 100% arriba es naranja y abajo verde', (t) async {
      expect(_same(await _pixel(t, const VerticalLevelMeter(level: 1, height: h), 6, 3), TfColors.accent), isTrue);
      expect(_same(await _pixel(t, const VerticalLevelMeter(level: 1, height: h), 6, 147), TfColors.ok), isTrue);
    });
    testWidgets('caliente: relleno entero accent', (t) async {
      expect(_same(await _pixel(t, const VerticalLevelMeter(level: 0.5, height: h, hot: true), 6, 148), TfColors.accent), isTrue);
    });
    test('shouldRepaint considera hot', () {
      expect(const VerticalLevelPainter(0.5).shouldRepaint(const VerticalLevelPainter(0.5, hot: true)), isTrue);
    });
  });
}
