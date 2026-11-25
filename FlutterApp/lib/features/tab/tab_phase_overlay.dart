import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/tab.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/features/tab/songsterr_store.dart';
import 'package:toneforge/features/tab/tab_store.dart';
import 'package:toneforge/features/tab/tab_track_strip.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_accent_bar.dart';
import 'package:toneforge/widgets/tf_buttons.dart';

/// Mensajes de fase sobre el lienzo (`TabScreen.swift:321-362`). Cubre el rectángulo del lienzo.
class TabPhaseOverlay extends ConsumerWidget {
  const TabPhaseOverlay({super.key, this.webError});

  /// Texto de la página cuando alphaTab falla; solo se muestra con `ready`.
  final String? webError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TabStoreState store = ref.watch(tabStoreProvider);
    final TabState? tab = store.tab;
    final AppLocalizations l = AppLocalizations.of(context);
    final TabPhase? phase = tab?.phase;
    switch (phase) {
      case TabPhase.ready:
        final String? e = webError;
        if (e == null || e.isEmpty) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.all(TfSpace.s16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(l.tab_webError, style: _body(TfColors.danger)),
                Text(e, style: _body(TfColors.danger)),
              ],
            ),
          ),
        );
      case TabPhase.working:
        final List<TabTrackInfo> pending = tabPending(tab);
        final bool hasEntries = tabEntries(tab).isNotEmpty;
        return _Box(
          opaque: !hasEntries,
          spacing: TfSpace.s12,
          children: <Widget>[
            Text(l.tab_workingTitle, key: const ValueKey<String>('phase-title'), style: _title()),
            Text(l.tab_workingBody, style: _body(TfColors.muted)),
            for (final TabTrackInfo t in pending)
              Row(
                key: ValueKey<String>('progress-${t.id}'),
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SizedBox(
                    width: TfSize.tabNameWidth,
                    child: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _body(TfColors.text)),
                  ),
                  const SizedBox(width: TfSpace.s12),
                  SizedBox(
                    width: TfSize.tabPhaseBarWidth,
                    child: TfAccentBar(value: store.progress[t.id]?.fraction ?? t.progress),
                  ),
                ],
              ),
          ],
        );
      case TabPhase.choosingSource:
        return _Box(
          opaque: true,
          spacing: TfSpace.s10,
          children: <Widget>[
            Text(l.tab_choosingTitle, key: const ValueKey<String>('phase-title'), style: _title()),
            Text(l.tab_choosingBody, style: _body(TfColors.muted)),
            Wrap(
              spacing: TfSpace.s10,
              runSpacing: TfSpace.s10,
              children: <Widget>[
                TfSecondaryButton(
                  key: const ValueKey<String>('phase-songsterr'),
                  label: l.tab_choosingSongsterr,
                  height: TfSize.pillHeight,
                  onPressed: () => ref.read(songsterrStoreProvider.notifier).open(),
                ),
                TfSecondaryButton(
                  key: const ValueKey<String>('phase-automatic'),
                  label: l.tab_choosingAutomatic,
                  height: TfSize.pillHeight,
                  onPressed: () => ref.read(tabStoreProvider.notifier).setSource(TabSource.automatic),
                ),
              ],
            ),
          ],
        );
      case TabPhase.waitingAnalysis:
        return _message(
          l.tab_waitingTitle,
          l.tab_waitingBody,
          action: TfSecondaryButton(
            key: const ValueKey<String>('phase-analyze'),
            label: l.tab_waitingAction,
            height: TfSize.pillHeight,
            onPressed: () => ref.read(studyStoreProvider.notifier).analyze(),
          ),
        );
      case TabPhase.empty:
        return _message(l.tab_emptyTitle, l.tab_emptyBody);
      case TabPhase.failed:
        return _message(l.tab_failedTitle, tab?.error ?? '');
      case TabPhase.unknown:
      case null:
        return const SizedBox.shrink();
    }
  }

  static Widget _message(String title, String body, {Widget? action}) => _Box(
        opaque: true,
        spacing: TfSpace.s10,
        children: <Widget>[
          Text(title, key: const ValueKey<String>('phase-title'), style: _title()),
          if (body.isNotEmpty) Text(body, style: _body(TfColors.muted)),
          ?action,
        ],
      );

  static TextStyle _title() => TfText.display(18).copyWith(color: TfColors.text);
  static TextStyle _body(Color c) => TfText.body(TfSize.font13).copyWith(color: c);
}

/// Caja común: padding 24, arriba a la izquierda, rellena el rectángulo; fondo `card` o transparente.
class _Box extends StatelessWidget {
  const _Box({required this.opaque, required this.spacing, required this.children});

  final bool opaque;
  final double spacing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey<String>('phase-box'),
      decoration: BoxDecoration(color: opaque ? TfColors.card : null),
      child: SizedBox.expand(
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.all(TfSpace.s24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: spacing,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}
