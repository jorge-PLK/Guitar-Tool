import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/study.dart';
import 'package:toneforge/features/backing/widgets/section_boxes_geometry.dart';
import 'package:toneforge/features/backing/widgets/section_menu.dart';
import 'package:toneforge/features/backing/widgets/section_popover.dart';
import 'package:toneforge/features/backing/widgets/section_popover_state.dart';
import 'package:toneforge/features/backing/widgets/section_selection.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/fmt.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_menu.dart';
import 'package:toneforge/widgets/tf_popover.dart';
import 'package:toneforge/widgets/tf_tooltip.dart';

// TOKEN: sectionIconSize 10 (SB:76)
const double sectionBoxIconSize = 10;
// TOKEN: loopSameTime 0.01 s (SectionEditor.sameTime, ficha §6.3)
const double sectionBoxSameTime = 0.01;

/// Cabecera de la caja de sección (SB:251-332): clic abre la hoja y la selección,
/// pulsación larga alterna el bucle y el menú contextual lista las acciones.
class SectionBoxHeader extends ConsumerWidget {
  const SectionBoxHeader({
    required this.placement,
    required this.icon,
    required this.nameStyle,
    required this.name,
    required this.popover,
    super.key,
  });

  final SectionPlacement placement;
  final Widget icon;
  final TextStyle nameStyle;
  final Widget name;
  final TfPopoverController popover;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final StudySectionInfo s = placement.section;
    final AppLocalizations l = AppLocalizations.of(context);
    final String from = TfFmt.clock(s.start);
    final String to = TfFmt.clock(s.end);
    void open() {
      ref.read(sectionSelectionProvider.notifier).select(s.id);
      ref.read(sectionPopoverProvider.notifier).open(s.id);
    }

    final Widget box = TfTooltip(
      message: l.backing_sectionBoxTooltip(
        s.name,
        s.solo ? 'yes' : 'no',
        from,
        to,
      ),
      child: Semantics(
        label: l.backing_sectionA11y(
          s.solo ? 'solo' : 'section',
          s.name,
          from,
          to,
        ),
        hint: l.backing_sectionA11yHint,
        button: true,
        excludeSemantics: true,
        onTap: open,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: open,
            onLongPress: () =>
                toggleSectionLoop(ref, s, sameTime: sectionBoxSameTime),
            child: !placement.labeled
                ? const SizedBox.expand()
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: TfSpace.s8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      // Como `ViewThatFits`: nombre con icono, solo el icono (si es solo) o nada.
                      child: LayoutBuilder(
                        builder: (BuildContext context, BoxConstraints c) {
                          final double text = (TextPainter(
                            text: TextSpan(text: s.name, style: nameStyle),
                            maxLines: 1,
                            textDirection: TextDirection.ltr,
                          )..layout()).width;
                          final double full =
                              text + (s.solo ? sectionBoxIconSize + TfSpace.s4 : 0);
                          if (full <= c.maxWidth) {
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              spacing: TfSpace.s4,
                              children: <Widget>[if (s.solo) icon, name],
                            );
                          }
                          return s.solo && sectionBoxIconSize <= c.maxWidth
                              ? icon
                              : const SizedBox.shrink();
                        },
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
    final Widget anchored = placement.labeled
        ? TfPopover(
            controller: popover,
            onClosed: ref.read(sectionPopoverProvider.notifier).close,
            popoverBuilder: (BuildContext _) => SectionPopover(sectionId: s.id),
            child: box,
          )
        : box;
    return TfContextMenu(
      entries: sectionMenuEntries(ref, s, AppLocalizations.of(context)),
      child: anchored,
    );
  }
}
