import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

enum TfChipKind { ok, working, neutral, error }

/// Cápsula de estado: `Chip` (Theme.swift:121). Sin estados.
class TfChip extends StatelessWidget {
  const TfChip(this.label, {super.key, required this.kind});

  final String label;
  final TfChipKind kind;

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg) = switch (kind) {
      TfChipKind.ok => (TfColors.ok, TfColors.okBg),
      TfChipKind.working => (TfColors.accent, TfColors.accentBg),
      TfChipKind.neutral => (TfColors.text2, TfColors.neutralBg),
      TfChipKind.error => (TfColors.danger, TfColors.dangerBg),
    };
    return DecoratedBox(
      decoration: ShapeDecoration(color: bg, shape: const StadiumBorder()),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: TfSpace.s10, vertical: TfSpace.s4),
        child: Text(
          label,
          maxLines: 1,
          softWrap: false,
          style: TfText.body(TfSize.font12, TfWeight.semibold).copyWith(color: fg, decoration: TextDecoration.none),
        ),
      ),
    );
  }
}
