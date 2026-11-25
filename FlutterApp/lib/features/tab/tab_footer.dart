import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/tab.dart';
import 'package:toneforge/features/tab/tab_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';

String _piece(AppLocalizations l, TabDrumPiece p) => switch (p) {
      TabDrumPiece.kick => l.tab_pieceKick,
      TabDrumPiece.snare => l.tab_pieceSnare,
      TabDrumPiece.hiHat => l.tab_pieceHiHat,
      TabDrumPiece.openHiHat => l.tab_pieceOpenHiHat,
      TabDrumPiece.tom => l.tab_pieceTom,
      TabDrumPiece.crash => l.tab_pieceCrash,
      TabDrumPiece.unknown => '',
    };

String _compose(AppLocalizations l, TabSelectionSummary s) {
  final String place = l.tab_selectionPlace(s.bar, s.beat);
  return switch (s.code) {
    TabSummaryCode.note => l.tab_selectionNote(place, s.string ?? 1, s.fret ?? 0),
    TabSummaryCode.noNote => l.tab_selectionNoNote(place, s.string ?? 1),
    TabSummaryCode.drums => l.tab_selectionDrums(
        place,
        <String>[for (final TabDrumPiece p in s.pieces) _piece(l, p)].where((String e) => e.isNotEmpty).join(', '),
      ),
    TabSummaryCode.drumsNoHits => l.tab_selectionDrums(place, l.tab_selectionNoHits),
    TabSummaryCode.unknown => place,
  };
}

/// Pie de estado: `flash` (accent) > resumen de selección > texto fijo según la fuente (muted).
class TabFooter extends ConsumerWidget {
  const TabFooter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String? flash = ref.watch(tabStoreProvider.select((TabStoreState s) => s.flash));
    final TabState? tab = ref.watch(tabStoreProvider.select((TabStoreState s) => s.tab));
    final TabSelectionSummary? summary = tab?.selection?.summary;
    final bool hasFlash = flash != null && flash.isNotEmpty;
    final String text = hasFlash
        ? flash
        : (summary != null && summary.code != TabSummaryCode.unknown)
            ? _compose(l, summary)
            : (tab?.source == TabSource.songsterr ? l.tab_footerSongsterr : l.tab_footerAutomatic);
    return SizedBox(
      height: TfSize.tabFooterHeight,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TfText.body(TfSize.font13).copyWith(color: hasFlash ? TfColors.accent : TfColors.muted),
      ),
    );
  }
}
