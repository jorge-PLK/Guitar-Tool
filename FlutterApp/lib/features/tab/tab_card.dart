import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/tab.dart';
import 'package:toneforge/features/tab/tab_footer.dart';
import 'package:toneforge/features/tab/tab_listen_selector.dart';
import 'package:toneforge/features/tab/tab_store.dart';
import 'package:toneforge/features/tab/tab_track_controls.dart';
import 'package:toneforge/features/tab/tab_track_strip.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_card.dart';

/// Alto mínimo de la zona del lienzo (`TabScreen.swift:191-198`); sin token en `theme/`.
const double tabStageMinHeight = 320;

/// Tarjeta de tablatura (`TabScreen.swift:185-203`): selector Oír, pastillas, controles de
/// pista, zona del lienzo (`stage`, la pone la pantalla) y pie.
class TabCard extends ConsumerWidget {
  const TabCard({super.key, required this.stage});

  final Widget stage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TabState? tab = ref.watch(tabStoreProvider.select((TabStoreState s) => s.tab));
    final List<TabTrackInfo> entries = tabEntries(tab);
    TabTrackInfo? selected;
    for (final TabTrackInfo t in entries) {
      if (t.id == tab?.selectedTrack) selected = t;
    }
    return TfCard(
      child: Padding(
        padding: const EdgeInsets.all(TfSpace.s18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: TfSpace.s12,
          children: <Widget>[
            if (entries.isNotEmpty) const TabListenSelector(),
            const TabTrackStrip(),
            if (selected != null) TabTrackControls(key: ValueKey<String>(selected.id), track: selected),
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: tabStageMinHeight),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: TfColors.bg.withValues(alpha: TfOpacity.dim),
                    borderRadius: BorderRadius.circular(TfRadius.control),
                  ),
                  child: ClipRRect(borderRadius: BorderRadius.circular(TfRadius.control), child: stage),
                ),
              ),
            ),
            const TabFooter(),
          ],
        ),
      ),
    );
  }
}
