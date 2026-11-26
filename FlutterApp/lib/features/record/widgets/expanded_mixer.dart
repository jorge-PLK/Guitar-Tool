import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/fmt.dart';
import '../../../theme/tokens.dart';
import '../../../theme/typography.dart';
import '../../../widgets/tf_divider.dart';
import '../../../widgets/tf_fader.dart';
import '../../../widgets/tf_level_bar.dart';
import '../../../widgets/tf_mixer_channel.dart';
import '../../../widgets/tf_scroll.dart';
import '../input_meter.dart';
import '../mixer_store.dart';
import 'compact_mixer.dart';
import 'vertical_level_painter.dart';

/// Mezclador expandido (RecordMixer.swift:39-56): Master, entrada de guitarra, separador y un
/// `TfMixerChannel` por canal de stems, guitarras y «Tú · parte».
class ExpandedMixer extends ConsumerWidget {
  const ExpandedMixer({super.key, this.inputLevel});

  /// Nivel de la entrada de guitarra 0…1 (G2: sin fuente en los stores, el padre lo aporta).
  final ValueListenable<InputMeter>? inputLevel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final MixerState s = ref.watch(mixerStoreProvider);
    final List<MixerRow> rows = MixerRow.of(s);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: TfSpace.s10,
      children: <Widget>[
        MasterChannel(gainDb: s.masterGainDB.toDouble()),
        GuitarInputChannel(level: inputLevel),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: TfSpace.s6),
          child: TfDivider.vertical(height: TfSize.mixerDividerHeight),
        ),
        Expanded(
          child: TfScroll(
            alwaysVisible: true,
            builder: (BuildContext context, ScrollController c) => SingleChildScrollView(
              controller: c,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(bottom: TfSpace.s10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: TfSpace.s10,
                children: <Widget>[for (final MixerRow r in rows) _StemChannel(row: r)],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

TextStyle _title() => TfText.body(TfSize.font12, TfWeight.semibold).copyWith(color: TfColors.text);

TextStyle _caption(Color color) => TfText.body(TfSize.font12).copyWith(color: color);

/// Canal Master (`RecordMasterChannel`, RM:172-189): fader 28×150 sin medidor ni M/S.
class MasterChannel extends ConsumerWidget {
  const MasterChannel({super.key, required this.gainDb});

  final double gainDb;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String locale = Localizations.localeOf(context).languageCode;
    return TfMixerChannel(
      variant: TfMixerChannelVariant.master,
      title: Text(l.record_master, style: _title()),
      faderBuilder: (double h) => TfFader(
        dB: gainDb,
        height: h,
        semanticLabel: l.record_faderA11y,
        semanticValue: (double d) => TfFmt.db(d, locale),
        onChanged: (double v) => ref.read(mixerStoreProvider.notifier).setMaster(v),
      ),
      value: Text(TfFmt.db(gainDb, locale), style: _caption(TfColors.text2)),
    );
  }
}

/// Entrada de guitarra (`GuitarInputChannel`, RM:192-216): solo medidor 12×150, sin gesto.
class GuitarInputChannel extends StatelessWidget {
  const GuitarInputChannel({super.key, this.level});

  final ValueListenable<InputMeter>? level;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return TfMixerChannel(
      title: Text(l.record_yourGuitar, style: _title()),
      faderBuilder: (double h) => Semantics(
        label: l.record_inputLevelA11y,
        child: inputLevelBuilder(level, (InputMeter v) => VerticalLevelMeter(level: v.level, hot: v.hot, height: h)),
      ),
      value: Text(l.record_inputWord, style: _caption(TfColors.text2)),
    );
  }
}

class _StemChannel extends ConsumerWidget {
  const _StemChannel({required this.row});

  final MixerRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String locale = Localizations.localeOf(context).languageCode;
    return TfMixerChannel(
      dimmed: row.dimmed,
      title: Text(row.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _title()),
      faderBuilder: (double h) => TfFader(
        dB: row.gainDB,
        height: h,
        semanticLabel: l.record_faderA11y,
        semanticValue: (double d) => TfFmt.db(d, locale),
        onChanged: (double v) => ref.read(mixerStoreProvider.notifier).setGain(row.id, v),
      ),
      levelBuilder: (double h) => TfLevelBar(rmsDb: row.rmsDb, height: h, dim: row.dimmed),
      value: Text(
        row.muted ? l.record_muted : TfFmt.db(row.gainDB, locale),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _caption(TfColors.text2),
      ),
      toggles: MixerToggles(row: row),
    );
  }
}
