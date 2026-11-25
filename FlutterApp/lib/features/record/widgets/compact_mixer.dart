import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
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
    final int n = rows.length;
    final double channelsWidth =
        n == 0 ? 0 : n * TfSize.compactChannelWidth + (n - 1) * TfSpace.s6;
    // ViewThatFits de SwiftUI (RecordMixer.swift:117-120): una fila si cabe todo; si no, el
    // encabezado y debajo los canales con desplazamiento horizontal.
    return _ViewThatFits(
      channelsWidth: channelsWidth,
      rowGap: TfSpace.s10,
      columnGap: TfSpace.s8,
      children: <Widget>[header, const TfDivider.vertical(), channels],
    );
  }
}

/// Hijos: encabezado, separador y canales (desplazables). Si `encabezado + separador + canales`
/// caben en el ancho disponible van en una fila (el separador visible); si no, en dos líneas
/// (sin separador, canales con scroll al ancho disponible).
class _ViewThatFits extends MultiChildRenderObjectWidget {
  const _ViewThatFits({
    required this.channelsWidth,
    required this.rowGap,
    required this.columnGap,
    required super.children,
  });

  final double channelsWidth;
  final double rowGap;
  final double columnGap;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderViewThatFits(channelsWidth, rowGap, columnGap);

  @override
  void updateRenderObject(BuildContext context, _RenderViewThatFits r) {
    r
      ..channelsWidth = channelsWidth
      ..rowGap = rowGap
      ..columnGap = columnGap;
  }
}

class _Slot extends ContainerBoxParentData<RenderBox> {}

class _RenderViewThatFits extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _Slot>,
        RenderBoxContainerDefaultsMixin<RenderBox, _Slot> {
  _RenderViewThatFits(this._channelsWidth, this._rowGap, this._columnGap);

  double _channelsWidth;
  double _rowGap;
  double _columnGap;
  bool _oneRow = true;

  set channelsWidth(double v) {
    if (v == _channelsWidth) return;
    _channelsWidth = v;
    markNeedsLayout();
  }

  set rowGap(double v) {
    if (v == _rowGap) return;
    _rowGap = v;
    markNeedsLayout();
  }

  set columnGap(double v) {
    if (v == _columnGap) return;
    _columnGap = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _Slot) {
      child.parentData = _Slot();
    }
  }

  RenderBox get _header => firstChild!;
  RenderBox get _divider => childAfter(_header)!;
  RenderBox get _channels => childAfter(_divider)!;

  @override
  void performLayout() {
    final double max = constraints.maxWidth;
    _header.layout(const BoxConstraints(), parentUsesSize: true);
    _divider.layout(const BoxConstraints(), parentUsesSize: true);
    final double rowWidth = _header.size.width + _rowGap + _divider.size.width + _rowGap + _channelsWidth;
    _oneRow = !max.isFinite || rowWidth <= max;
    if (_oneRow) {
      _channels.layout(BoxConstraints.tightFor(width: _channelsWidth), parentUsesSize: true);
      final double hgt = <double>[_header.size.height, _divider.size.height, _channels.size.height]
          .reduce((double a, double b) => a > b ? a : b);
      double x = 0;
      for (final RenderBox c in <RenderBox>[_header, _divider, _channels]) {
        (c.parentData! as _Slot).offset = Offset(x, (hgt - c.size.height) / 2);
        x += c.size.width + _rowGap;
      }
      size = constraints.constrain(Size(rowWidth, hgt));
    } else {
      _channels.layout(BoxConstraints(maxWidth: max), parentUsesSize: true);
      (_header.parentData! as _Slot).offset = Offset.zero;
      (_channels.parentData! as _Slot).offset =
          Offset(0, _header.size.height + _columnGap);
      final double w = _header.size.width > _channels.size.width ? _header.size.width : _channels.size.width;
      size = constraints.constrain(Size(w, _header.size.height + _columnGap + _channels.size.height));
    }
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.constrain(Size.zero);

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final RenderBox c in <RenderBox>[_header, if (_oneRow) _divider, _channels]) {
      context.paintChild(c, (c.parentData! as _Slot).offset + offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final RenderBox c in <RenderBox>[_channels, if (_oneRow) _divider, _header]) {
      final Offset o = (c.parentData! as _Slot).offset;
      final bool hit = result.addWithPaintOffset(
        offset: o,
        position: position,
        hitTest: (BoxHitTestResult r, Offset p) => c.hitTest(r, position: p),
      );
      if (hit) return true;
    }
    return false;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    visitor(_header);
    if (_oneRow) visitor(_divider);
    visitor(_channels);
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
