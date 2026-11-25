import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/tab.dart';
import 'package:toneforge/features/tab/tab_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';

/// Pie de estado: `flash` (accent) > resumen de selección > texto fijo según la fuente (muted).
class TabFooter extends ConsumerWidget {
  const TabFooter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String? flash = ref.watch(tabStoreProvider.select((TabStoreState s) => s.flash));
    final TabState? tab = ref.watch(tabStoreProvider.select((TabStoreState s) => s.tab));
    final String? summary = tab?.selection?.summary;
    final bool hasFlash = flash != null && flash.isNotEmpty;
    final String text = hasFlash
        ? flash
        : (summary != null && summary.isNotEmpty)
            ? summary
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
