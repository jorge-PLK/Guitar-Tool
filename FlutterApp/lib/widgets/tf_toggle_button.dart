import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Tamaño del botón M/S: `large` = `MixerToggle` (BackingMixer.swift:257), `small` = `trackToggle` (TabScreen.swift:245).
enum TfToggleSize {
  large(TfSize.controlMd, TfRadius.field, TfSize.font12),
  small(TfSize.controlSm, TfRadius.r7, TfSize.font11);

  const TfToggleSize(this.side, this.radius, this.fontSize);
  final double side;
  final double radius;
  final double fontSize;
}

/// Botón M / S. Off: `field`, texto `text2`, borde `fieldLine`; on: `accent`, texto `accentInk`, sin borde.
class TfToggleButton extends StatelessWidget {
  const TfToggleButton({
    super.key,
    required this.text,
    required this.on,
    required this.onPressed,
    required this.semanticLabel,
    this.size = TfToggleSize.large,
  });

  final String text;
  final bool on;
  final VoidCallback? onPressed;
  final String semanticLabel;
  final TfToggleSize size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: on,
      label: semanticLabel,
      excludeSemantics: true,
      onTap: onPressed,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: on ? TfColors.accent : TfColors.field,
              borderRadius: BorderRadius.all(Radius.circular(size.radius)),
              border: on ? null : Border.all(color: TfColors.fieldLine, width: TfStroke.hairline),
            ),
            child: SizedBox(
              width: size.side,
              height: size.side,
              child: Center(
                child: Text(
                  text,
                  style: TfText.body(size.fontSize, TfWeight.bold).copyWith(
                    color: on ? TfColors.accentInk : TfColors.text2,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
