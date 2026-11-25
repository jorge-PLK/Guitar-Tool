import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/study.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/features/backing/widgets/chords_expanded.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_pill.dart';
import 'package:toneforge/widgets/tf_tooltip.dart';

/// Cabecera de acordes (BT:64-117). Lee el store; [onSectionMarked] recibe el id de la sección nueva
/// (la TimelineCard la selecciona para abrir su hoja).
class ChordsHeader extends ConsumerWidget {
  const ChordsHeader({super.key, this.onSectionMarked});

  final void Function(String? id)? onSectionMarked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final StudyStore store = ref.read(studyStoreProvider.notifier);
    final StudyOpenResult? study = ref.watch(studyStoreProvider.select((s) => s.study));
    final bool edit = ref.watch(studyStoreProvider.select((s) => s.editMode));
    final bool expanded = ref.watch(chordsExpandedProvider);
    final int overrides = study?.chordOverrides.length ?? 0;
    final StudyLoop? loop = study?.transport.loop;
    final bool hasChords = study?.analysis.chords.isNotEmpty ?? false;
    final bool unapplied = study?.unappliedSections ?? false;
    final bool mac = defaultTargetPlatform == TargetPlatform.macOS;

    Widget mark(String label, String tip, TfIcon icon, bool solo) => TfTooltip(
          message: tip,
          child: TfCompactPill(
            label: label,
            active: solo,
            iconBuilder: (Color c) => TfIconView(icon, size: TfSize.font12, color: c),
            onPressed: () async => onSectionMarked?.call(await store.markSection(loop!.start, loop.end, solo: solo)),
          ),
        );

    return Row(
      spacing: TfSpace.s12,
      children: <Widget>[
        Text(l.backing_chords, style: TfText.display(16).copyWith(color: TfColors.text)),
        _HeaderButton(
          label: l.backing_editChords,
          icon: edit ? TfIcon.pencilCircleFill : TfIcon.pencil,
          active: edit,
          onTap: () => store.setEditMode(!edit),
        ),
        if (edit && overrides > 0)
          TfTooltip(
            message: l.backing_clearOverridesTooltip,
            child: _HeaderButton(
              label: l.backing_clearOverrides(overrides),
              onTap: store.clearChordOverrides,
            ),
          ),
        Expanded(
          child: Text(
            edit ? l.backing_editModeHint : (mac ? l.backing_dragHintMac : l.backing_dragHintWin),
            style: TfText.body(TfSize.font12).copyWith(color: edit ? TfColors.accent : TfColors.muted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (!edit && loop != null && hasChords) ...<Widget>[
          mark(l.backing_markSection, l.backing_markSectionTooltip, TfIcon.rectangleDashed, false),
          mark(l.backing_markSolo, l.backing_markSoloTooltip, TfIcon.guitarsFill, true),
        ],
        if (unapplied) ...<Widget>[
          TfTooltip(
            message: l.backing_discardTooltip,
            child: TfSecondaryButton(
              label: l.backing_discard,
              height: TfSize.controlSm,
              onPressed: store.discardSections,
            ),
          ),
          TfTooltip(
            message: l.backing_applyTooltip,
            child: TfPrimaryButton.apply(label: l.backing_apply, onPressed: store.applySections),
          ),
        ],
        _HeaderButton(
          label: expanded ? l.backing_collapse : l.backing_expand,
          semanticLabel: expanded ? l.backing_collapseA11y : l.backing_expandA11y,
          icon: expanded ? TfIcon.chevronUp : TfIcon.chevronDown,
          iconAfter: true,
          onTap: () => ref.read(chordsExpandedProvider.notifier).toggle(),
        ),
      ],
    );
  }
}

/// Botón de cabecera (alto 28, h 10, radio 8, body 12). Activo: `accentInk` sobre `accent`, sin borde.
class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.label,
    required this.onTap,
    this.icon,
    this.iconAfter = false,
    this.active = false,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback onTap;
  final TfIcon? icon;
  final bool iconAfter;
  final bool active;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final Color fg = active ? TfColors.accentInk : TfColors.text2;
    final Widget text = Text(
      label,
      style: TfText.body(TfSize.font12, active ? TfWeight.semibold : TfWeight.medium).copyWith(color: fg),
      maxLines: 1,
      softWrap: false,
    );
    final Widget? glyph = icon == null ? null : TfIconView(icon!, size: TfSize.font12, color: fg);
    return Semantics(
      button: true,
      selected: active,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            height: TfSize.controlSm,
            padding: const EdgeInsets.symmetric(horizontal: TfSpace.s10),
            decoration: BoxDecoration(
              color: active ? TfColors.accent : TfColors.field,
              borderRadius: BorderRadius.circular(TfRadius.field),
              border: active ? null : Border.all(color: TfColors.fieldLine, width: TfStroke.hairline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: TfSpace.s6,
              children: <Widget>[if (!iconAfter) ?glyph, text, if (iconAfter) ?glyph],
            ),
          ),
        ),
      ),
    );
  }
}
