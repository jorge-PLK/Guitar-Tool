import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/playlist.dart';
import 'package:toneforge/features/library/library_metrics.dart';
import 'package:toneforge/features/library/playlist_store.dart';
import 'package:toneforge/features/library/sheets/playlist_table.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_buttons.dart';

/// Fase «resumen» de la hoja de lista (PI:513-575).
class PlaylistSummaryView extends ConsumerWidget {
  const PlaylistSummaryView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(playlistStoreProvider);
    final store = ref.read(playlistStoreProvider.notifier);
    final snap = s.snapshot;
    final t = s.summary ?? (imported: 0, skipped: 0, inLibrary: 0, failed: 0);
    final b = s.buttons;
    final failed = s.failedRows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: TfSpace.s14,
      children: [
        PlaylistHeader(subtitle: snap?.summary.cancelled ?? false ? l.library_plCancelledTitle : l.library_plDoneTitle),
        Row(
          spacing: TfSpace.s12,
          children: [
            _Stat(label: l.library_plStatImported, value: t.imported, color: TfColors.ok),
            _Stat(label: l.library_plStatSkipped, value: t.skipped, color: TfColors.text2),
            _Stat(label: l.library_plStatInLibrary, value: t.inLibrary, color: TfColors.text2),
            _Stat(
              label: l.library_plStatFailed,
              value: t.failed,
              color: t.failed > 0 ? TfColors.danger : TfColors.text2,
            ),
          ],
        ),
        if (t.imported > 0)
          Text(l.library_plSeparatingNote, style: TfText.body(TfSize.font12).copyWith(color: TfColors.muted)),
        if (failed.isEmpty)
          const Spacer()
        else ...[
          Text(
            l.library_plFailedHeader,
            style: TfText.body(TfSize.font12, TfWeight.medium).copyWith(
              color: TfColors.muted,
              letterSpacing: TfSize.trackingTableHeader,
            ),
          ),
          Expanded(child: PlaylistTable(children: [for (final i in failed) _FailedRow(item: i)])),
        ],
        PlaylistActions(
          [
            TfPrimaryButton(label: l.library_importClose, onPressed: () => closePlaylistSheet(context, ref)),
            if (b.showResume) TfSecondaryButton(label: l.library_plResumeN(b.resumeCount ?? 0), onPressed: store.resume),
            if (b.showRetryFailed)
              TfSecondaryButton(label: l.library_plRetryFailed(b.retryFailedCount), onPressed: store.retryFailed),
          ],
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: TfSpace.s16, vertical: TfSpace.s12),
      decoration: BoxDecoration(
        color: TfColors.field,
        borderRadius: BorderRadius.circular(TfRadius.control),
        border: Border.all(color: TfColors.fieldLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: TfSpace.s4,
        children: [
          Text(
            label.toUpperCase(),
            style: TfText.body(TfSize.font11).copyWith(color: TfColors.muted, letterSpacing: TfSize.trackingTableHeader),
          ),
          Text('$value', style: TfText.display(TfSize.font26).copyWith(color: color)),
        ],
      ),
    ),
  );
}

class _FailedRow extends StatelessWidget {
  const _FailedRow({required this.item});

  final PlaylistItemInfo item;

  @override
  Widget build(BuildContext context) {
    final e = item.error;
    return PlaylistRow(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: TfSpace.s12,
        children: [
          SizedBox(
            width: LibraryMetrics.failedTitleWidth,
            child: PlaylistTrackTitle(title: item.title, artist: item.artist),
          ),
          if (e != null)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: TfSpace.s2,
                children: [
                  Text(e.title, style: TfText.body(TfSize.font13, TfWeight.semibold).copyWith(color: TfColors.danger)),
                  if (e.detail.isNotEmpty)
                    Text(
                      e.detail,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TfText.body(TfSize.font12).copyWith(color: TfColors.muted),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
