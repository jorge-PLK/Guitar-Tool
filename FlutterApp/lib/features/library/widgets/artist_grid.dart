import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/tokens.dart';
import '../library_logic.dart';
import '../library_store.dart';
import 'artist_tile.dart';

/// Medidas de `GridItem(.adaptive(minimum: 160, maximum: 220))` y del `LazyVGrid` (LV:18, 78).
const double artistTileMinWidth = 160;
const double artistTileMaxWidth = 220;
const double artistGridColumnGap = TfSpace.s20;
const double artistGridRowGap = TfSpace.s24;

/// Delegado adaptativo con mínimo y máximo (`SliverGridDelegateWithMaxCrossAxisExtent` no tiene mínimo).
///
/// Misma regla que `GridItem(.adaptive(minimum:160, maximum:220))` de SwiftUI: columnas
/// `n = max(1, floor((W + gap) / (min + gap)))` (el mayor n cuyo recuadro mide ≥ 160) y ancho de
/// recuadro `min(max, (W - (n - 1) * gap) / n)`. Si ese ancho pasa de 220 (ancho de zona pequeño o
/// justo bajo el siguiente salto) los recuadros se quedan en 220 y la fila se alinea a la izquierda,
/// como hace SwiftUI con `alignment: .leading`.
class ArtistGridDelegate extends SliverGridDelegate {
  const ArtistGridDelegate();

  /// Columnas para un ancho disponible [width].
  static int columnsFor(double width) {
    final n = ((width + artistGridColumnGap) / (artistTileMinWidth + artistGridColumnGap)).floor();
    return n < 1 ? 1 : n;
  }

  /// Ancho de cada recuadro para [width] y [columns].
  static double tileWidthFor(double width, int columns) {
    final w = (width - (columns - 1) * artistGridColumnGap) / columns;
    return w > artistTileMaxWidth ? artistTileMaxWidth : w;
  }

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final width = constraints.crossAxisExtent;
    final columns = columnsFor(width);
    final tile = tileWidthFor(width, columns);
    return SliverGridRegularTileLayout(
      crossAxisCount: columns,
      mainAxisStride: tile + artistTileCaptionHeight + artistGridRowGap,
      crossAxisStride: tile + artistGridColumnGap,
      childMainAxisExtent: tile + artistTileCaptionHeight,
      childCrossAxisExtent: tile,
      reverseCrossAxis: axisDirectionIsReversed(constraints.crossAxisDirection),
    );
  }

  @override
  bool shouldRelayout(ArtistGridDelegate oldDelegate) => false;
}

/// Cuadrícula perezosa de artistas (LV:77-85): pulsar un recuadro abre el artista.
class ArtistGrid extends ConsumerWidget {
  const ArtistGrid({super.key, required this.groups});

  final List<ArtistGroup> groups;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.read(libraryStoreProvider.notifier);
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: TfSpace.s8),
      gridDelegate: const ArtistGridDelegate(),
      itemCount: groups.length,
      itemBuilder: (context, i) {
        final g = groups[i];
        return ArtistTile(
          key: ValueKey(g.name),
          name: g.name,
          count: g.tracks.length,
          onTap: () => store.openArtistGroup(g.name),
        );
      },
    );
  }
}
