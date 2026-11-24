import 'package:flutter/widgets.dart';

import '../../../theme/tokens.dart';

/// Medidor horizontal compacto de «Tu guitarra» (RecordMixer.swift:78-85, grabar.md §2.5):
/// lienzo 22×8, pista `bg` radio 3, relleno `ok` sin degradado anclado a la izquierda.
class HorizontalLevelMeter extends StatelessWidget {
  const HorizontalLevelMeter({super.key, required this.level});

  // TODO(ola3): falta TfSize.compactMeterWidth/Height (22×8, RM:78-85).
  static const double width = 22;
  static const double height = 8;

  /// Nivel 0…1 (se recorta).
  final double level;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(width, height), painter: HorizontalLevelPainter(level));
}

class HorizontalLevelPainter extends CustomPainter {
  const HorizontalLevelPainter(this.level);

  final double level;

  double get fraction => level.clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    const Radius r = Radius.circular(TfRadius.r3);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, r), Paint()..color = TfColors.bg);
    final double w = size.width * fraction;
    if (w <= 0) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, size.height), r),
      Paint()..color = TfColors.ok,
    );
  }

  @override
  bool shouldRepaint(HorizontalLevelPainter old) => old.fraction != fraction;
}
