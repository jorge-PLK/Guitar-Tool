import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/features/backing/study_position.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/features/tab/tab_loop_menu.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/fmt.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_checkbox.dart';
import 'package:toneforge/widgets/tf_slider.dart';

// Medidas de TabScreen.swift (transporte) sin token propio.
const double _playSize = 52;
const double _playIcon = 20;
const double _rewindIcon = 15;
const double _tempoSliderWidth = 120;
const double _tempoValueWidth = 54;

const List<FontFeature> _tabular = <FontFeature>[FontFeature.tabularFigures()];

/// Transporte de Tablatura: inicio, play/pausa, reloj, tempo, metrónomo y menú de bucle.
class TabTransport extends ConsumerWidget {
  const TabTransport({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final double rate = ref.watch(studyStoreProvider.select((s) => s.transport?.rate)) ?? 1;
    final double duration = ref.watch(studyStoreProvider.select((s) => s.transport?.duration)) ?? 0;
    final bool metronomeOn =
        ref.watch(studyStoreProvider.select((s) => s.transport?.metronome.on)) ?? false;
    final bool hasBeats = ref.watch(studyStoreProvider.select((s) =>
        (s.study?.analysis.beats.isNotEmpty ?? false) && (s.transport?.metronome.available ?? false)));
    final StudyStore store = ref.read(studyStoreProvider.notifier);
    return DefaultTextStyle(
      style: TfText.body(TfSize.font13).copyWith(color: TfColors.text2),
      child: Row(
        spacing: TfSpace.s14,
        children: <Widget>[
          _Rewind(label: l.tab_a11yRewind, onTap: () => store.seek(0)),
          const _PlayButton(),
          _Clock(duration: duration),
          Text(l.tab_tempo),
          TfSlider(
            value: rate * 100,
            min: 50,
            max: 200,
            step: 5,
            width: _tempoSliderWidth,
            onChanged: (double v) => store.setRate(v / 100),
          ),
          SizedBox(
            width: _tempoValueWidth,
            child: Text(
              TfFmt.percent(rate),
              style: TfText.body(TfSize.font13, TfWeight.semibold)
                  .copyWith(color: TfColors.text, fontFeatures: _tabular),
            ),
          ),
          TfCheckbox(
            value: metronomeOn,
            label: l.tab_metronome,
            onChanged: hasBeats ? store.setMetronome : null,
          ),
          const TabLoopMenu(),
          const Spacer(),
        ],
      ),
    );
  }
}

class _Rewind extends StatelessWidget {
  const _Rewind({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: const ValueKey<String>('tab_rewind'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: TfSize.controlLg,
            height: TfSize.controlLg,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: TfColors.field,
              shape: BoxShape.circle,
              border: Border.all(color: TfColors.fieldLine, width: TfStroke.hairline),
            ),
            child: const TfIconView(TfIcon.backwardEndFill, size: _rewindIcon, color: TfColors.text),
          ),
        ),
      ),
    );
  }
}

class _PlayButton extends ConsumerWidget {
  const _PlayButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool playing = ref.watch(studyPositionProvider.select((e) => e.playing));
    final StudyStore store = ref.read(studyStoreProvider.notifier);
    return Semantics(
      button: true,
      label: playing ? l.tab_a11yPause : l.tab_a11yPlay,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: const ValueKey<String>('tab_play'),
          behavior: HitTestBehavior.opaque,
          onTap: playing ? store.pause : store.play,
          child: Container(
            width: _playSize,
            height: _playSize,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: TfColors.accent, shape: BoxShape.circle),
            child: TfIconView(
              playing ? TfIcon.pauseFill : TfIcon.playFill,
              size: _playIcon,
              color: TfColors.accentInk,
            ),
          ),
        ),
      ),
    );
  }
}

/// «m:ss» en `text` + « / m:ss» en `muted`. Solo repinta si cambia el texto (30 Hz de `study.position`).
class _Clock extends ConsumerWidget {
  const _Clock({required this.duration});

  final double duration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String now = ref.watch(studyPositionProvider.select((e) => TfFmt.clock(e.seconds)));
    return Text.rich(
      TextSpan(children: <InlineSpan>[
        TextSpan(text: now, style: const TextStyle(color: TfColors.text)),
        TextSpan(text: ' / ${TfFmt.clock(duration)}', style: const TextStyle(color: TfColors.muted)),
      ]),
      maxLines: 1,
      softWrap: false,
      style: TfText.display(20).copyWith(fontFeatures: _tabular),
    );
  }
}
