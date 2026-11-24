import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// Tarjeta: `Card` (Theme.swift:112). Fondo `card`, radio 14, borde `line` 1. Sin padding propio.
class TfCard extends StatelessWidget {
  const TfCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: TfColors.card, borderRadius: BorderRadius.circular(TfRadius.card)),
      position: DecorationPosition.background,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(TfRadius.card),
          border: Border.all(color: TfColors.line, width: TfStroke.hairline),
        ),
        position: DecorationPosition.foreground,
        child: child,
      ),
    );
  }
}
