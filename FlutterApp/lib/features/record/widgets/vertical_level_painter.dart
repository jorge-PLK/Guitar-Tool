import 'package:flutter/widgets.dart';

import '../../../theme/tokens.dart';

/// Medidor vertical del canal «Tu guitarra» (RecordMixer.swift:198-207, grabar.md §2.5):
/// 12 de ancho (`TfLevelBar` del kit es de 8 y recibe dB), nivel ya 0…1.
class VerticalLevelMeter extends StatelessWidget {
  const VerticalLevelMeter({super.key, required this.level, required this.height});

  static const double width = TfSize.inputLevelBarWidth;

  /// Nivel 0…1 (se recorta).
  final double level;
  final double height;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(width, height), painter: VerticalLevelPainter(level));
}

class VerticalLevelPainter extends CustomPainter {
  const VerticalLevelPainter(this.level);

  final double level;

  double get fraction => level.clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    const Radius r = Radius.circular(TfRadius.xs);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, r), Paint()..color = TfColors.bg);
    final double h = size.height * fraction;
    if (h <= 0) return;
    final Rect fill = Rect.fromLTWH(0, size.height - h, size.width, h);
    final Paint paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: <Color>[TfColors.ok, TfColors.ok, TfColors.accent, TfColors.accent],
        stops: <double>[0, 0.7, 0.92, 1],
      ).createShader(fill);
    canvas.drawRRect(RRect.fromRectAndRadius(fill, r), paint);
  }

  @override
  bool shouldRepaint(VerticalLevelPainter old) => old.fraction != fraction;
}
