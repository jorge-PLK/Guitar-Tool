import 'package:flutter/widgets.dart';

/// Table frame of the playlist sheet (PI:241-243 background, radius, border)
/// with rows padded h14 v8 (PI:264). Provisional: part F1 styles it; F2 uses it.
class PlaylistTable extends StatelessWidget {
  const PlaylistTable({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(children: children);
}
