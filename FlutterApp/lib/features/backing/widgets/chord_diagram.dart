import 'package:flutter/widgets.dart';
import 'package:toneforge/features/backing/widgets/chord_shape.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';

/// Diagrama de acorde 72 × 84 (CD:1-67). Sin forma ocupa el mismo espacio y no pinta.
class ChordDiagram extends StatelessWidget {
  const ChordDiagram({super.key, required this.shape, this.fretLabel});

  static const double width = 72;
  static const double height = 84;

  final ChordShape? shape;

  /// Texto de la etiqueta de traste base («{base}fr»). Por defecto `Nfr`.
  final String Function(int base)? fretLabel;

  @override
  Widget build(BuildContext context) {
    // TODO l10n: sin claves ARB «Diagrama del acorde»/«Sin diagrama»; sin etiqueta semántica.
    return CustomPaint(
      size: const Size(width, height),
      painter: ChordDiagramPainter(shape, fretLabel: fretLabel),
    );
  }
}

class ChordDiagramPainter extends CustomPainter {
  ChordDiagramPainter(this.shape, {this.fretLabel});

  final ChordShape? shape;
  final String Function(int base)? fretLabel;

  static const double _top = 16;
  static const double _left = 22;
  static const double _right = ChordDiagram.width - 6;
  static const double _bottom = ChordDiagram.height - 4;
  static const double stringGap = (_right - _left) / 5;
  static const double fretGap = (_bottom - _top) / 5;
  static const double _dotOffset = 6.4;

  static double x(int s) => _left + stringGap * s;
  static double y(int r) => _top + fretGap * r;

  /// Traste base según §2.4: sin cuerda al aire y con el traste más bajo > 1, ese traste.
  static int baseOf(ChordShape shape) {
    if (shape.frets.any((int? f) => f == 0)) return shape.baseFret;
    int? lowest;
    for (final int? f in shape.frets) {
      if (f != null && f > 0 && (lowest == null || f < lowest)) lowest = f;
    }
    return lowest != null && lowest > 1 ? lowest : shape.baseFret;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final ChordShape? s = shape;
    if (s == null) return;
    final int base = baseOf(s);
    final Color ink = TfColors.muted.withValues(alpha: TfOpacity.pressedPrimary);

    for (int r = 0; r <= 5; r++) {
      final bool nut = r == 0 && base == 1;
      canvas.drawLine(
        Offset(_left, y(r)),
        Offset(_right, y(r)),
        Paint()
          ..color = nut ? TfColors.text2 : ink
          ..strokeWidth = nut ? 3 : 1,
      );
    }
    for (int i = 0; i < 6; i++) {
      canvas.drawLine(
        Offset(x(i), _top),
        Offset(x(i), _bottom),
        Paint()
          ..color = ink
          ..strokeWidth = 1,
      );
    }
    if (base > 1) {
      _text(canvas, fretLabel?.call(base) ?? '${base}fr', TfText.body(10, TfWeight.semibold),
          TfColors.text2, Offset(10, y(0) + _dotOffset));
    }
    final ChordBarre? b = s.barre;
    if (b != null) {
      final int row = b.fret - base;
      final int a = 6 - (b.from > b.to ? b.from : b.to);
      final int z = 6 - (b.from < b.to ? b.from : b.to);
      final double top = y(row) + _dotOffset - 4;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x(a) - 4, top, x(z) - x(a) + 8, 8),
          const Radius.circular(TfRadius.xs),
        ),
        Paint()..color = TfColors.accent,
      );
    }
    for (int i = 0; i < 6; i++) {
      final int? f = s.frets[i];
      if (f == null) {
        _text(canvas, '×', TfText.body(11, TfWeight.bold), TfColors.muted, Offset(x(i), 7));
      } else if (f == 0) {
        canvas.drawCircle(
          Offset(x(i), 7),
          3.5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = TfColors.text2,
        );
      } else {
        final int row = f - base;
        if (row >= 0 && row < 5) {
          canvas.drawCircle(Offset(x(i), y(row) + _dotOffset), 5, Paint()..color = TfColors.accent);
        }
      }
    }
  }

  void _text(Canvas canvas, String text, TextStyle style, Color color, Offset center) {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: text, style: style.copyWith(color: color)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    tp.dispose();
  }

  @override
  bool shouldRepaint(ChordDiagramPainter old) => old.shape != shape;
}
