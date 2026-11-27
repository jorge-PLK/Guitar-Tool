import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/montage.dart';
import 'package:toneforge/features/montage/montage_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_card.dart';
import 'package:toneforge/widgets/tf_dropdown.dart';

// Medidas de la miniatura (MV:297-317); sin token propio.
const double _kThumbW = 64;
const double _kLandscapeW = 56;
const double _kLandscapeH = 30;
const double _kPortraitW = 24;
const double _kPortraitH = 40;
const double _kRowMinHeight = 52;
const double _kMinScale = 0.8;
// Ancho del picker de rítmica tal como lo dibuja SwiftUI (vertical.png).
const double _kRhythmW = 204;

/// Distribución de la miniatura de losetas.
enum _Shape { side, grid, stack, single, singleLandscape }

class _LayoutDef {
  const _LayoutDef(this.id, this.shape, this.name, this.desc);
  final String id;
  final _Shape shape;
  final String name;
  final String desc;
}

List<_LayoutDef> _layouts(AppLocalizations l) => <_LayoutDef>[
      _LayoutDef('side', _Shape.side, l.montageLayoutSideName, l.montageLayoutSideDesc),
      _LayoutDef('grid', _Shape.grid, l.montageLayoutGridName, l.montageLayoutGridDesc),
      _LayoutDef('stack', _Shape.stack, l.montageLayoutStackName, l.montageLayoutStackDesc),
      _LayoutDef('single', _Shape.single, l.montageLayoutSingleName, l.montageLayoutSinglePortraitDesc),
      _LayoutDef('single-landscape', _Shape.singleLandscape, l.montageLayoutSingleName, l.montageLayoutSingleLandscapeDesc),
    ];

/// Columna «Layout» de Montaje (MV:241-295).
class MontageLayoutColumn extends ConsumerWidget {
  const MontageLayoutColumn({super.key, required this.snapshot});

  final MontageSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MontageStore store = ref.read(montageStoreProvider.notifier);
    return TfCard(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: TfSpace.s18, vertical: TfSpace.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: TfSpace.s8,
          children: <Widget>[
            Text(l.montageLayout, style: TfText.display(TfSize.font18).copyWith(color: TfColors.text)),
            for (final _LayoutDef d in _layouts(l))
              _LayoutButton(def: d, on: snapshot.layout == d.id, onTap: () => store.setLayout(d.id)),
            if (snapshot.isSingleShot) _RhythmPicker(snapshot: snapshot, onChanged: store.setSingleRhythm),
          ],
        ),
      ),
    );
  }
}

class _LayoutButton extends StatelessWidget {
  const _LayoutButton({required this.def, required this.on, required this.onTap});

  final _LayoutDef def;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: on,
      label: def.name,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: _kRowMinHeight),
            padding: const EdgeInsets.symmetric(horizontal: TfSpace.s8, vertical: TfSpace.s6),
            decoration: BoxDecoration(
              color: on ? TfColors.accentBg : TfColors.field,
              borderRadius: BorderRadius.circular(TfRadius.tile),
              border: Border.all(color: on ? TfColors.accent : TfColors.fieldLine, width: TfStroke.hairline),
            ),
            child: Row(
              spacing: TfSpace.s10,
              children: <Widget>[
                _Thumb(shape: def.shape),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    spacing: TfSpace.s2,
                    children: <Widget>[
                      Text(def.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TfText.body(TfSize.font14, TfWeight.semibold).copyWith(color: TfColors.text)),
                      _ScaledLine(def.desc, TfText.body(TfSize.font11).copyWith(color: TfColors.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Una línea que se encoge hasta el 80 % antes de truncar: `minimumScaleFactor(0.8)` (MV:263).
class _ScaledLine extends StatelessWidget {
  const _ScaledLine(this.text, this.style);

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final TextPainter p = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        final double natural = p.width;
        p.dispose();
        final double k = natural <= c.maxWidth ? 1 : (c.maxWidth / natural).clamp(_kMinScale, 1.0);
        return Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style.copyWith(fontSize: (style.fontSize ?? TfSize.font11) * k),
        );
      },
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.shape});

  final _Shape shape;

  static Widget _tile() => DecoratedBox(
        decoration: BoxDecoration(color: TfColors.tileGrey, borderRadius: BorderRadius.circular(TfRadius.r3)),
        child: const SizedBox.expand(),
      );

  static Widget _row() => Row(
        spacing: TfSpace.s3,
        children: <Widget>[Expanded(child: _tile()), Expanded(child: _tile())],
      );

  @override
  Widget build(BuildContext context) {
    final (double, double, Widget) c = switch (shape) {
      _Shape.side => (_kLandscapeW, _kLandscapeH, _row()),
      _Shape.grid => (
          _kLandscapeW,
          _kLandscapeH,
          Column(spacing: TfSpace.s3, children: <Widget>[Expanded(child: _row()), Expanded(child: _row())]),
        ),
      _Shape.stack => (
          _kPortraitW,
          _kPortraitH,
          Column(spacing: TfSpace.s3, children: <Widget>[Expanded(child: _tile()), Expanded(child: _tile())]),
        ),
      _Shape.single => (_kPortraitW, _kPortraitH, _tile()),
      _Shape.singleLandscape => (_kLandscapeW, _kLandscapeH, _tile()),
    };
    return SizedBox(
      width: _kThumbW,
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(color: TfColors.bg, borderRadius: BorderRadius.circular(TfRadius.small)),
          child: Padding(
            padding: const EdgeInsets.all(TfSpace.s4),
            child: SizedBox(width: c.$1, height: c.$2, child: c.$3),
          ),
        ),
      ),
    );
  }
}

/// «Rítmica del plano único» (MV:283-294): automática + partes candidatas.
class _RhythmPicker extends StatelessWidget {
  const _RhythmPicker({required this.snapshot, required this.onChanged});

  final MontageSnapshot snapshot;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final List<String> parts = snapshot.singleRhythmCandidates;
    // El núcleo da ids de parte; el nombre sale del carril con ese id.
    String name(String id) {
      for (final MontageLaneInfo lane in snapshot.lanes) {
        if (lane.id == id) return lane.partName;
      }
      return id;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: TfSpace.s4,
      children: <Widget>[
        Text(l.montageSingleRhythm, style: TfText.body(TfSize.font12).copyWith(color: TfColors.muted)),
        TfDropdown<String?>(
          width: _kRhythmW,
          items: <TfDropdownItem<String?>>[
            TfDropdownItem<String?>(
              value: null,
              label: l.montageAutoPart(snapshot.autoPartId == null ? '—' : name(snapshot.autoPartId!)),
            ),
            for (final String p in parts) TfDropdownItem<String?>(value: p, label: name(p)),
          ],
          value: snapshot.singleRhythmPartId,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
