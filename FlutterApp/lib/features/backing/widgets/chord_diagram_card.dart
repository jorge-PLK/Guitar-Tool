import 'package:flutter/widgets.dart';
import 'package:toneforge/contract/study.dart';
import 'package:toneforge/features/backing/widgets/chord_diagram.dart';
import 'package:toneforge/features/backing/widgets/chord_shape.dart';
import 'package:toneforge/features/backing/widgets/chord_strip.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';

/// Tarjeta del diagrama (BT:310-323): diagrama 72 x 84 y, al lado, nombre, «Siguiente» y capo.
class ChordDiagramCard extends StatelessWidget {
  const ChordDiagramCard({super.key, this.current, this.next, this.capo = 0});

  static const double textMinWidth = 90;

  final StudyChord? current;
  final StudyChord? next;
  final int capo;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final StudyChordShape? shape = current?.shape;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: TfSpace.s12, vertical: TfSpace.s8),
      decoration: BoxDecoration(
        color: TfColors.field,
        borderRadius: BorderRadius.circular(TfRadius.control),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: TfSpace.s12,
        children: <Widget>[
          Semantics(
            label: shape == null ? l.backing_noChordDiagramA11y : l.backing_chordDiagramA11y,
            child: ChordDiagram(
              shape: shape == null ? null : ChordShape.fromContract(shape),
              fretLabel: l.backing_fretLabel,
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: textMinWidth),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: TfSpace.s2,
              children: <Widget>[
                Text(
                  current == null ? '—' : chordShownName(current!),
                  style: TfText.display(22).copyWith(color: TfColors.text),
                ),
                Text(
                  next == null ? ' ' : l.backing_nextChord(chordShownName(next!)),
                  style: TfText.body(12).copyWith(color: TfColors.muted),
                ),
                if (capo > 0)
                  Text(l.backing_capoShown(capo), style: TfText.body(12).copyWith(color: TfColors.accent)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
