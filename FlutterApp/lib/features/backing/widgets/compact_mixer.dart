import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/study.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/features/backing/widgets/mixer_channel.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_divider.dart';
import 'package:toneforge/widgets/tf_fader.dart';
import 'package:toneforge/widgets/tf_slider.dart';

/// Mezclador con la rejilla expandida (BackingMixer.swift:87-129): master deslizante y M/S por canal, sin faders.
class CompactMixer extends ConsumerWidget {
  const CompactMixer({super.key});

  static const double masterSliderWidth = 150;
  static const double valueWidth = 62;
  static const double minBlockWidth = 78;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final StudyOpenResult? study = ref.watch(studyStoreProvider.select((s) => s.study));
    if (study == null) return const SizedBox.shrink();
    final double db = study.transport.masterGainDB;
    final bool anySolo = study.transport.anySolo;
    final List<StudyChannel> channels = orderedMixerChannels(study);
    return Row(
      spacing: TfSpace.s16,
      children: <Widget>[
        Text(
          l.backing_master,
          style: TfText.body(TfSize.font13, TfWeight.semibold).copyWith(color: TfColors.text),
        ),
        TfSlider(
          value: db,
          min: TfFader.minDb,
          max: TfFader.maxDb,
          snapTo: 0,
          snapTolerance: TfFader.snapDb,
          width: masterSliderWidth,
          onChanged: (double v) => ref.read(studyStoreProvider.notifier).setMaster(v),
        ),
        SizedBox(
          width: valueWidth,
          child: Text(mixerDbText(context, db), style: TfText.body(TfSize.font12).copyWith(color: TfColors.text2)),
        ),
        const TfDivider.vertical(),
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              final int n = channels.length;
              final double w = n == 0
                  ? minBlockWidth
                  : math.max(minBlockWidth, (c.maxWidth - TfSpace.s8 * (n - 1)) / n);
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: TfSpace.s8,
                  children: <Widget>[
                    for (final StudyChannel ch in channels)
                      SizedBox(width: w, child: _Block(channel: ch, dim: isMixerChannelDim(ch, anySolo))),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.channel, required this.dim});

  final StudyChannel channel;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final String title = mixerChannelTitle(AppLocalizations.of(context), channel);
    final Widget block = Column(
      spacing: TfSpace.s4,
      children: <Widget>[
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TfText.body(TfSize.font12, TfWeight.semibold).copyWith(color: TfColors.text),
        ),
        MixerMuteSolo(channel: channel, title: title),
      ],
    );
    return dim ? Opacity(opacity: TfOpacity.muted, child: block) : block;
  }
}
