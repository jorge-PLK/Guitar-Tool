import 'package:flutter/widgets.dart';
import 'package:toneforge/widgets/tf_pill.dart';

/// Pista en cola sin partitura: cápsula de borde discontinuo (`dash 3`) y texto `muted`.
/// El trazo discontinuo ya lo pinta `TfPill(pending: true)` con su `CustomPainter`.
class TabPendingPill extends StatelessWidget {
  const TabPendingPill({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context) => TfPill(label: name, pending: true);
}
