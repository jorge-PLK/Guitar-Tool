import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/playlist.dart';
import 'package:toneforge/features/library/library_metrics.dart';
import 'package:toneforge/features/library/playlist_store.dart';
import 'package:toneforge/features/library/sheets/import_banner.dart';
import 'package:toneforge/features/library/sheets/playlist_table.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/fmt.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_checkbox.dart';
import 'package:toneforge/widgets/tf_chip.dart';
import 'package:toneforge/widgets/tf_tooltip.dart';

/// Fase «Elegir temas» (PI:281-333): resumen, marcar todos/ninguno, tabla de temas y pie.
class PlaylistPickView extends ConsumerWidget {
  const PlaylistPickView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final p = ref.watch(playlistStoreProvider);
    final snap = p.snapshot;
    final t = p.tracks;
    if (snap == null || t == null) return const SizedBox.shrink();
    final b = p.buttons;
    final store = ref.read(playlistStoreProvider.notifier);
    final subtitle =
        l.library_plSummary(t.total, t.selected) + (t.inLibrary > 0 ? l.library_plSummaryInLibrary(t.inLibrary) : '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: TfSpace.s14,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          spacing: TfSpace.s8,
          children: [
            Expanded(child: PlaylistHeader(subtitle: subtitle)),
            if (b.markAll)
              TfSecondaryButton(
                label: l.library_plSelectAll,
                height: LibraryMetrics.plActionHeight,
                onPressed: store.selectAll,
              ),
            if (b.markNone)
              TfSecondaryButton(
                label: l.library_plSelectNone,
                height: LibraryMetrics.plActionHeight,
                onPressed: store.selectNone,
              ),
          ],
        ),
        if (snap.mayBeTruncated) ImportBanner(text: l.library_plCap, tone: ImportBannerTone.warning),
        Expanded(
          child: PlaylistTable(children: [for (final item in snap.items) _TrackRow(item: item)]),
        ),
        PlaylistActions([
          TfSecondaryButton(label: l.library_importClose, onPressed: () => closePlaylistSheet(context, ref)),
          if (b.showContinue)
            TfPrimaryButton(
              label: b.continueIsSearch ? l.library_plSearch(b.continueCount) : l.library_plDownload(b.continueCount),
              onPressed: b.continueEnabled ? store.continue_ : null,
            ),
        ]),
      ],
    );
  }
}

class _TrackRow extends ConsumerWidget {
  const _TrackRow({required this.item});

  final PlaylistItemInfo item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final store = ref.read(playlistStoreProvider.notifier);
    final inLib = item.status == PlaylistItemStatus.inLibrary;
    final possible = item.possible;
    void toggle() => store.select(item.id, !item.selected);
    return PlaylistRow(
      onTap: inLib ? null : toggle,
      child: Row(
        spacing: TfSpace.s12,
        children: [
          if (inLib)
            const SizedBox.square(dimension: LibraryMetrics.plCheckSlot)
          else
            TfCheckbox(value: item.selected, onChanged: (_) => toggle()),
          Expanded(
            child: Opacity(
              opacity: inLib ? TfOpacity.muted : 1,
              child: PlaylistTrackTitle(title: item.title, artist: item.artist),
            ),
          ),
          if (inLib) TfChip(l.library_plQInLibrary, kind: TfChipKind.neutral),
          if (possible != null)
            TfTooltip(
              message: l.library_plMaybeTooltip(possible.title),
              child: TfChip(l.library_plChipMaybe, kind: TfChipKind.working),
            ),
          SizedBox(
            width: LibraryMetrics.plDurationWidth,
            child: Text(
              item.duration == null ? '—' : TfFmt.duration(item.duration!),
              textAlign: TextAlign.right,
              style: TfText.body(13).copyWith(color: TfColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}
