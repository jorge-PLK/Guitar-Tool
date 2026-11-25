import 'package:flutter/widgets.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';

/// Chip de acorde de la tira (BT:263-279): caja 36 de alto (ancho mín. 52 + 6 por lado) y, debajo,
/// el número de compás (hueco fijo de 12).
class ChordChip extends StatelessWidget {
  const ChordChip({
    super.key,
    required this.name,
    this.barNumber,
    this.isCurrent = false,
    this.inLoop = false,
    this.isPast = false,
  });

  static const double boxHeight = 36;
  static const double minTextWidth = 52;
  static const double padH = 6;
  static const double barRowHeight = 12;
  static const double height = boxHeight + barRowHeight;

  final String name;

  /// Solo en el acorde que abre compás.
  final int? barNumber;
  final bool isCurrent;
  final bool inLoop;

  /// Acorde anterior al actual (texto atenuado).
  final bool isPast;

  static TextStyle get nameStyle => TfText.body(14, TfWeight.bold);

  /// Ancho de la caja para [name]; el mismo que usa el diseño de la tira.
  static double widthFor(String name) {
    final TextPainter p = TextPainter(
      text: TextSpan(text: name, style: nameStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final double w = p.width;
    p.dispose();
    return (w < minTextWidth ? minTextWidth : w) + padH * 2;
  }

  @override
  Widget build(BuildContext context) {
    final Color textColor = isCurrent
        ? TfColors.accentInk
        // TODO token: `muted@0.7` (BT:268) sin token propio; mismo valor que pressedSecondary.
        : (isPast ? TfColors.muted.withValues(alpha: TfOpacity.pressedSecondary) : TfColors.text);
    final Color fill = isCurrent
        ? TfColors.accent
        : (inLoop ? TfColors.accent.withValues(alpha: TfOpacity.tint22) : TfColors.field);
    final Color? border = isCurrent ? null : (inLoop ? TfColors.accent : TfColors.fieldLine);
    return Semantics(
      label: name,
      selected: isCurrent,
      child: SizedBox(
        width: widthFor(name),
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              key: const ValueKey<String>('chord-chip-box'),
              height: boxHeight,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(TfRadius.field),
                border: border == null ? null : Border.all(color: border, width: TfStroke.hairline),
              ),
              child: Text(name, style: nameStyle.copyWith(color: textColor), maxLines: 1, softWrap: false),
            ),
            SizedBox(
              height: barRowHeight,
              child: Padding(
                padding: const EdgeInsets.only(left: TfSpace.s2),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    barNumber == null ? ' ' : '$barNumber',
                    style: TfText.body(10).copyWith(color: TfColors.muted),
                    maxLines: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
