import 'dart:ui';

import 'package:flutter/widgets.dart';

import '../../../theme/tokens.dart';

/// Borde de rectángulo redondeado discontinuo (RV:199-204: trazo 1, patrón 4-3, radio 10).
class DashedRRectPainter extends CustomPainter {
  const DashedRRectPainter({
    required this.color,
    this.radius = TfRadius.control,
    this.strokeWidth = TfStroke.hairline,
    this.dash = TfSpace.s4,
    this.gap = TfSpace.s3,
  });

  final Color color;
  final double radius;
  final double strokeWidth;
  final double dash;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect box = (Offset.zero & size).deflate(strokeWidth / 2);
    final Path outline = Path()..addRRect(RRect.fromRectAndRadius(box, Radius.circular(radius)));
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    for (final PathMetric m in outline.computeMetrics()) {
      double d = 0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(DashedRRectPainter old) =>
      old.color != color || old.radius != radius || old.strokeWidth != strokeWidth || old.dash != dash || old.gap != gap;
}
