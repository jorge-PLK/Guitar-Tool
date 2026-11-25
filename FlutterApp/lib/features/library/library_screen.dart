import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/features/library/library_logic.dart';
import 'package:toneforge/features/library/library_store.dart';
import 'package:toneforge/features/library/project_detail_page.dart';
import 'package:toneforge/features/library/widgets/artists_view.dart';
import 'package:toneforge/features/library/widgets/library_header.dart';
import 'package:toneforge/features/library/widgets/song_table.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/library_detail.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';

/// Biblioteca (LV:52-105): cabecera y tabla de temas o cuadrícula de artistas; o el detalle.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(libraryDetailProvider);
    if (detail != null) return ProjectDetailPage(projectId: detail);
    final l = AppLocalizations.of(context);
    final state = ref.watch(libraryStoreProvider);
    final Widget content;
    if (!state.loaded) {
      content = const SizedBox.shrink();
    } else if (state.noMatches) {
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: TfSpace.s32),
        child: Center(
          child: Text(
            l.library_noMatch(state.query.trim()),
            textAlign: TextAlign.center,
            style: TfText.body().copyWith(color: TfColors.muted),
          ),
        ),
      );
    } else if (state.grouping == LibraryGrouping.artists) {
      content = const ArtistsView();
    } else {
      content = SongTable(tracks: state.songs);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: TfSpace.s40, vertical: TfSpace.s32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LibraryHeader(),
          const SizedBox(height: TfSpace.s24),
          content,
        ],
      ),
    );
  }
}
