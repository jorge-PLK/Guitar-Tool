import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/icons.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Casilla de macOS redibujada (`Toggle` `.checkbox`). Marcada: relleno `accent`.
/// Etiqueta body 13 `text2` (texto por parámetro). `onChanged == null` la deshabilita.
class TfCheckbox extends StatelessWidget {
  const TfCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onChanged != null;
    final Widget box = SizedBox(
      width: TfSize.checkboxBox,
      height: TfSize.checkboxBox,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: value ? TfColors.accent : TfColors.field,
          borderRadius: BorderRadius.circular(TfRadius.xs),
          border: Border.all(
            color: value ? TfColors.accent : TfColors.fieldLine,
            width: TfStroke.hairline,
          ),
        ),
        child: value
            ? const Center(
                child: TfIconView(
                  TfIcon.checkmark,
                  size: TfSize.checkboxMark,
                  color: TfColors.white,
                ),
              )
            : null,
      ),
    );
    final Widget row = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        box,
        if (label != null) ...<Widget>[
          const SizedBox(width: TfSpace.s8),
          Flexible(
            child: Text(
              label!,
              style: TfText.body(13).copyWith(
                color: TfColors.text2,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ],
    );
    if (!enabled) {
      return Semantics(
        label: label,
        checked: value,
        enabled: false,
        child: Opacity(opacity: TfOpacity.disabled, child: row),
      );
    }
    return Semantics(
      label: label,
      checked: value,
      enabled: true,
      child: Focus(
        onKeyEvent: (FocusNode node, KeyEvent event) {
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.space) {
            onChanged!(!value);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged!(!value),
            child: row,
          ),
        ),
      ),
    );
  }
}
