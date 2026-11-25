import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/library.dart';
import 'package:toneforge/features/library/import_store.dart';
import 'package:toneforge/features/library/widgets/importing_row.dart';
import 'package:toneforge/features/library/widgets/library_empty.dart';
import 'package:toneforge/features/library/widgets/song_row.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_card.dart';
import 'package:toneforge/widgets/tf_divider.dart';
import 'package:toneforge/widgets/tf_list_row.dart';

/// Anchos fijos de las columnas de la tabla (LV:152-154); la primera ocupa el resto.
abstract final class SongColumns {
  static const double takes = 70;
  static const double state = 150;
  static const double actions = 170;
}

/// Tabla de temas (LV:161-189). [showArtist] falso dentro de un artista abierto (LV:203, 214).
class SongTable extends ConsumerWidget {
  const SongTable({super.key, required this.tracks, this.showArtist = true});

  final List<ProjectSummary> tracks;
  final bool showArtist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final imports = ref.watch(importStoreProvider.select((s) => s.importRows));
    return TfCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: TfSpace.s20, vertical: TfSpace.s14),
            child: Row(
              children: [
                Expanded(child: TfTableHeaderCell(l.library_colSong)),
                SizedBox(width: SongColumns.takes, child: TfTableHeaderCell(l.library_colTakes)),
                SizedBox(width: SongColumns.state, child: TfTableHeaderCell(l.library_colState)),
                const SizedBox(width: SongColumns.actions),
              ],
            ),
          ),
          for (final job in imports) ImportingRow(key: ValueKey('import-${job.id}'), job: job),
          for (final p in tracks) SongRow(key: ValueKey(p.id), entry: p, showArtist: showArtist),
          if (tracks.isEmpty && imports.isEmpty) ...[const TfDivider(), const LibraryEmpty()],
        ],
      ),
    );
  }
}
