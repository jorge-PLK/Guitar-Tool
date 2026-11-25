import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/link_resolve.dart';
import 'package:toneforge/contract/playlist.dart';
import 'package:toneforge/features/library/library_metrics.dart';
import 'package:toneforge/features/library/playlist_store.dart';
import 'package:toneforge/features/library/sheets/candidate_row.dart';
import 'package:toneforge/features/library/sheets/playlist_phase_parts.dart';
import 'package:toneforge/features/library/sheets/playlist_table.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/selected_project.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_chip.dart';
import 'package:toneforge/widgets/tf_menu.dart';

/// Fila de Revisar (`reviewRow`, PI:377): título, duración, selector de candidato y chip «dudoso».
class PlaylistReviewRow extends ConsumerWidget {
  const PlaylistReviewRow({super.key, required this.item});

  final PlaylistItemInfo item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final doubtful = item.status == PlaylistItemStatus.doubtful;
    return PlaylistRow(
      child: DecoratedBox(
        decoration: BoxDecoration(color: doubtful ? TfColors.dangerBg.withValues(alpha: TfOpacity.tint35) : null),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: doubtful ? TfSpace.s4 : 0),
          child: Row(
            spacing: TfSpace.s12,
            children: [
              SizedBox(width: LibraryMetrics.reviewTitleWidth, child: PlaylistTrackTitle(title: item.title, artist: item.artist)),
              SizedBox(
                width: LibraryMetrics.reviewDurationWidth,
                child: Text(
                  playlistDuration(item.duration),
                  textAlign: TextAlign.right,
                  style: TfText.body(TfSize.font12).copyWith(color: TfColors.muted),
                ),
              ),
              Expanded(child: _CandidateMenu(item: item)),
              if (doubtful) TfChip(l.library_plChipDoubtful, kind: TfChipKind.error),
            ],
          ),
        ),
      ),
    );
  }
}

class _CandidateMenu extends ConsumerWidget {
  const _CandidateMenu({required this.item});

  final PlaylistItemInfo item;

  String _label(BuildContext context, AppLocalizations l, LinkCandidateInfo c) {
    final locale = Localizations.localeOf(context).languageCode;
    return [
      c.title,
      if (c.artist != null) c.artist!,
      if (c.duration != null) playlistDuration(c.duration),
      if (c.difference != null) signedSeconds(c.difference!, locale),
      if (c.isClose) l.library_importChipClose,
      if (c.isLive) l.library_importChipLive,
    ].join(' · ');
  }

  String _placeholder(AppLocalizations l) => switch (item.status) {
    PlaylistItemStatus.skipped => l.library_plChoiceSkipped,
    PlaylistItemStatus.failed => l.library_plChoiceFailed(item.error?.title ?? ''),
    PlaylistItemStatus.pending => l.library_plChoicePending,
    _ => item.candidates.isEmpty ? l.library_plChoiceNoResults : l.library_plChoicePick,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final store = ref.read(playlistStoreProvider.notifier);
    final chosen = item.chosen;
    final ranked = chosen == null ? null : item.candidates.where((c) => c.id == chosen.id).firstOrNull;
    final entries = <TfMenuEntry>[
      for (final c in item.candidates)
        if (c.inLibrary != null) ...[
          TfMenuItem(
            label: l.library_plInLibrarySuffix(_label(context, l, c)),
            enabled: false,
            onSelected: () {},
          ),
          TfMenuItem(
            label: l.library_plOpenExisting(c.inLibrary!.title),
            onSelected: () {
              ref.read(selectedProjectProvider.notifier).select(c.inLibrary!.id);
              store.closeSheet();
            },
          ),
        ] else
          TfMenuItem(label: _label(context, l, c), onSelected: () => store.choose(item.id, c.id)),
      if (item.candidates.isNotEmpty) const TfMenuDivider(),
      TfMenuItem(label: l.library_plSkipItem, onSelected: () => store.skip(item.id)),
    ];
    final muted = TfText.body(TfSize.font11).copyWith(color: TfColors.muted);
    return TfMenu(
      entries: entries,
      builder: (context, toggle) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: toggle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: TfSpace.s10, vertical: TfSpace.s6),
          decoration: BoxDecoration(
            color: TfColors.field,
            borderRadius: BorderRadius.circular(TfRadius.field),
            border: Border.all(color: TfColors.fieldLine),
          ),
          child: Row(
            spacing: TfSpace.s8,
            children: [
              if (chosen != null)
                Expanded(
                  child: Row(
                    spacing: TfSpace.s8,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: TfSpace.s2,
                          children: [
                            Text(
                              chosen.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TfText.body(TfSize.font13, TfWeight.medium).copyWith(color: TfColors.text),
                            ),
                            Text(
                              candidateSubtitle(chosen),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: muted,
                            ),
                          ],
                        ),
                      ),
                      if (ranked?.difference != null)
                        Text(
                          signedSeconds(ranked!.difference!, Localizations.localeOf(context).languageCode),
                          style: TfText.body(TfSize.font12, TfWeight.medium).copyWith(color: TfColors.text2),
                        ),
                      if (ranked?.isClose ?? false) TfChip(l.library_importChipClose, kind: TfChipKind.ok),
                      if (ranked?.isLive ?? false) TfChip(l.library_importChipLive, kind: TfChipKind.neutral),
                      if (ranked?.inLibrary != null)
                        TfChip(l.library_importChipInLibrary, kind: TfChipKind.neutral),
                    ],
                  ),
                )
              else
                Expanded(
                  child: Text(
                    _placeholder(l),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TfText.body(TfSize.font13).copyWith(
                      color: item.status == PlaylistItemStatus.skipped ? TfColors.muted : TfColors.text2,
                    ),
                  ),
                ),
              const TfIconView(
                TfIcon.chevronUpChevronDown,
                size: LibraryMetrics.candidateChevron,
                color: TfColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
