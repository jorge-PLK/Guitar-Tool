import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/features/backing/widgets/mixer_channel.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_fader.dart';
import 'package:toneforge/widgets/tf_mixer_channel.dart';

/// Canal master (BackingMixer.swift:238-255): fader sin medidor ni M/S.
class MasterChannel extends ConsumerWidget {
  const MasterChannel({super.key, required this.height});

  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final double db = ref.watch(studyStoreProvider.select((s) => s.transport?.masterGainDB ?? 0));
    return TfMixerChannel(
      variant: TfMixerChannelVariant.master,
      height: height,
      title: Text(
        l.backing_master,
        maxLines: 1,
        style: TfText.body(TfSize.font12, TfWeight.semibold).copyWith(color: TfColors.text),
      ),
      faderBuilder: (double fh) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: TfSpace.s18),
        child: TfFader(
          dB: db,
          height: fh,
          semanticLabel: l.backing_master,
          semanticValue: (double v) => mixerDbText(context, v),
          onChanged: (double v) => ref.read(studyStoreProvider.notifier).setMaster(v),
        ),
      ),
      value: Text(mixerDbText(context, db), style: TfText.body(TfSize.font12).copyWith(color: TfColors.text2)),
    );
  }
}
