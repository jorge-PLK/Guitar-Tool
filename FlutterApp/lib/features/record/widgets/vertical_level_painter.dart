import 'package:flutter/widgets.dart';

import '../../../theme/tokens.dart';

/// Medidor vertical del canal «Tu guitarra» (RecordMixer.swift:198-207, grabar.md §2.5):
/// 12 de ancho (`TfLevelBar` del kit es de 8 y recibe dB), nivel ya 0…1.
class VerticalLevelMeter extends StatelessWidget {
  const VerticalLevelMeter({super.key, required this.level, required this.height, this.hot = false});

  static const double width = TfSize.inputLevelBarWidth;

  /// Nivel 0…1 (se recorta).
  final double level;
  final double height;

  /// M-6: aviso de tope; relleno entero `accent`.
  final bool hot;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(width, height), painter: VerticalLevelPainter(level, hot: hot));
}

class VerticalLevelPainter extends CustomPainter {
  const VerticalLevelPainter(this.level, {this.hot = false});

  final double level;
  final bool hot;

  double get fraction => level.clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    const Radius r = Radius.circular(TfRadius.xs);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, r), Paint()..color = TfColors.bg);
    final double h = size.height * fraction;
    if (h <= 0) return;
    final Rect fill = Rect.fromLTWH(0, size.height - h, size.width, h);
    // M-6: el degradado se calcula sobre la pista entera: el naranja solo asoma por encima de 0,7.
    final Paint paint = Paint();
    if (hot) {
      paint.color = TfColors.accent;
    } else {
      paint.shader = const LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: <Color>[TfColors.ok, TfColors.ok, TfColors.accent, TfColors.accent],
        stops: <double>[0, 0.7, 0.92, 1],
      ).createShader(Offset.zero & size);
    }
    canvas.drawRRect(RRect.fromRectAndRadius(fill, r), paint);
  }

  @override
  bool shouldRepaint(VerticalLevelPainter old) => old.fraction != fraction || old.hot != hot;
}
