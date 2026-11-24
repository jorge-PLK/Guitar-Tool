import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// Deslizador de macOS redibujado (`Slider.tint(accent)`): parte izquierda `accent`,
/// pomo circular blanco. `step` cuantiza; `snapTo` imanta a un valor si la distancia es
/// <= `snapTolerance` (solo con el ratón). Flechas ±paso, Inicio/Fin con el foco.
/// Sin `width` ocupa el ancho disponible (o `TfSize.sliderWidth` si no está acotado).
class TfSlider extends StatelessWidget {
  const TfSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.step,
    this.snapTo,
    this.snapTolerance = 0,
    this.width,
    this.onChangeEnd,
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final double min;
  final double max;

  /// Paso de cuantización (ratón y teclado). Sin él: continuo (teclado: 5 % del rango).
  final double? step;
  final double? snapTo;
  final double snapTolerance;
  final double? width;
  final ValueChanged<double>? onChangeEnd;

  double _clamp(double v) => v.clamp(min, max).toDouble();

  double _quantize(double v) {
    final double? s = step;
    if (s == null || s <= 0) return _clamp(v);
    return _clamp(min + ((v - min) / s).round() * s);
  }

  double _fromDx(double dx, double trackWidth) {
    final double usable = trackWidth - TfSize.sliderKnob;
    final double t = usable <= 0 ? 0 : ((dx - TfSize.sliderKnob / 2) / usable).clamp(0.0, 1.0);
    double v = _quantize(min + t * (max - min));
    final double? target = snapTo;
    if (target != null && (v - target).abs() <= snapTolerance) v = target;
    return v;
  }

  void _keyStep(double delta) {
    final double inc = step ?? (max - min) * 0.05;
    final double next = _quantize(value + delta * inc);
    if (next != value) onChanged!(next);
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = onChanged != null;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double w = width ?? (c.hasBoundedWidth ? c.maxWidth : TfSize.sliderWidth);
        final double t = max == min ? 0 : ((value - min) / (max - min)).clamp(0.0, 1.0);
        final double usable = w - TfSize.sliderKnob;
        final double knobLeft = t * usable;
        const double trackTop = (TfSize.sliderHit - TfSize.sliderTrack) / 2;
        Widget body = SizedBox(
          width: w,
          height: TfSize.sliderHit,
          child: Stack(
            children: <Widget>[
              Positioned(
                left: 0,
                right: 0,
                top: trackTop,
                height: TfSize.sliderTrack,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: TfColors.fieldLine,
                    borderRadius: BorderRadius.circular(TfRadius.pill),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                width: knobLeft + TfSize.sliderKnob / 2,
                top: trackTop,
                height: TfSize.sliderTrack,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: TfColors.accent,
                    borderRadius: BorderRadius.circular(TfRadius.pill),
                  ),
                ),
              ),
              Positioned(
                left: knobLeft,
                top: (TfSize.sliderHit - TfSize.sliderKnob) / 2,
                width: TfSize.sliderKnob,
                height: TfSize.sliderKnob,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    color: TfColors.white,
                    shape: BoxShape.circle,
                    boxShadow: <BoxShadow>[TfShadow.knob],
                  ),
                ),
              ),
            ],
          ),
        );
        if (!enabled) {
          return Opacity(opacity: TfOpacity.disabled, child: body);
        }
        body = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (TapDownDetails d) => onChanged!(_fromDx(d.localPosition.dx, w)),
          onTapUp: (TapUpDetails d) => onChangeEnd?.call(_fromDx(d.localPosition.dx, w)),
          onHorizontalDragUpdate: (DragUpdateDetails d) =>
              onChanged!(_fromDx(d.localPosition.dx, w)),
          onHorizontalDragEnd: (DragEndDetails d) => onChangeEnd?.call(value),
          child: body,
        );
        return Focus(
          onKeyEvent: (FocusNode node, KeyEvent event) {
            if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
              return KeyEventResult.ignored;
            }
            final LogicalKeyboardKey k = event.logicalKey;
            if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.arrowUp) {
              _keyStep(1);
            } else if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.arrowDown) {
              _keyStep(-1);
            } else if (k == LogicalKeyboardKey.home) {
              onChanged!(min);
            } else if (k == LogicalKeyboardKey.end) {
              onChanged!(max);
            } else {
              return KeyEventResult.ignored;
            }
            return KeyEventResult.handled;
          },
          child: MouseRegion(cursor: SystemMouseCursors.click, child: body),
        );
      },
    );
  }
}
