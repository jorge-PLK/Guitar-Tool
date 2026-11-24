import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// Interruptor de macOS redibujado (`Toggle` `.switch`). Encendido: `accent`.
/// `onChanged == null` lo deshabilita. Espacio conmuta; Tab lo enfoca.
class TfSwitch extends StatelessWidget {
  const TfSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.small = false,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  /// `.controlSize(.small)`.
  final bool small;
  final String? semanticLabel;

  bool get _enabled => onChanged != null;

  @override
  Widget build(BuildContext context) {
    final double w = small ? TfSize.switchSmallWidth : TfSize.switchWidth;
    final double h = small ? TfSize.switchSmallHeight : TfSize.switchHeight;
    final double knob = h - 2 * TfSpace.s2;
    Widget body = SizedBox(
      width: w,
      height: h,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: value ? TfColors.accent : TfColors.fieldLine,
          borderRadius: BorderRadius.circular(TfRadius.pill),
        ),
        child: Padding(
          padding: const EdgeInsets.all(TfSpace.s2),
          child: Align(
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: TfColors.white,
                shape: BoxShape.circle,
                boxShadow: <BoxShadow>[TfShadow.knob],
              ),
              child: SizedBox(width: knob, height: knob),
            ),
          ),
        ),
      ),
    );
    if (!_enabled) {
      return Semantics(
        label: semanticLabel,
        toggled: value,
        enabled: false,
        child: Opacity(opacity: TfOpacity.disabled, child: body),
      );
    }
    body = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged!(!value),
        child: body,
      ),
    );
    return Semantics(
      label: semanticLabel,
      toggled: value,
      enabled: true,
      child: Focus(
        onKeyEvent: (FocusNode node, KeyEvent event) {
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.space) {
            onChanged!(!value);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: body,
      ),
    );
  }
}
