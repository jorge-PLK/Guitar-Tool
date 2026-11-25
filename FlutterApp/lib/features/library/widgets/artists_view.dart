import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/tokens.dart';
import '../../../widgets/tf_card.dart';
import '../library_store.dart';
import 'artist_bar.dart';
import 'artist_grid.dart';
import 'library_empty.dart';
import 'song_table.dart';

/// Vista «Artistas» de la Biblioteca (LV:55-60, 70-86): cuadrícula, o barra del artista + tabla.
class ArtistsView extends ConsumerWidget {
  const ArtistsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(libraryStoreProvider);
    final open = s.openArtist;
    if (open == null) {
      if (s.loaded && s.entries.isEmpty) {
        return const Align(
          alignment: Alignment.topCenter,
          child: TfCard(child: LibraryEmpty()),
        );
      }
      return ArtistGrid(groups: s.groups);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ArtistBar(name: open),
        const SizedBox(height: TfSpace.s24),
        SongTable(tracks: s.openArtistTracks, showArtist: false),
      ],
    );
  }
}
