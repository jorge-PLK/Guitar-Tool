import 'package:flutter/widgets.dart';
import 'package:toneforge/features/backing/widgets/chords_area.dart';
import 'package:toneforge/features/backing/widgets/chords_header.dart';
import 'package:toneforge/features/backing/widgets/info_row.dart';
import 'package:toneforge/features/backing/widgets/loop_marking.dart';
import 'package:toneforge/features/backing/widgets/transport_row.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_card.dart';

/// Tarjeta «Línea de tiempo» (BackingTimeline.swift:31-40): cabecera de acordes, área de acordes,
/// fila de info, barra de posición y transporte; `VStack(spacing: 10)`, `padding h 18 v 12`.
class TimelineCard extends StatelessWidget {
  const TimelineCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const TfCard(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: TfSpace.s18, vertical: TfSpace.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: TfSpace.s10,
          children: [
            ChordsHeader(),
            ChordsArea(),
            InfoRow(),
            CoalescedPositionBar(),
            TransportRow(),
          ],
        ),
      ),
    );
  }
}
