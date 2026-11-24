import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// `ProgressView(value:).tint(accent)`: barra lineal determinada, relleno `accent`, ancho exacto
/// `w * v` (sin mínimo, a diferencia de `TfAccentBar`). Ocupa el ancho disponible.
class TfProgress extends StatelessWidget {
  const TfProgress({super.key, required this.value, this.height = TfSize.progressHeight});

  final double value;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _BarPainter(value.clamp(0.0, 1.0))),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.value);

  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final Radius r = Radius.circular(size.height / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, r), Paint()..color = TfColors.fieldLine);
    if (value > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width * value, size.height), r),
        Paint()..color = TfColors.accent,
      );
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.value != value;
}

/// `ProgressView().controlSize(.small/.mini)`: rueda de 12 aspas grises que giran a pasos.
class TfSpinner extends StatefulWidget {
  const TfSpinner.small({super.key}) : size = TfSize.spinnerSmall;
  const TfSpinner.mini({super.key}) : size = TfSize.spinnerMini;

  final double size;

  @override
  State<TfSpinner> createState() => _TfSpinnerState();
}

class _TfSpinnerState extends State<TfSpinner> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 1))
    ..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(painter: _SpinnerPainter(_ctrl)),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  _SpinnerPainter(this.t) : super(repaint: t);

  final Animation<double> t;
  static const int _spokes = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;
    final Offset c = size.center(Offset.zero);
    final int head = (t.value * _spokes).floor() % _spokes;
    final Paint p = Paint()
      ..strokeWidth = s * 0.11
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < _spokes; i++) {
      final int age = (head - i + _spokes) % _spokes;
      final double a = 1 - age / _spokes * 0.85;
      p.color = TfColors.muted.withValues(alpha: a);
      final double ang = i * 2 * math.pi / _spokes;
      final Offset d = Offset(math.sin(ang), -math.cos(ang));
      canvas.drawLine(c + d * (s * 0.26), c + d * (s * 0.46), p);
    }
  }

  @override
  bool shouldRepaint(_SpinnerPainter old) => old.t != t;
}
