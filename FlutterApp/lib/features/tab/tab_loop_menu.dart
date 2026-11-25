import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/study.dart';
import 'package:toneforge/contract/tab.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/features/tab/tab_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/fmt.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_menu.dart';

/// `true` si [loop] es el bucle que el núcleo crea para el tramo seleccionado (campo `span`).
bool isSpanLoop(StudyLoop loop) => loop.span;

/// Menú «Bucle» del transporte de Tablatura (TabScreen.swift:457-479).
class TabLoopMenu extends ConsumerWidget {
  const TabLoopMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final StudyLoop? loop = ref.watch(studyStoreProvider.select((s) => s.transport?.loop));
    final List<StudySectionInfo> sections =
        ref.watch(studyStoreProvider.select((s) => s.study?.sections)) ?? const <StudySectionInfo>[];
    final bool hasSpan = ref.watch(tabStoreProvider.select((s) => s.tab?.span != null));
    final TabBarRange? bar = ref.watch(tabStoreProvider.select((s) => s.tab?.selection?.barRange));
    final StudyStore study = ref.read(studyStoreProvider.notifier);
    final TabStore tab = ref.read(tabStoreProvider.notifier);

    final String label;
    if (loop == null) {
      label = l.tab_loop;
    } else {
      final String name = loop.name == null
          ? l.tab_loopFree
          : (isSpanLoop(loop) ? l.tab_loopSelection : loop.name!);
      label = l.tab_loopActive(name, TfFmt.clock(loop.start), TfFmt.clock(loop.end));
    }

    final Color color = loop == null ? TfColors.text2 : TfColors.accent;
    final List<TfMenuEntry> entries = <TfMenuEntry>[
      TfMenuItem(
        label: l.tab_loopNone,
        onSelected: () async {
          await tab.span(TabSpanAction.clear, keepAnchor: true);
          await study.clearLoop();
        },
      ),
      if (hasSpan)
        TfMenuItem(label: l.tab_loopSelection, onSelected: () => tab.span(TabSpanAction.apply)),
      if (bar != null)
        TfMenuItem(
          label: l.tab_loopBar(bar.bar + 1),
          onSelected: () => study.setLoop(bar.start, bar.end, name: l.tab_loopBarName(bar.bar + 1)),
        ),
      for (final StudySectionInfo s in sections)
        TfMenuItem(label: s.name, onSelected: () => study.setLoop(s.start, s.end, name: s.name)),
    ];

    return TfMenu(
      entries: entries,
      builder: (BuildContext context, VoidCallback toggle) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: const ValueKey<String>('tab_loop_menu'),
          behavior: HitTestBehavior.opaque,
          onTap: toggle,
          child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: TfText.body(TfSize.font13, TfWeight.semibold).copyWith(color: color),
            ),
            const SizedBox(width: TfSpace.s4),
            TfIconView(TfIcon.chevronDown, size: TfSize.backingInfoChevron, color: color),
          ]),
        ),
      ),
    );
  }
}
