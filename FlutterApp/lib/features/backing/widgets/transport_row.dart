import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/features/backing/study_position.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/features/backing/widgets/loop_marking.dart';
import 'package:toneforge/features/backing/widgets/loop_pill.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/fmt.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_checkbox.dart';
import 'package:toneforge/widgets/tf_slider.dart';
import 'package:toneforge/widgets/tf_tooltip.dart';

// Medidas de BackingTimeline.swift:427-468 sin token propio.
const double _playSize = 52;
const double _playIcon = 20;
const double _markHeight = 30;
const double _tempoSliderWidth = 120;
const double _tempoValueWidth = 54;
const double _flowSpacing = 14;
const double _runSpacing = 10;

const List<FontFeature> _tabular = <FontFeature>[FontFeature.tabularFigures()];

/// Fila de transporte (BT:427-468): play, reloj, Inicio/Fin, píldora de bucle, tempo y metrónomo.
class TransportRow extends ConsumerWidget {
  const TransportRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final transport = ref.watch(studyStoreProvider.select((s) => s.transport));
    final bool hasBeats = ref.watch(studyStoreProvider.select(
        (s) => (s.study?.analysis.beats.isNotEmpty ?? false) && (s.transport?.metronome.available ?? false)));
    final StudyStore store = ref.read(studyStoreProvider.notifier);
    final double rate = transport?.rate ?? 1;
    return SizedBox(
      width: double.infinity,
      child: DefaultTextStyle(
        style: TfText.body(TfSize.font13).copyWith(color: TfColors.text2),
        child: Wrap(
          spacing: _flowSpacing,
          runSpacing: _runSpacing,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            const _PlayButton(),
            _Clock(duration: transport?.duration ?? 0),
            const _LoopMarks(),
            if (transport?.loop != null) LoopPill(loop: transport!.loop!, onClear: store.clearLoop),
            Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
              Text(l.backing_tempo),
              const SizedBox(width: TfSpace.s10),
              TfSlider(
                value: rate * 100,
                min: 50,
                max: 200,
                step: 5,
                width: _tempoSliderWidth,
                onChanged: (double v) => store.setRate(v / 100),
              ),
              const SizedBox(width: TfSpace.s10),
              SizedBox(
                width: _tempoValueWidth,
                child: Text(
                  TfFmt.percent(rate),
                  style: TfText.body(TfSize.font13, TfWeight.semibold)
                      .copyWith(color: TfColors.text, fontFeatures: _tabular),
                ),
              ),
            ]),
            TfCheckbox(
              value: transport?.metronome.on ?? false,
              label: l.backing_metronome,
              onChanged: hasBeats ? store.setMetronome : null,
            ),
          ],
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
      label: playing ? l.backing_pause : l.backing_play,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: const ValueKey<String>('transport_play'),
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

/// «m:ss» en `text` + « / m:ss» en `muted`, display 20 con cifras tabulares. Aislado para que el
/// reloj (≤ 30 Hz) no reconstruya el resto.
class _Clock extends ConsumerWidget {
  const _Clock({required this.duration});

  final double duration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final double t = ref.watch(studyPositionProvider.select((e) => e.seconds));
    return Text.rich(
      TextSpan(children: <InlineSpan>[
        TextSpan(text: TfFmt.clock(t), style: const TextStyle(color: TfColors.text)),
        TextSpan(text: ' / ${TfFmt.clock(duration)}', style: const TextStyle(color: TfColors.muted)),
      ]),
      maxLines: 1,
      softWrap: false,
      style: TfText.display(20).copyWith(fontFeatures: _tabular),
    );
  }
}

class _LoopMarks extends ConsumerWidget {
  const _LoopMarks();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final double? pending = ref.watch(pendingLoopStartProvider);
    final bool hasLoop = ref.watch(studyStoreProvider.select((s) => s.transport?.loop != null));
    return Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
      TfTooltip(
        message: l.backing_loopStartTooltip,
        child: pending == null
            ? TfSecondaryButton(
                label: l.backing_sectionStart, height: _markHeight, onPressed: () => markLoopStart(ref))
            : _AccentButton(
                label: l.backing_loopStartButton(TfFmt.clock(pending)), onTap: () => markLoopStart(ref)),
      ),
      const SizedBox(width: TfSpace.s6),
      TfTooltip(
        message: l.backing_loopEndTooltip,
        child: TfSecondaryButton(
          label: l.backing_loopEnd,
          height: _markHeight,
          onPressed: pending == null && !hasLoop ? null : () => markLoopEnd(ref),
        ),
      ),
    ]);
  }
}

/// `SecondaryButton(30)` con el texto en `accent` (inicio pendiente); el kit no admite color de etiqueta.
class _AccentButton extends StatelessWidget {
  const _AccentButton({required this.label, required this.onTap});

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
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            height: _markHeight,
            padding: const EdgeInsets.symmetric(horizontal: TfSpace.s16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: TfColors.field,
              borderRadius: BorderRadius.circular(TfRadius.control),
              border: Border.all(color: TfColors.fieldLine, width: TfStroke.hairline),
            ),
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: TfText.body(TfSize.font14, TfWeight.medium).copyWith(color: TfColors.accent),
            ),
          ),
        ),
      ),
    );
  }
}
