import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// Medidores de entrada por canal (`InputMeters`, AudioSettingsView.swift:66-82): 8×28, radio 2, relleno `ok`.
/// `levels` = nivel 0..1 por canal; con null no pinta nada (sin sesión abierta).
class TfInputMeters extends StatelessWidget {
  const TfInputMeters({super.key, required this.levels});

  final List<double>? levels;

  @override
  Widget build(BuildContext context) {
    final List<double>? l = levels;
    if (l == null) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      spacing: TfSpace.s4,
      children: <Widget>[
        for (final double v in l)
          CustomPaint(
            size: const Size(TfSize.inputMeterWidth, TfSize.inputMeterHeight),
            painter: _MeterPainter(v.clamp(0.0, 1.0)),
          ),
      ],
    );
  }
}

class _MeterPainter extends CustomPainter {
  _MeterPainter(this.level);
  final double level;

  @override
  void paint(Canvas canvas, Size size) {
    const Radius r = Radius.circular(TfRadius.r2);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, r), Paint()..color = TfColors.field);
    final double h = size.height * level;
    if (h <= 0) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, size.height - h, size.width, h), r),
      Paint()..color = TfColors.ok,
    );
  }

  @override
  bool shouldRepaint(_MeterPainter old) => old.level != level;
}
