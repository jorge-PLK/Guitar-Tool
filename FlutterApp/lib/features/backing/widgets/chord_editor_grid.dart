import 'package:flutter/widgets.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';

/// Chip de la hoja: alto 30, minWidth 36, padding 4, radio 6; activo acento, inactivo field.
class ChordEditorChip extends StatelessWidget {
  const ChordEditorChip({super.key, required this.text, required this.on, required this.onTap});

  static const double height = TfSize.chordChipHeight;

  final String text;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: height,
          constraints: const BoxConstraints(minWidth: TfSize.controlMd),
          padding: const EdgeInsets.symmetric(horizontal: TfSpace.s4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? TfColors.accent : TfColors.field,
            borderRadius: BorderRadius.circular(TfRadius.small),
          ),
          child: Text(
            text,
            style: TfText.body(13, TfWeight.semibold).copyWith(color: on ? TfColors.accentInk : TfColors.text),
          ),
        ),
      ),
    );
  }
}

/// Rejilla de celdas fijas (`LazyVGrid` de [columns] columnas de [cell], spacing 6) con el chip centrado.
class ChordEditorGrid extends StatelessWidget {
  const ChordEditorGrid({super.key, required this.cell, required this.columns, required this.children});

  final double cell;
  final int columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: cell * columns + TfSpace.s6 * (columns - 1),
      child: Wrap(
        spacing: TfSpace.s6,
        runSpacing: TfSpace.s6,
        children: <Widget>[
          for (final Widget c in children) SizedBox(width: cell, child: Center(child: c)),
        ],
      ),
    );
  }
}
