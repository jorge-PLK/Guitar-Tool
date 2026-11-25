import 'package:flutter/widgets.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';

/// Calidades por índice de `StudyChord.index = raíz*14 + calidad` (backing-contrato.md:92).
const int chordQualityCount = 14;

/// Sin acorde (`ChordLabel.noChordIndex`).
const int chordNoChordIndex = 169;

/// Nombres de raíz (sostenidos) y sufijos de calidad en el orden del índice (`ChordLabel.swift`).
/// El puente no ofrece estos nombres: ver desvío en el informe.
const List<String> chordRootNames = <String>['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
const List<String> chordQualitySuffixes = <String>[
  'm', '', '°', '+', 'm6', '6', 'm7', 'm(maj7)', 'maj7', '7', '°7', 'ø7', 'sus2', 'sus4', //
];

/// Chip de la hoja: alto 30, minWidth 36, padding 4, radio 6; activo acento, inactivo field.
class ChordEditorChip extends StatelessWidget {
  const ChordEditorChip({super.key, required this.text, required this.on, required this.onTap});

  static const double height = TfSize.controlSm + TfSpace.s2;

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
