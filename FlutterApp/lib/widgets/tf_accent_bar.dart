import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// Barra de progreso en acento: `AccentBar` (Theme.swift:87). Con [value] (0..1) rellena; sin valor,
/// un tramo del 30 % va y viene con `0.5 - 0.5 cos(2 pi t)`, periodo 1,6 s. Ocupa todo el ancho disponible.
class TfAccentBar extends StatefulWidget {
  const TfAccentBar({super.key, this.value, this.height = TfSize.accentBarHeight});

  final double? value;
  final double height;

  @override
  State<TfAccentBar> createState() => _TfAccentBarState();
}

class _TfAccentBarState extends State<TfAccentBar> with SingleTickerProviderStateMixin {
  static const Duration _period = Duration(milliseconds: 1600);
  late final AnimationController _ctrl = AnimationController(vsync: this, duration: _period);

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(TfAccentBar old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.value == null) {
      if (!_ctrl.isAnimating) _ctrl.repeat();
    } else {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: CustomPaint(painter: _AccentBarPainter(widget.value, _ctrl)),
    );
  }
}

class _AccentBarPainter extends CustomPainter {
  _AccentBarPainter(this.value, this.t) : super(repaint: t);

  final double? value;
  final Animation<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect track = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.height / 2));
    canvas.clipRRect(track);
    canvas.drawRRect(track, Paint()..color = TfColors.field);
    final double? v = value;
    final double w;
    final double x;
    if (v != null) {
      w = math.max(size.height, size.width * v.clamp(0.0, 1.0));
      x = 0;
    } else {
      w = size.width * 0.3;
      x = (size.width - w) * (0.5 - 0.5 * math.cos(t.value * 2 * math.pi));
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(x, 0, w, size.height), Radius.circular(size.height / 2)),
      Paint()..color = TfColors.accent,
    );
  }

  @override
  bool shouldRepaint(_AccentBarPainter old) => old.value != value || old.t != t;
}
