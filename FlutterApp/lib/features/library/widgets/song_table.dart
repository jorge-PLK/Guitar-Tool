import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/library.dart';

/// Tabla de temas (LV:161-189). [showArtist] falso dentro de un artista abierto (LV:203, 214).
/// Provisional: la rellena la parte B.
class SongTable extends ConsumerWidget {
  const SongTable({super.key, required this.tracks, this.showArtist = true});

  final List<ProjectSummary> tracks;
  final bool showArtist;

  @override
  Widget build(BuildContext context, WidgetRef ref) => const SizedBox.shrink();
}
