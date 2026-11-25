import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/playlist.dart';
import 'package:toneforge/features/library/playlist_store.dart';
import 'package:toneforge/features/library/sheets/playlist_table.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/fmt.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_accent_bar.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_progress.dart';

/// Fase «Leyendo» (PI:271-277): spinner, texto y «Cancelar» (cancela y descarta la lista).
class PlaylistLoadingView extends ConsumerWidget {
  const PlaylistLoadingView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: TfSpace.s16,
      children: [
        Row(
          spacing: TfSpace.s12,
          children: [
            const TfSpinner.small(),
            Text(l.library_plIndLoading, style: TfText.body().copyWith(color: TfColors.text)),
          ],
        ),
        const Spacer(),
        PlaylistActions([
          TfSecondaryButton(
            label: l.library_plCancel,
            onPressed: () async {
              await ref.read(playlistStoreProvider.notifier).cancel();
              await discardPlaylist(ref);
            },
          ),
        ]),
      ],
    );
  }
}

/// Fase «Buscando» (PI:337-351): progreso de la búsqueda de cada tema en YouTube.
class PlaylistSearchingView extends ConsumerWidget {
  const PlaylistSearchingView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final p = ref.watch(playlistStoreProvider);
    final s = p.search;
    if (s == null) return const SizedBox.shrink();
    PlaylistItemInfo? current;
    for (final i in p.snapshot!.items) {
      if (i.status == PlaylistItemStatus.searching) {
        current = i;
        break;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: TfSpace.s14,
      children: [
        PlaylistHeader(subtitle: l.library_plSearchingAll),
        Row(
          children: [
            Expanded(
              child: Text(
                l.library_plSearchingN(s.current, s.total),
                style: TfText.body().copyWith(color: TfColors.text),
              ),
            ),
            Text(TfFmt.percent(s.fraction), style: TfText.body().copyWith(color: TfColors.muted)),
          ],
        ),
        TfAccentBar(value: s.fraction),
        if (current != null) PlaylistTrackTitle(title: current.title, artist: current.artist),
        Text(l.library_plNothingYet, style: TfText.body(12).copyWith(color: TfColors.muted)),
        const Spacer(),
        PlaylistActions([
          TfSecondaryButton(
            label: l.library_plCancel,
            onPressed: () => ref.read(playlistStoreProvider.notifier).cancel(),
          ),
        ]),
      ],
    );
  }
}

/// Error de lista (PI:575-593): título y detalle del núcleo, «Cerrar» y «Probar con otro enlace».
class PlaylistErrorView extends ConsumerWidget {
  const PlaylistErrorView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final error = ref.watch(playlistStoreProvider.select((p) => p.snapshot?.error));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: TfSpace.s12,
          children: [
            const TfIconView(TfIcon.exclamationmarkTriangleFill, size: TfSize.noticeIcon, color: TfColors.danger),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: TfSpace.s6,
                children: [
                  Text(
                    error?.title ?? l.library_importFailTitle,
                    style: TfText.body(15, TfWeight.semibold).copyWith(color: TfColors.text),
                  ),
                  if (error != null && error.detail.isNotEmpty)
                    Text(error.detail, style: TfText.body(13).copyWith(color: TfColors.muted)),
                ],
              ),
            ),
          ],
        ),
        const Spacer(),
        PlaylistActions([
          TfSecondaryButton(label: l.library_importClose, onPressed: () => closePlaylistSheet(context, ref)),
          TfPrimaryButton(label: l.library_importOtherLink, onPressed: () => discardPlaylist(ref)),
        ]),
      ],
    );
  }
}
