import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/playlist.dart';
import 'package:toneforge/features/library/playlist_store.dart';
import 'package:toneforge/features/library/sheets/playlist_pick_view.dart';
import 'package:toneforge/features/library/sheets/playlist_queue_view.dart';
import 'package:toneforge/features/library/sheets/playlist_review_view.dart';
import 'package:toneforge/features/library/sheets/playlist_status_views.dart';
import 'package:toneforge/features/library/sheets/playlist_summary_view.dart';

/// Pantalla «lista» de la hoja de importación (PlaylistImportView, PI:216-596): enruta por `step`.
class PlaylistImportView extends ConsumerWidget {
  const PlaylistImportView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final step = ref.watch(playlistStoreProvider.select((p) => p.step));
    return switch (step) {
      PlaylistStep.loading => const PlaylistLoadingView(),
      PlaylistStep.tracks => const PlaylistPickView(),
      PlaylistStep.searching => const PlaylistSearchingView(),
      PlaylistStep.review => const PlaylistReviewView(),
      PlaylistStep.running || PlaylistStep.stopped => const PlaylistQueueView(),
      PlaylistStep.summary => const PlaylistSummaryView(),
      PlaylistStep.error => const PlaylistErrorView(),
      PlaylistStep.unknown || null => const SizedBox.shrink(),
    };
  }
}
