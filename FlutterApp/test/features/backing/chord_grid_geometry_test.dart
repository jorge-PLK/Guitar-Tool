import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/features/backing/widgets/chord_grid_geometry.dart';

void main() {
  test('constantes derivadas', () {
    expect(ChordGridGeometry.rowPitch, 68);
    expect(ChordGridGeometry.visibleHeight, 268);
  });

  test('4 u 8 compases según umbral 112', () {
    expect(const ChordGridGeometry(84 + 8 * 112 - 0.1).perRow, 4);
    expect(const ChordGridGeometry(84 + 8 * 112).perRow, 8);
    expect(const ChordGridGeometry(600).perRow, 4);
  });

  for (final double width in <double>[700, 1200]) {
    test('celda <-> hit-test (ancho $width)', () {
      final ChordGridGeometry g = ChordGridGeometry(width);
      for (int row = 0; row < 3; row++) {
        for (int col = 0; col < g.perRow; col++) {
          for (final int beats in <int>[3, 4]) {
            for (int beat = 0; beat < beats; beat++) {
              final Rect r = g.cellRect(row, col, beat, beats);
              final GridCell want = GridCell(row, col, beat);
              GridCell hit(Offset p) => g.hitTest(p, rows: 3, beats: beats);
              expect(hit(r.center), want);
              expect(hit(r.topLeft + const Offset(0.5, 0.5)), want);
              expect(hit(r.bottomRight - const Offset(0.5, 0.5)), want);
            }
          }
        }
      }
    });
  }

  test('hit-test fuera de rango se acota', () {
    const ChordGridGeometry g = ChordGridGeometry(700);
    expect(g.hitTest(const Offset(-50, -50), rows: 2, beats: 4), const GridCell(0, 0, 0));
    expect(g.hitTest(const Offset(5000, 5000), rows: 2, beats: 4), const GridCell(1, 3, 3));
  });
}
