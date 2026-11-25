import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/tab.dart';
import 'package:toneforge/features/tab/songsterr_store.dart';
import 'package:toneforge/features/tab/tab_confirm_auto.dart';
import 'package:toneforge/features/tab/tab_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_menu.dart';

/// Menú «Fuente: …» de la cabecera (TabScreen.swift:151-167, ficha 2.8).
/// Deshabilitado en `waitingAnalysis` y `empty`.
class TabSourceMenu extends ConsumerWidget {
  const TabSourceMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final tab = ref.watch(tabStoreProvider.select((s) => s.tab));
    final source = tab?.source;
    final name = switch (source) {
      TabSource.songsterr => l.tab_sourceSongsterr,
      TabSource.automatic => l.tab_sourceAutomatic,
      _ => l.tab_sourceNone,
    };
    final label = l.tab_sourceMenu(name);
    final enabled = tab?.phase != TabPhase.waitingAnalysis && tab?.phase != TabPhase.empty;
    if (!enabled) return _Label(label: label, onTap: null);
    final uses = source == TabSource.songsterr;
    return TfMenu(
      entries: [
        TfMenuItem(
          label: l.tab_sourceSongsterrSearch,
          onSelected: () => ref.read(songsterrStoreProvider.notifier).open(),
        ),
        if (uses)
          TfMenuItem(
            label: l.tab_sourceChangePairing,
            onSelected: () => ref.read(songsterrStoreProvider.notifier).review(),
          ),
        TfMenuItem(
          label: l.tab_sourceAutomatic,
          enabled: source != TabSource.automatic,
          onSelected: () => _automatic(context, ref, uses: uses),
        ),
      ],
      builder: (context, toggle) => _Label(label: label, onTap: toggle),
    );
  }

  Future<void> _automatic(BuildContext context, WidgetRef ref, {required bool uses}) async {
    if (uses && !await confirmTabAuto(context)) return;
    await ref.read(tabStoreProvider.notifier).setSource(TabSource.automatic);
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? TfOpacity.disabled : 1,
        child: MouseRegion(
          cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(
                label,
                style: TfText.body(TfSize.font13, TfWeight.medium).copyWith(color: TfColors.text2),
              ),
              const SizedBox(width: TfSpace.s4),
              const TfIconView(TfIcon.chevronDown, size: TfSize.backingInfoChevron, color: TfColors.text2),
            ]),
          ),
        ),
      ),
    );
  }
}
