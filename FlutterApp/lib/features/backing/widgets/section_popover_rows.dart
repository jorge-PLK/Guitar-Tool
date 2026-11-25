import 'package:flutter/widgets.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_buttons.dart';

/// Ancho de la hoja (SectionBoxes.swift:305-367), desde el token del tema.
const double sectionPopoverWidth = TfSize.sectionPopoverWidth;
const double sectionLabelWidth = TfSize.sectionPopoverLabelWidth;
const double _swatchRingGap = 3;
const double _swatchRowHeight = 24;
const int _suggestionColumns = 3;

/// `SectionPopover.precise` (SectionBoxes.swift:393): `m:ss.d`, nunca negativo.
String sectionPreciseTime(double s) {
  final double t = s > 0 ? s : 0;
  final int minutes = t ~/ 60;
  final String secs = (t - minutes * 60).toStringAsFixed(1).padLeft(4, '0');
  return '$minutes:$secs';
}

/// Rejilla de 3 columnas con las cinco sugerencias de nombre.
class SectionSuggestions extends StatelessWidget {
  const SectionSuggestions({required this.draft, required this.onPick, super.key});

  final String draft;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final List<String> names = <String>[
      l.backing_sectionSuggestIntro,
      l.backing_sectionSuggestVerse,
      l.backing_sectionSuggestChorus,
      l.backing_sectionSuggestBridge,
      l.backing_sectionSuggestEnd,
    ];
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < names.length; i += _suggestionColumns) {
      if (i > 0) rows.add(const SizedBox(height: TfSpace.s6));
      rows.add(Row(children: <Widget>[
        for (int c = 0; c < _suggestionColumns; c++) ...<Widget>[
          if (c > 0) const SizedBox(width: TfSpace.s6),
          Expanded(
            child: i + c < names.length
                ? _SuggestionChip(name: names[i + c], active: draft == names[i + c], onTap: onPick)
                : const SizedBox.shrink(),
          ),
        ],
      ]));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.name, required this.active, required this.onTap});

  final String name;
  final bool active;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: name,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(name),
        child: Container(
          key: ValueKey<String>('section-suggest-$name'),
          height: TfSize.sectionSuggestionHeight,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? TfColors.line : TfColors.field,
            borderRadius: BorderRadius.circular(TfRadius.small),
          ),
          child: Text(
            name,
            style: TfText.body(TfSize.font12, TfWeight.medium)
                .copyWith(color: active ? TfColors.text : TfColors.muted),
          ),
        ),
      ),
    );
  }
}

/// Fila «Color»: 7 círculos de paleta (el elegido con aro) o, en un solo, el círculo naranja y su nota.
class SectionSwatches extends StatelessWidget {
  const SectionSwatches({
    required this.solo,
    required this.current,
    required this.onPick,
    super.key,
  });

  final bool solo;

  /// Índice de paleta efectivo (`paletteIndex`).
  final int? current;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return SizedBox(
      height: _swatchRowHeight,
      child: Row(children: <Widget>[
        SizedBox(
          width: sectionLabelWidth,
          child: Text(l.backing_sectionColor, style: TfText.body(TfSize.font13).copyWith(color: TfColors.text2)),
        ),
        if (solo) ...<Widget>[
          const _Dot(color: TfColors.accent),
          const SizedBox(width: TfSpace.s8),
          Flexible(
            child: Text(
              l.backing_sectionSoloOrange,
              style: TfText.body(TfSize.font12).copyWith(color: TfColors.muted),
            ),
          ),
        ] else
          for (int i = 0; i < TfColors.sectionPalette.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: TfSpace.s8),
            Semantics(
              button: true,
              selected: current == i,
              label: l.backing_sectionColorN(i + 1),
              excludeSemantics: true,
              child: GestureDetector(
                key: ValueKey<String>('section-swatch-$i'),
                behavior: HitTestBehavior.opaque,
                onTap: () => onPick(i),
                child: _Dot(color: TfColors.sectionPalette[i], ring: current == i),
              ),
            ),
          ],
      ]),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, this.ring = false});

  final Color color;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: TfSize.sectionColorDot,
      height: TfSize.sectionColorDot,
      child: OverflowBox(
        maxWidth: TfSize.sectionColorDot + 2 * _swatchRingGap + 2 * TfStroke.thick,
        maxHeight: TfSize.sectionColorDot + 2 * _swatchRingGap + 2 * TfStroke.thick,
        child: Container(
          width: TfSize.sectionColorDot + 2 * _swatchRingGap + 2 * TfStroke.thick,
          height: TfSize.sectionColorDot + 2 * _swatchRingGap + 2 * TfStroke.thick,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: ring ? Border.all(color: TfColors.text, width: TfStroke.thick) : null,
          ),
          child: Container(
            width: TfSize.sectionColorDot,
            height: TfSize.sectionColorDot,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}

/// Fila «Inicio» / «Fin»: ◀ tiempo ▶.
class SectionEdgeRow extends StatelessWidget {
  const SectionEdgeRow({
    required this.title,
    required this.isStart,
    required this.time,
    required this.onNudge,
    super.key,
  });

  final String title;
  final bool isStart;
  final double time;

  /// `forward` = ▶.
  final ValueChanged<bool> onNudge;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String edge = isStart ? 'start' : 'end';
    return Row(children: <Widget>[
      SizedBox(
        width: sectionLabelWidth,
        child: Text(title, style: TfText.body(TfSize.font13).copyWith(color: TfColors.text2)),
      ),
      TfIconButton(
        key: ValueKey<String>('section-$edge-back'),
        icon: TfIcon.chevronLeft,
        kind: TfIconButtonKind.nudge,
        semanticLabel: l.backing_sectionNudgeA11y(edge, 'before'),
        onPressed: () => onNudge(false),
      ),
      const SizedBox(width: TfSpace.s8),
      ConstrainedBox(
        constraints: const BoxConstraints(minWidth: TfSize.sectionTimeMinWidth),
        child: Text(
          sectionPreciseTime(time),
          key: ValueKey<String>('section-$edge-time'),
          textAlign: TextAlign.center,
          style: TfText.body(TfSize.font14, TfWeight.semibold)
              .copyWith(color: TfColors.text, fontFeatures: const <FontFeature>[FontFeature.tabularFigures()]),
        ),
      ),
      const SizedBox(width: TfSpace.s8),
      TfIconButton(
        key: ValueKey<String>('section-$edge-forward'),
        icon: TfIcon.chevronRight,
        kind: TfIconButtonKind.nudge,
        semanticLabel: l.backing_sectionNudgeA11y(edge, 'after'),
        onPressed: () => onNudge(true),
      ),
    ]);
  }
}
