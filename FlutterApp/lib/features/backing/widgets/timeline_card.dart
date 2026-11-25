import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/features/backing/widgets/chord_grid.dart';
import 'package:toneforge/features/backing/widgets/chords_area.dart';
import 'package:toneforge/features/backing/widgets/chords_header.dart';
import 'package:toneforge/features/backing/widgets/info_row.dart';
import 'package:toneforge/features/backing/widgets/loop_marking.dart';
import 'package:toneforge/features/backing/widgets/section_boxes.dart';
import 'package:toneforge/features/backing/widgets/section_popover_state.dart';
import 'package:toneforge/features/backing/widgets/section_selection.dart';
import 'package:toneforge/features/backing/widgets/transport_row.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_card.dart';

/// Tarjeta «Línea de tiempo» (BackingTimeline.swift:31-40): cabecera de acordes, área de acordes,
/// fila de info, barra de posición y transporte; `VStack(spacing: 10)`, `padding h 18 v 12`.
class TimelineCard extends ConsumerWidget {
  const TimelineCard({super.key});

  static Widget _grid(BuildContext context) => const ChordGrid(sectionsLayer: gridSectionBoxes);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TfCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: TfSpace.s18, vertical: TfSpace.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: TfSpace.s10,
          children: [
            ChordsHeader(onSectionMarked: (String? id) {
              if (id == null) return;
              ref.read(sectionSelectionProvider.notifier).select(id);
              ref.read(sectionPopoverProvider.notifier).open(id);
            }),
            const ChordsArea(gridBuilder: _grid, sectionsLayer: stripSectionBoxes),
            const InfoRow(),
            const CoalescedPositionBar(),
            const TransportRow(),
          ],
        ),
      ),
    );
  }
}
