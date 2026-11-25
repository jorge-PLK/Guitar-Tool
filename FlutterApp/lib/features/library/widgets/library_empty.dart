import 'package:flutter/widgets.dart';

/// «Todavía no hay temas» (LV:99-105), sin marco: la tabla lo pone tras un divisor y la cuadrícula
/// de artistas dentro de una tarjeta. Provisional: la rellena la parte B.
class LibraryEmpty extends StatelessWidget {
  const LibraryEmpty({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
