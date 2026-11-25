import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/link_import.dart';
import 'package:toneforge/features/library/library_metrics.dart';
import 'package:toneforge/features/library/link_import_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_buttons.dart';

/// Fila de un resultado de Spotify (LinkImportSheet.swift:525-545).
class SpotifyTrackRow extends ConsumerWidget {
  const SpotifyTrackRow({super.key, required this.track});

  final LinkSpotifyTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final store = ref.read(linkImportStoreProvider.notifier);
    final busy = ref.watch(linkImportStoreProvider.select((s) => s.busy));
    final year = track.year;
    final album = year == null ? track.album : '${track.album} · $year';
    final artists = track.artists.join(', ');
    Widget line(String t, TextStyle style) => Text(t, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: TfSpace.s10, vertical: TfSpace.s6),
      child: Row(
        spacing: TfSpace.s10,
        children: [
          _Thumb(url: track.imageURL),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: TfSpace.s1,
              children: [
                line(track.name, TfText.body(TfSize.font13, TfWeight.semibold).copyWith(color: TfColors.text)),
                line(artists, TfText.body(TfSize.font12).copyWith(color: TfColors.text2)),
                line(album, TfText.body(TfSize.font11).copyWith(color: TfColors.muted)),
              ],
            ),
          ),
          Text(
            track.durationText,
            style: TfText.body(TfSize.font12).copyWith(
              color: TfColors.muted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Semantics(
            button: true,
            label: l.library_importListenTooltip,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => store.openSpotify(track.appURL, fallback: track.trackURL),
              child: const TfIconView(TfIcon.playFill, size: TfSize.font13, color: TfColors.accent),
            ),
          ),
          TfSecondaryButton(
            label: l.library_importChoose,
            height: LibraryMetrics.spotifyChooseHeight,
            onPressed: busy ? null : () => store.chooseSpotifyTrack(track),
          ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    const placeholder = Center(child: TfIconView(TfIcon.musicNote, size: TfSize.font14, color: TfColors.muted));
    final u = url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(TfRadius.xs),
      child: SizedBox.square(
        dimension: LibraryMetrics.spotifyThumb,
        child: ColoredBox(
          color: TfColors.card,
          child: u == null
              ? placeholder
              : Image.network(u, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder),
        ),
      ),
    );
  }
}
