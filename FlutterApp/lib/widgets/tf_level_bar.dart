import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// Barra de nivel del canal (`levelBar`, BackingMixer.swift:222-234): 8 de ancho, relleno desde abajo.
/// El degradado es relativo al propio relleno (ok hasta el 70 %, mezcla hasta accent en el 92 %).
class TfLevelBar extends StatelessWidget {
  const TfLevelBar({
    super.key,
    required this.rmsDb,
    required this.height,
    this.dim = false,
  });

  /// Suelo del medidor en dB (`BackingController.meterFloorDB`).
  static const double floorDb = -60;

  /// RMS en dB; null = sin medidor.
  final double? rmsDb;
  final double height;

  /// Canal en mute o solo ajeno: nivel 0.
  final bool dim;

  static double fractionFor(double? rmsDb, {bool dim = false}) {
    if (dim || rmsDb == null) return 0;
    return ((rmsDb - floorDb) / -floorDb).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final double f = fractionFor(rmsDb, dim: dim);
    return CustomPaint(
      size: Size(TfSize.levelBarWidth, height),
      painter: _LevelBarPainter(f),
    );
  }
}

class _LevelBarPainter extends CustomPainter {
  _LevelBarPainter(this.fraction);
  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    const Radius r = Radius.circular(TfRadius.xs);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, r), Paint()..color = TfColors.bg);
    if (fraction <= 0) return;
    final double h = size.height * fraction;
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
  bool shouldRepaint(_LevelBarPainter old) => old.fraction != fraction;
}
