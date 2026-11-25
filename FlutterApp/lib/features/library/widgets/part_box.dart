import 'package:flutter/widgets.dart';
import 'package:toneforge/contract/library_detail.dart';
import 'package:toneforge/features/library/widgets/take_row.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';

/// Caja de una parte (PR:50-60): nombre y sus tomas.
class PartBox extends StatelessWidget {
  const PartBox({super.key, required this.projectId, required this.part});

  final String projectId;
  final PartInfo part;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: TfSpace.s14, vertical: TfSpace.s12),
      decoration: BoxDecoration(
        color: TfColors.field,
        borderRadius: BorderRadius.circular(TfRadius.tile),
        border: Border.all(color: TfColors.fieldLine, width: TfStroke.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: TfSpace.s8,
        children: [
          Text(
            part.name,
            style: TfText.body(TfSize.font14, TfWeight.semibold).copyWith(
              color: TfColors.text,
              decoration: TextDecoration.none,
            ),
          ),
          for (final t in part.takes) TakeRow(projectId: projectId, part: part, take: t),
        ],
      ),
    );
  }
}
