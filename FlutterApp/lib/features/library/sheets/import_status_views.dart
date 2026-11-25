import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Pantallas de estado de la hoja de importación. Provisionales: las rellena la parte E1b.
/// Cada una pinta su cuerpo y su pie; [onClose] cierra la hoja (la hoja hace `reset()` + pop).

/// «Leyendo metadatos…» / «Buscando en YouTube…» (LS:584-593).
class ImportResolvingView extends ConsumerWidget {
  const ImportResolvingView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => const SizedBox.shrink();
}

/// «Preparando…» (LS:572-580).
class ImportPreparingView extends ConsumerWidget {
  const ImportPreparingView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => const SizedBox.shrink();
}

/// Error de fuente (LS:759-789).
class ImportErrorView extends ConsumerWidget {
  const ImportErrorView({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) => const SizedBox.shrink();
}

/// «Tema importado» (LS:791-796).
class ImportDoneView extends ConsumerWidget {
  const ImportDoneView({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) => const SizedBox.shrink();
}

/// «Ya está en la biblioteca» (LS:550-568).
class ImportRepeatedView extends ConsumerWidget {
  const ImportRepeatedView({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) => const SizedBox.shrink();
}
