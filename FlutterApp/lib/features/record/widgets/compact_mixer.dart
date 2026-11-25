import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/fmt.dart';
import '../../../theme/tokens.dart';
import '../../../theme/typography.dart';
import '../../../widgets/tf_divider.dart';
import '../../../widgets/tf_slider.dart';
import '../../../widgets/tf_toggle_button.dart';
import '../mixer_store.dart';
import 'horizontal_level_painter.dart';

/// Canal del mezclador visto por la interfaz: stems, guitarras y «Tú · parte» (`take-<partId>`).
@immutable
class MixerRow {
  const MixerRow({
    required this.id,
    required this.name,
    required this.gainDB,
    required this.muted,
    required this.solo,
    required this.forced,
    required this.dimmed,
    required this.rmsDb,
  });

  final String id;
  final String name;
  final double gainDB;

  /// Silenciado a la vista: `muted` o forzado (guitarra que sustituye la parte).
  final bool muted;
  final bool solo;

  /// `forcedMuted`: M/S no actúan.
  final bool forced;

  /// Silenciado o solo ajeno: opacidad 0,55 y medidor a 0.
  final bool dimmed;
  final double? rmsDb;

  /// Canales en el orden del núcleo: stems/guitarras y después los «Tú · parte».
  static List<MixerRow> of(MixerState s) {
    final bool anySolo = s.anySolo;
    MixerRow row(String id, String name, num gain, bool muted, bool solo, bool forced) {
      final bool m = muted || forced;
      return MixerRow(
        id: id,
        name: name,
        gainDB: gain.toDouble(),
        muted: m,
        solo: solo,
        forced: forced,
        dimmed: m || (anySolo && !solo),
        rmsDb: s.levels[id]?.rmsDB.toDouble(),
      );
    }

    return <MixerRow>[
      for (final c in s.channels) row(c.id, c.name, c.gainDB, c.muted, c.solo, c.forcedMuted),
      for (final c in s.takeChannels) row(c.id, c.name, c.gainDB, c.muted, c.solo, false),
    ];
  }
}

/// Nivel de la entrada de guitarra (0…1). `null` = sin fuente: medidor a 0.
Widget inputLevelBuilder(ValueListenable<double>? level, Widget Function(double v) builder) {
  if (level == null) return builder(0);
  return ValueListenableBuilder<double>(valueListenable: level, builder: (_, v, _) => builder(v));
}

/// Botones M y S de un canal; sin acción si está forzado a silencio.
class MixerToggles extends ConsumerWidget {
  const MixerToggles({super.key, required this.row, this.size = TfToggleSize.large});

  final MixerRow row;
  final TfToggleSize size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MixerStore store = ref.read(mixerStoreProvider.notifier);
    final bool on = !row.forced;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: TfSpace.s6,
      children: <Widget>[
        TfToggleButton(
          text: l.record_mixer_muteShort,
          on: row.muted,
          size: size,
          semanticLabel: row.muted ? l.record_unmuteA11y(row.name) : l.record_muteA11y(row.name),
          onPressed: on ? () => store.setMute(row.id, !row.muted) : null,
        ),
        TfToggleButton(
          text: l.record_mixer_soloShort,
          on: row.solo,
          size: size,
          semanticLabel: l.record_soloA11y(row.name),
          onPressed: on ? () => store.setSolo(row.id, !row.solo) : null,
        ),
      ],
    );
  }
}

/// Mezclador plegado (RecordMixer.swift:67-135): Master, «Tu guitarra» y un canal compacto por pista.
class CompactMixer extends ConsumerWidget {
  const CompactMixer({super.key, this.inputLevel});

  /// Nivel de la entrada de guitarra 0…1 (G2: sin fuente en los stores, el padre lo aporta).
  final ValueListenable<double>? inputLevel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final MixerState s = ref.watch(mixerStoreProvider);
    final List<MixerRow> rows = MixerRow.of(s);
    final Widget header = _Header(master: s.masterGainDB.toDouble(), inputLevel: inputLevel);
    final Widget channels = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: TfSpace.s6,
        children: <Widget>[for (final MixerRow r in rows) _CompactChannel(row: r)],
      ),
    );
    // Desvío: SwiftUI usa ViewThatFits (una fila o dos); Flutter no lo tiene, queda siempre una
    // fila con los canales desplazables.
    return Row(
      spacing: TfSpace.s10,
      children: <Widget>[header, const TfDivider.vertical(), Expanded(child: channels)],
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.master, required this.inputLevel});

  final double master;
  final ValueListenable<double>? inputLevel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String locale = Localizations.localeOf(context).languageCode;
    final TextStyle label = TfText.body(TfSize.font12, TfWeight.semibold).copyWith(color: TfColors.text);
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: TfSpace.s10,
      children: <Widget>[
        Text(l.record_master, style: label),
        TfSlider(
          width: TfSize.compactMasterWidth,
          min: kFaderMinDb,
          max: kFaderMaxDb,
          value: master,
          snapTo: 0,
          snapTolerance: kFaderSnapDb,
          onChanged: (double v) => ref.read(mixerStoreProvider.notifier).setMaster(v),
        ),
        Text(
          TfFmt.db(master, locale),
          style: TfText.body(TfSize.font12).copyWith(color: TfColors.text2),
        ),
        const TfDivider.vertical(),
        Text(l.record_yourGuitar, style: label),
        Semantics(
          label: l.record_inputLevelA11y,
          child: inputLevelBuilder(inputLevel, (double v) => HorizontalLevelMeter(level: v)),
        ),
      ],
    );
  }
}

class _CompactChannel extends StatelessWidget {
  const _CompactChannel({required this.row});

  final MixerRow row;

  @override
  Widget build(BuildContext context) {
    final Widget channel = SizedBox(
      width: TfSize.compactChannelWidth,
      child: Column(
        spacing: TfSpace.s4,
        children: <Widget>[
          Text(
            row.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TfText.body(TfSize.font12, TfWeight.semibold).copyWith(color: TfColors.text),
          ),
          // SwiftUI también desborda 2 pt (36+6+36 en un marco de 76) y los centra.
          SizedBox(
            height: TfSize.controlMd,
            child: OverflowBox(maxWidth: double.infinity, child: MixerToggles(row: row)),
          ),
        ],
      ),
    );
    return row.dimmed ? Opacity(opacity: TfOpacity.muted, child: channel) : channel;
  }
}
