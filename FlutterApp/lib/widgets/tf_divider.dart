import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// Separador de 1 px: `Divider().overlay(TF.line)`. Horizontal ocupa el ancho; vertical, [height]
/// (alto 28 en `BackingMixer.swift:96`).
class TfDivider extends StatelessWidget {
  const TfDivider({super.key, this.color = TfColors.line})
      : vertical = false,
        height = null;

  const TfDivider.vertical({super.key, this.color = TfColors.line, this.height = TfSize.dividerVerticalHeight})
      : vertical = true;

  final Color color;
  final bool vertical;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: vertical ? TfStroke.hairline : null,
      height: vertical ? height : TfStroke.hairline,
      child: ColoredBox(color: color),
    );
  }
}
