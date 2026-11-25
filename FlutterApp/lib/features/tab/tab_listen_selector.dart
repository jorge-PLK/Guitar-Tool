import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/tab.dart';
import 'package:toneforge/features/tab/tab_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_progress.dart';

/// Alto de las cápsulas Stems/Transcripción (`TabScreen.swift:263`); sin token en `theme/`.
const double tabListenOptionHeight = 30;

/// Progreso de síntesis derivado de las pistas (el DTO no trae `synthProgress`):
/// `null` si ninguna se está renderizando.
({int done, int total})? tabSynthProgress(TabState? tab) {
  final List<TabTrackInfo> synthing = <TabTrackInfo>[
    for (final TabTrackInfo t in tab?.tracks ?? const <TabTrackInfo>[])
      if (t.synth != null) t,
  ];
  if (!synthing.any((TabTrackInfo t) => t.synth == TabSynth.rendering)) return null;
  return (done: synthing.where((TabTrackInfo t) => t.synth == TabSynth.ready).length, total: synthing.length);
}

/// Selector «Oír: Stems / Transcripción» (`TabScreen.swift:257-283`). Mixto: ninguna activa.
class TabListenSelector extends ConsumerWidget {
  const TabListenSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final TabState? tab = ref.watch(tabStoreProvider.select((TabStoreState s) => s.tab));
    final TabListenMode mode = tab?.listenMode ?? TabListenMode.stems;
    final TabStore store = ref.read(tabStoreProvider.notifier);
    final TextStyle muted = TfText.body(TfSize.font13).copyWith(color: TfColors.muted);
    final ({int done, int total})? progress = tabSynthProgress(tab);
    return Row(
      spacing: TfSpace.s8,
      children: <Widget>[
        Text(l.tab_listenLabel, style: muted),
        _Option(
          title: l.tab_listenStems,
          on: mode == TabListenMode.stems,
          onPressed: () => store.setAllListening(on: false),
        ),
        _Option(
          title: l.tab_listenTranscription,
          on: mode == TabListenMode.transcription,
          onPressed: () => store.setAllListening(on: true),
        ),
        if (mode == TabListenMode.mixed) Text(l.tab_listenMixed, style: muted),
        if (progress != null)
          Row(
            spacing: TfSpace.s6,
            children: <Widget>[
              const TfSpinner.small(),
              Text(l.tab_synthProgress(progress.done, progress.total), style: muted),
            ],
          ),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({required this.title, required this.on, required this.onPressed});

  final String title;
  final bool on;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final Color fg = on ? TfColors.accent : TfColors.text2;
    return Semantics(
      button: true,
      selected: on,
      label: title,
      excludeSemantics: true,
      onTap: onPressed,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: on ? TfColors.accentBg : TfColors.field,
              shape: StadiumBorder(
                side: BorderSide(color: on ? TfColors.accent : TfColors.fieldLine, width: TfStroke.hairline),
              ),
            ),
            child: SizedBox(
              height: tabListenOptionHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: TfSpace.s14),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    title,
                    style: TfText.body(TfSize.font13, on ? TfWeight.semibold : TfWeight.medium).copyWith(color: fg),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
