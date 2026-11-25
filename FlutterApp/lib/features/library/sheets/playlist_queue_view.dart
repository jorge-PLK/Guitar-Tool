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
import 'package:toneforge/widgets/tf_accent_bar.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_chip.dart';
import 'package:toneforge/widgets/tf_tooltip.dart';

/// Fase «cola» de la hoja de lista (PI:454-509): en marcha o detenida por un error.
class PlaylistQueueView extends ConsumerWidget {
  const PlaylistQueueView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(playlistStoreProvider);
    final store = ref.read(playlistStoreProvider.notifier);
    final snap = s.snapshot;
    final q = s.queue ?? (done: 0, total: 0);
    final b = s.buttons;
    final stopped = snap?.step == PlaylistStep.stopped;
    final err = snap?.error;
    final progress = snap?.progress ?? 0;
    final close = TfSecondaryButton(
      label: l.library_importClose,
      onPressed: () => closePlaylistSheet(context, ref),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: TfSpace.s14,
      children: [
        PlaylistHeader(subtitle: stopped ? l.library_plQueueStopped : l.library_plQueueTitle),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              l.library_plQueueCount(q.done, q.total),
              style: TfText.body(TfSize.font14).copyWith(color: TfColors.text),
            ),
            Text(TfFmt.percent(progress), style: TfText.body(TfSize.font14).copyWith(color: TfColors.muted)),
          ],
        ),
        TfAccentBar(value: progress),
        if (stopped && err != null) ...[
          ImportBanner(
            text: '${err.title}. ${err.code == 'rate-limited' ? l.library_plRateLimitedHint : err.detail}',
          ),
          if (snap!.update.alreadyLatest)
            ImportBanner(text: l.library_plLatestKept, tone: ImportBannerTone.warning),
          if (snap.update.error != null) ImportBanner(text: snap.update.error!),
        ],
        Expanded(child: PlaylistTable(children: [for (final i in s.queueRows) PlaylistQueueRow(item: i)])),
        PlaylistActions(
          [
            if (b.closeKeepsQueue) TfTooltip(message: l.library_plCloseTooltip, child: close) else close,
            if (b.showUpdateAndRetry)
              TfPrimaryButton(
                label: snap?.update.updating ?? false ? l.library_plUpdating : l.library_plUpdateRetry,
                onPressed: b.updateEnabled ? store.updateAndRetry : null,
              ),
            if (b.showResume) TfPrimaryButton(label: l.library_plResume, onPressed: store.resume),
            if (b.showCancel) TfSecondaryButton(label: l.library_plCancel, onPressed: store.cancel),
          ],
        ),
      ],
    );
  }
}

/// Fila de la cola (`queueRow`, PI:491): estado a la derecha.
class PlaylistQueueRow extends StatelessWidget {
  const PlaylistQueueRow({super.key, required this.item});

  final PlaylistItemInfo item;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final accent = TfText.body(TfSize.font12).copyWith(color: TfColors.accent);
    final p = item.progress;
    final downloading = item.stage != PlaylistItemStage.convert;
    final Widget status = switch (item.status) {
      PlaylistItemStatus.downloading => Row(
        spacing: TfSpace.s12,
        children: [
          Text(
            downloading
                ? (p == null ? l.library_plDownloading : l.library_plDownloadingPercent(TfFmt.percent(p)))
                : l.library_plConverting,
            style: accent,
          ),
          SizedBox(
            width: LibraryMetrics.queueBarWidth,
            child: TfAccentBar(value: downloading ? p : null, height: LibraryMetrics.queueBarHeight),
          ),
        ],
      ),
      PlaylistItemStatus.imported => TfChip(l.library_plQImported, kind: TfChipKind.ok),
      PlaylistItemStatus.skipped => TfChip(l.library_plQSkipped, kind: TfChipKind.neutral),
      PlaylistItemStatus.inLibrary => TfChip(l.library_plQInLibrary, kind: TfChipKind.neutral),
      PlaylistItemStatus.failed => TfChip(item.error?.title ?? '', kind: TfChipKind.error),
      _ => Text(l.library_plQQueued, style: TfText.body(TfSize.font12).copyWith(color: TfColors.muted)),
    };
    return PlaylistRow(
      child: Row(
        spacing: TfSpace.s12,
        children: [
          Expanded(child: PlaylistTrackTitle(title: item.title, artist: item.artist)),
          status,
        ],
      ),
    );
  }
}
