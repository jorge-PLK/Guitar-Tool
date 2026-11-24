import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/icons.dart';
import '../theme/tokens.dart';

/// Par ▲▼ de macOS (`Stepper` `.labelsHidden`). Ajusta `value` en `step` dentro de [min, max].
/// Flechas arriba/abajo con el foco. `onChanged == null` lo deshabilita.
class TfStepper extends StatelessWidget {
  const TfStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.step = 1,
    this.min = double.negativeInfinity,
    this.max = double.infinity,
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final double step;
  final double min;
  final double max;

  void _bump(double delta) {
    final double next = (value + delta).clamp(min, max).toDouble();
    if (next != value) onChanged!(next);
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = onChanged != null;
    final bool canUp = enabled && value < max;
    final bool canDown = enabled && value > min;
    Widget half(TfIcon icon, bool active, double delta) {
      return Expanded(
        child: MouseRegion(
          cursor: active ? SystemMouseCursors.click : MouseCursor.defer,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: active ? () => _bump(delta) : null,
            child: Center(
              child: TfIconView(
                icon,
                size: TfSize.stepperIcon,
                color: active ? TfColors.text2 : TfColors.muted,
              ),
            ),
          ),
        ),
      );
    }

    Widget body = SizedBox(
      width: TfSize.stepperWidth,
      height: TfSize.stepperHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: TfColors.nativeStepperBg,
          borderRadius: BorderRadius.circular(TfRadius.native),
          border: Border.all(color: TfColors.nativeStepperLine, width: TfStroke.hairline),
        ),
        child: Column(
          children: <Widget>[
            half(TfIcon.chevronUp, canUp, step),
            half(TfIcon.chevronDown, canDown, -step),
          ],
        ),
      ),
    );
    if (!enabled) {
      return Opacity(opacity: TfOpacity.disabled, child: body);
    }
    body = Focus(
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          _bump(step);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _bump(-step);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: body,
    );
    return body;
  }
}
