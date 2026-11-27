import 'package:flutter/widgets.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/fmt.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_tooltip.dart';

/// Parte elegible en el menú de un corte.
class MontageCutChoice {
  const MontageCutChoice({required this.id, required this.name, required this.eligible});
  final String id;
  final String name;

  /// Sin toma en el instante del corte -> deshabilitada (MV:700-706).
  final bool eligible;
}

/// Contenido del menú del corte (MV:697-714); lo aloja un `TfPopover`.
class MontageCutMenu extends StatelessWidget {
  const MontageCutMenu({
    super.key,
    required this.time,
    required this.selectedPartId,
    required this.choices,
    required this.onSelectPart,
    required this.onDelete,
  });

  final double time;
  final String? selectedPartId;
  final List<MontageCutChoice> choices;
  final ValueChanged<String?> onSelectPart;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = TfFmt.duration(time);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 190),
      child: IntrinsicWidth(
        child: Padding(
          padding: const EdgeInsets.all(TfSpace.s12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: TfSpace.s4,
            children: [
              Text(l10n.montageCutFrom(t), style: TfText.body(TfSize.font12).copyWith(color: TfColors.muted)),
              for (final c in choices)
                Opacity(
                  opacity: c.eligible ? 1 : TfOpacity.disabledSoft,
                  child: TfTooltip(
                    message: c.eligible ? '' : l10n.montageCutNoTake(t),
                    child: _Choice(
                      key: ValueKey('montage-cut-part-${c.id}'),
                      title: c.name,
                      selected: selectedPartId == c.id,
                      onTap: c.eligible ? () => onSelectPart(c.id) : null,
                    ),
                  ),
                ),
              // TODO(l10n): clave «Automático» (montageCutAuto) pendiente en los ARB.
              _Choice(key: const ValueKey('montage-cut-auto'), title: 'Automático', selected: selectedPartId == null, onTap: () => onSelectPart(null)),
              const SizedBox(height: TfStroke.hairline, child: ColoredBox(color: TfColors.line)),
              GestureDetector(
                key: const ValueKey('montage-cut-delete'),
                behavior: HitTestBehavior.opaque,
                onTap: onDelete,
                child: Text(l10n.montageCutDelete, style: TfText.body(TfSize.font13).copyWith(color: TfColors.danger)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({super.key, required this.title, required this.selected, required this.onTap});
  final String title;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(children: [
          SizedBox(
            width: TfSize.font14,
            child: selected ? const TfIconView(TfIcon.checkmark, size: TfSize.font12, color: TfColors.text) : null,
          ),
          const SizedBox(width: TfSpace.s6),
          Text(title, style: TfText.body(TfSize.font13).copyWith(color: TfColors.text)),
        ]),
      );
}
