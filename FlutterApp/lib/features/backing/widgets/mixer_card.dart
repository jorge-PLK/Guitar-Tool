import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/study.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/features/backing/widgets/compact_mixer.dart';
import 'package:toneforge/features/backing/widgets/guitar_stereo_toggle.dart';
import 'package:toneforge/features/backing/widgets/master_channel.dart';
import 'package:toneforge/features/backing/widgets/mixer_channel.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_card.dart';
import 'package:toneforge/widgets/tf_divider.dart';
import 'package:toneforge/widgets/tf_scroll.dart';

/// Tarjeta «Mezclador» (BackingMixer.swift:30-70). [compact] = rejilla de acordes expandida;
/// [lowHeight] = ventana baja (< 780): mínimo del cuerpo 176 en vez de 210.
class MixerCard extends ConsumerWidget {
  const MixerCard({super.key, required this.compact, required this.lowHeight});

  final bool compact;
  final bool lowHeight;

  /// Alto del cuerpo: mínimo (210; 176 baja) e ideal/máximo (276 + 10 del scroll).
  static const double bodyMinHeight = 210;
  static const double bodyMinHeightLow = 176;
  static const double bodyIdealHeight = TfSize.mixerChannelHeight + 10;

  /// Cabecera (22) + padding vertical (28) + separación (10).
  static const double _chrome = 28 + 22 + 10;

  /// Alto mínimo de la tarjeta completa: 270 (236 baja). Ideal: 346.
  static const double minHeight = _chrome + bodyMinHeight;
  static const double minHeightLow = _chrome + bodyMinHeightLow;
  static const double idealHeight = _chrome + bodyIdealHeight;

  /// Alto del canal para un alto de cuerpo: `clamp(alto − 10, 166, 276)`.
  static double channelHeightFor(double bodyHeight) =>
      (bodyHeight - 10).clamp(TfSize.mixerChannelMinHeight, TfSize.mixerChannelHeight).toDouble();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final StudyOpenResult? study = ref.watch(studyStoreProvider.select((s) => s.study));
    final bool hasGuitar = study != null &&
        (study.usesSeparatedGuitars ||
            study.transport.channels.any((StudyChannel c) => c.kind == StudyStemKind.guitar));
    final String output = study?.transport.outputName ?? '';
    return TfCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: TfSpace.s20, vertical: TfSpace.s14),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            final Widget header = SizedBox(
              height: 22,
              child: Row(
                spacing: TfSpace.s12,
                children: <Widget>[
                  Text(l.backing_mixer, style: TfText.display(18).copyWith(color: TfColors.text)),
                  const Spacer(),
                  if (hasGuitar) const GuitarStereoToggle(),
                  Text(
                    l.backing_mixerOutput(output.isEmpty ? '—' : output),
                    style: TfText.body(TfSize.font12).copyWith(color: TfColors.muted),
                  ),
                ],
              ),
            );
            final double minBody = lowHeight ? bodyMinHeightLow : bodyMinHeight;
            final Widget body = compact
                ? const CompactMixer()
                : _ChannelsBody(study: study, minBody: minBody);
            final bool bounded = c.hasBoundedHeight;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: TfSpace.s10,
              children: <Widget>[
                header,
                if (compact)
                  body
                else if (bounded)
                  Expanded(child: body)
                else
                  SizedBox(height: bodyIdealHeight, child: body),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ChannelsBody extends StatelessWidget {
  const _ChannelsBody({required this.study, required this.minBody});

  final StudyOpenResult? study;
  final double minBody;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double ch = MixerCard.channelHeightFor(math.max(math.min(c.maxHeight, MixerCard.bodyIdealHeight), minBody));
        final StudyOpenResult? s = study;
        final List<StudyChannel> channels = s == null ? const <StudyChannel>[] : orderedMixerChannels(s);
        final bool anySolo = s?.transport.anySolo ?? false;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: TfSpace.s10,
          children: <Widget>[
            MasterChannel(height: ch),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: TfSpace.s6),
              child: TfDivider.vertical(height: math.max(ch - 76, 40)),
            ),
            Expanded(
              child: TfScroll(
                alwaysVisible: true,
                builder: (BuildContext context, ScrollController controller) => SingleChildScrollView(
                  controller: controller,
                  scrollDirection: Axis.horizontal,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: TfSpace.s10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: TfSpace.s10,
                      children: <Widget>[
                        for (final StudyChannel k in channels)
                          MixerChannel(key: ValueKey<String>(k.id), channel: k, anySolo: anySolo, height: ch),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
