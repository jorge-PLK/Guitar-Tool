import 'package:flutter/widgets.dart';
import 'package:toneforge/contract/record.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/icons.dart';
import '../../../theme/tokens.dart';
import '../../../theme/typography.dart';
import '../../../widgets/tf_menu.dart';

/// Toma en el panel «Partes» (RV:257-292): botón-menú «Toma N» + botón ▶ 32×32.
/// Clic en la etiqueta = elegir la toma; el chevron abre el menú. Todo inerte con [busy].
class TakeButton extends StatelessWidget {
  const TakeButton({
    super.key,
    required this.take,
    required this.best,
    required this.selected,
    required this.busy,
    required this.onSelect,
    required this.onMarkBest,
    required this.onPunch,
    required this.onDelete,
    required this.onView,
    this.onAdjustOffset,
  });

  final RecordTake take;
  final bool best;
  final bool selected;
  final bool busy;
  final VoidCallback onSelect;
  final VoidCallback onMarkBest;
  final VoidCallback onPunch;
  final VoidCallback onDelete;
  final VoidCallback onView;

  /// Abre «Ajustar desfase» (otra hoja); sin callback la entrada queda inactiva.
  final VoidCallback? onAdjustOffset;

  bool get _canView => !busy && take.audioPath != null && take.songStart != null;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String label = best ? l.record_takeBest(take.number) : l.record_take(take.number);
    final Color fill = selected ? TfColors.accentBg : (best ? TfColors.okBg : TfColors.sidebar);
    final Color line = selected ? TfColors.accent : (best ? TfColors.okBorder : TfColors.fieldLine);
    final Color ink = best ? TfColors.ok : TfColors.text2;
    final List<TfMenuEntry> entries = <TfMenuEntry>[
      TfMenuItem(label: l.record_menuBest, enabled: !best, onSelected: onMarkBest),
      TfMenuItem(label: l.record_menuOffset, enabled: take.hasVideo && onAdjustOffset != null, onSelected: onAdjustOffset ?? () {}),
      TfMenuItem(label: l.record_menuPunch, onSelected: onPunch),
      const TfMenuDivider(),
      TfMenuItem(label: l.record_menuDelete, destructive: true, onSelected: onDelete),
    ];
    return Opacity(
      opacity: take.discarded ? TfOpacity.dim : 1,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TfMenu(
            entries: entries,
            builder: (BuildContext context, VoidCallback toggle) => Semantics(
              button: true,
              selected: selected,
              enabled: !busy,
              label: best ? l.record_takeA11yBest(take.number) : l.record_takeA11y(take.number),
              child: Opacity(
                opacity: busy ? TfOpacity.disabled : 1,
                child: Container(
                  height: TfSpace.s32,
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: BorderRadius.circular(TfRadius.field),
                    border: Border.all(color: line, width: selected ? TfStroke.thick : TfStroke.hairline),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _Tap(
                        onTap: busy ? null : onSelect,
                        child: Padding(
                          padding: const EdgeInsets.only(left: TfSpace.s10, right: TfSpace.s6),
                          child: Center(
                            child: Text(
                              label,
                              maxLines: 1,
                              softWrap: false,
                              style: TfText.body(TfSize.font12, TfWeight.semibold).copyWith(color: ink, decoration: TextDecoration.none),
                            ),
                          ),
                        ),
                      ),
                      _Tap(
                        onTap: busy ? null : toggle,
                        child: Padding(
                          padding: const EdgeInsets.only(right: TfSpace.s8),
                          child: Center(child: TfIconView(TfIcon.chevronDown, size: TfSize.font11, color: ink)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: TfSpace.s4),
          Opacity(
            opacity: _canView ? 1 : TfOpacity.disabled,
            child: Container(
              width: TfSpace.s32,
              height: TfSpace.s32,
              decoration: BoxDecoration(
                color: TfColors.sidebar,
                borderRadius: BorderRadius.circular(TfRadius.field),
                border: Border.all(color: TfColors.fieldLine),
              ),
              child: _Tap(
                onTap: _canView ? onView : null,
                semanticLabel: l.record_viewTakeA11y(take.number),
                child: const Center(child: TfIconView(TfIcon.playFill, size: TfSize.font11, color: TfColors.text2)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tap extends StatelessWidget {
  const _Tap({required this.onTap, required this.child, this.semanticLabel});

  final VoidCallback? onTap;
  final Widget child;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    Widget w = GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: child);
    w = MouseRegion(cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click, child: w);
    if (semanticLabel != null) {
      w = Semantics(button: true, enabled: onTap != null, label: semanticLabel, child: w);
    }
    return w;
  }
}
