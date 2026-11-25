import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/playlist_enums.dart';
import 'package:toneforge/features/library/playlist_store.dart';
import 'package:toneforge/features/library/sheets/import_sheet.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_progress.dart';
import 'package:toneforge/widgets/tf_tooltip.dart';

/// Texto traducido del indicador según el paso de la sesión; null si no hay indicador.
String? playlistIndicatorText(AppLocalizations l, PlaylistState s) {
  if (s.indicator == null) return null;
  switch (s.step) {
    case PlaylistStep.loading:
      return l.library_plIndLoading;
    case PlaylistStep.searching:
      final p = s.search;
      return l.library_plIndSearching(p?.current ?? 0, p?.total ?? 0);
    case PlaylistStep.running:
      final q = s.queue;
      final total = q?.total ?? 0;
      return l.library_plIndImporting(math.min((q?.done ?? 0) + 1, total), total);
    case PlaylistStep.stopped:
      return l.library_plIndStopped;
    case PlaylistStep.summary:
      return (s.snapshot?.summary.cancelled ?? false)
          ? l.library_plIndCancelled
          : l.library_plIndFinished;
    default:
      return null;
  }
}

/// Cápsula de la cabecera (LV:114-127): estado de la importación de lista; reabre la hoja.
class PlaylistIndicator extends ConsumerWidget {
  const PlaylistIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final state = ref.watch(playlistStoreProvider);
    final text = playlistIndicatorText(l, state);
    if (text == null) return const SizedBox.shrink();
    return TfTooltip(
      message: l.library_playlistIndicatorTooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          ref.read(playlistStoreProvider.notifier).openSheet();
          showImportSheet(context);
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: DecoratedBox(
            decoration: const ShapeDecoration(color: TfColors.accentBg, shape: StadiumBorder()),
            child: SizedBox(
              height: TfSize.controlMd,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: TfSpace.s12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (state.isLive)
                      const TfSpinner.small()
                    else
                      const TfIconView(
                        TfIcon.checkmarkCircle,
                        size: TfSize.iconButtonIcon,
                        color: TfColors.accent,
                      ),
                    const SizedBox(width: TfSpace.s8),
                    Text(
                      text,
                      style: TfText.body(13, TfWeight.medium).copyWith(color: TfColors.accent),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
