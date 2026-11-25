import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/widgets.dart';

/// Zona de soltar ficheros del sistema (`dropDestination` de SwiftUI, RootView.swift:28-30).
/// Entrega las rutas de lo soltado a [onPaths]; no filtra ni realza al arrastrar (SwiftUI tampoco).
class TfDropTarget extends StatelessWidget {
  const TfDropTarget({super.key, required this.child, required this.onPaths});

  final Widget child;
  final ValueChanged<List<String>> onPaths;

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragDone: (DropDoneDetails details) {
        final List<String> paths = <String>[for (final f in details.files) f.path];
        if (paths.isNotEmpty) onPaths(paths);
      },
      child: child,
    );
  }
}
