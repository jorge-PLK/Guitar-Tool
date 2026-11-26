import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/study.dart';
import 'package:toneforge/features/backing/study_position.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/features/backing/widgets/chord_diagram_card.dart';
import 'package:toneforge/features/backing/widgets/chord_strip.dart';
import 'package:toneforge/features/backing/widgets/chords_expanded.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';

/// Índice del acorde sonando en [seconds] (`start <= t < end`).
int? currentChordIndex(List<StudyChord> chords, double seconds) {
  for (int i = 0; i < chords.length; i++) {
    if (chords[i].start <= seconds && seconds < chords[i].end) return i;
  }
  return null;
}

/// Primer acorde posterior al actual con otro índice y que sea acorde (< 168: sin «?» ni «N»).
StudyChord? nextChord(List<StudyChord> chords, int? current) {
  if (current == null) return null;
  for (int i = current + 1; i < chords.length; i++) {
    if (chords[i].index != chords[current].index && chords[i].index < 168) return chords[i];
  }
  return null;
}

/// Área de acordes (BT:149-174): [tira ‖ tarjeta] plegada o [rejilla ‖ tarjeta] expandida, con el marco de
/// edición. Lee el store y la posición; no tiene estado propio.
class ChordsArea extends ConsumerWidget {
  const ChordsArea({super.key, this.gridBuilder, this.sectionsLayer, this.onEditChord});

  /// SLOT: ChordGrid. Rejilla expandida; recibe el ancho que deja la tarjeta.
  final WidgetBuilder? gridBuilder;

  /// SLOT: SectionBoxesLayer (ver [ChordStrip.sectionsLayer]).
  final Widget Function(BuildContext context, ChordStripLayout layout)? sectionsLayer;
  final void Function(int index)? onEditChord;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final StudyStore store = ref.read(studyStoreProvider.notifier);
    final StudyOpenResult? study = ref.watch(studyStoreProvider.select((s) => s.study));
    final bool edit = ref.watch(studyStoreProvider.select((s) => s.editMode));
    final bool expanded = ref.watch(chordsExpandedProvider);
    final List<StudyChord> chords = study?.analysis.chords ?? const <StudyChord>[];
    final int? cur = ref.watch(studyPositionProvider.select((p) => currentChordIndex(chords, p.seconds)));
    final StudyLoop? loop = study?.transport.loop;
    final StudyChord? current = cur == null ? null : chords[cur];
    final Widget card = ChordDiagramCard(
      current: current,
      next: nextChord(chords, cur),
      capo: study?.transport.capo ?? 0,
    );

    final Widget body;
    if (expanded) {
      body = Row(
        key: const ValueKey<String>('chords-grid'),
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: TfSpace.s12,
        children: <Widget>[
          // SLOT: ChordGrid
          Expanded(child: gridBuilder?.call(context) ?? const SizedBox.shrink()),
          card,
        ],
      );
    } else {
      body = Row(
        key: const ValueKey<String>('chords-strip'),
        spacing: TfSpace.s12,
        children: <Widget>[
          Expanded(
            child: chords.isEmpty
                ? SizedBox(
                    height: 36,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        study?.analysis.state == StudyAnalysisState.ready
                            ? l.backing_noChords
                            : l.backing_chordsAfterAnalysis,
                        style: TfText.body(13).copyWith(color: TfColors.muted),
                      ),
                    ),
                  )
                : ChordStrip(
                    chords: chords,
                    current: cur,
                    downbeats: study?.analysis.downbeats ?? const <double>[],
                    bpm: study?.analysis.bpm,
                    loopStart: loop?.start,
                    loopEnd: loop?.end,
                    edit: edit,
                    onEditChord: onEditChord,
                    sectionsLayer: sectionsLayer,
                    onSeek: store.seek,
                    onLoop: (double s, double e, {required bool bar}) => store.setLoop(
                      s,
                      e,
                      name: bar ? l.backing_loopNameBars : l.backing_loopNameChords,
                      snap: bar ? StudySnap.bar : StudySnap.chord,
                    ),
                  ),
          ),
          card,
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.all(TfSpace.s8),
      decoration: BoxDecoration(
        color: edit ? TfColors.accentBg.withValues(alpha: TfOpacity.dim) : null,
        borderRadius: BorderRadius.circular(TfRadius.tile),
        // TODO token: trazo 1,5 del marco de edición (BT:172), sin token en TfStroke.
        border: Border.all(
          color: TfColors.accent.withValues(alpha: edit ? 1 : 0),
          width: (TfStroke.hairline + TfStroke.thick) / 2,
        ),
      ),
      child: AnimatedSize(
        duration: TfMotion.expand,
        curve: Curves.easeInOut,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: TfMotion.expand,
          switchInCurve: Curves.easeInOut,
          switchOutCurve: Curves.easeInOut,
          transitionBuilder: (Widget w, Animation<double> a) => FadeTransition(opacity: a, child: w),
          layoutBuilder: (Widget? current, List<Widget> previous) => Stack(
            alignment: Alignment.topCenter,
            children: <Widget>[...previous, ?current],
          ),
          child: body,
        ),
      ),
    );
  }
}
