import 'dart:math' as math;
import 'dart:ui';

/// Celda de la rejilla de acordes: fila, columna (compás dentro de la fila) y pulso.
class GridCell {
  const GridCell(this.row, this.col, this.beat);

  final int row;
  final int col;
  final int beat;

  @override
  bool operator ==(Object other) =>
      other is GridCell && other.row == row && other.col == col && other.beat == beat;

  @override
  int get hashCode => Object.hash(row, col, beat);

  @override
  String toString() => 'GridCell($row, $col, $beat)';
}

/// Geometría pura de la rejilla de acordes (CG:81-106, 131-142). Una sola fuente para pintar y pulsar.
class ChordGridGeometry {
  const ChordGridGeometry(this.width);

  static const double labelWidth = 84;
  static const double rowHeight = 46;
  static const double sectionGutter = 18;
  static const double rowSpacing = 4;
  static const double barGap = 4;
  static const double minBarWidthFor8 = 112;
  static const int visibleRows = 4;
  static const double clickSlop = 4;

  /// `18 + 46 + 4`.
  static const double rowPitch = sectionGutter + rowHeight + rowSpacing;

  /// `4·(18+46) + 3·4`.
  static const double visibleHeight =
      visibleRows * (sectionGutter + rowHeight) + (visibleRows - 1) * rowSpacing;

  /// Ancho total de la rejilla (con la columna de etiquetas).
  final double width;

  /// 8 compases por fila si `(ancho − 84)/8 ≥ 112`, si no 4.
  int get perRow => (width - labelWidth) / 8 >= minBarWidthFor8 ? 8 : 4;

  double get barWidth => (width - labelWidth) / perRow;
  double get drawnBarWidth => barWidth - barGap;

  /// Rectángulo del compás completo (fila, col).
  Rect barRect(int row, int col) =>
      Rect.fromLTWH(labelWidth + col * barWidth, row * rowPitch + sectionGutter, drawnBarWidth, rowHeight);

  /// Celda `(fila, col, pulso, nPulsos)`.
  Rect cellRect(int row, int col, int beat, int beats) {
    final double w = drawnBarWidth / beats;
    return Rect.fromLTWH(
      labelWidth + col * barWidth + beat * w,
      row * rowPitch + sectionGutter,
      w,
      rowHeight,
    );
  }

  /// Alto del contenido para [rows] filas (sin recorte por `visibleHeight`).
  double contentHeight(int rows) => rows <= 0 ? 0 : rows * rowPitch - rowSpacing;

  /// Punto → celda. [rows] limita la fila; [beats] son los pulsos del compás pulsado.
  GridCell hitTest(Offset p, {required int rows, required int beats}) {
    final int row = (p.dy / rowPitch).floor().clamp(0, math.max(rows - 1, 0));
    final int col = ((p.dx - labelWidth) / barWidth).floor().clamp(0, perRow - 1);
    final double frac = ((p.dx - labelWidth - col * barWidth) / drawnBarWidth).clamp(0.0, 0.999999);
    return GridCell(row, col, (frac * beats).floor());
  }
}
