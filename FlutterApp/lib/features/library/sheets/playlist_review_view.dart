import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/features/library/playlist_store.dart';
import 'package:toneforge/features/library/sheets/import_banner.dart';
import 'package:toneforge/features/library/sheets/playlist_review_row.dart';
import 'package:toneforge/features/library/sheets/playlist_table.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_buttons.dart';

/// Fase «revisar» de la hoja de lista (PI:363-428).
class PlaylistReviewView extends ConsumerWidget {
  const PlaylistReviewView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(playlistStoreProvider);
    final store = ref.read(playlistStoreProvider.notifier);
    final r = s.review;
    final b = s.buttons;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: TfSpace.s14,
      children: [
        PlaylistHeader(subtitle: r == null ? '' : l.library_plReviewSummary(r.proposed, r.doubtful, r.skipped)),
        ImportBanner(text: l.library_plReviewBanner, tone: ImportBannerTone.warning),
        Expanded(child: PlaylistTable(children: [for (final i in s.reviewRows) PlaylistReviewRow(item: i)])),
        PlaylistActions(
          [
            TfSecondaryButton(label: l.library_importClose, onPressed: () => closePlaylistSheet(context, ref)),
            if (b.showSearchMore) TfSecondaryButton(label: l.library_plKeepSearching, onPressed: store.search),
            TfPrimaryButton(
              label: l.library_plDownload(b.startCount),
              onPressed: b.startEnabled ? store.start : null,
            ),
          ],
        ),
      ],
    );
  }
}
