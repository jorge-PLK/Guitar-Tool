import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/record.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/tokens.dart';
import '../../../theme/typography.dart';
import '../../../widgets/tf_alert.dart';
import '../../../widgets/tf_card.dart';
import '../record_store.dart';
import 'dashed_rrect_painter.dart';
import 'part_box.dart';

/// Panel «Partes» (RV:192-208). El ancho (320) y el scroll los pone el padre.
class PartsPanel extends ConsumerWidget {
  const PartsPanel({super.key, required this.onViewTake, required this.onAddPart, this.onAdjustOffset});

  /// «Ver toma» (botón ▶): el padre abre el visor.
  final ValueChanged<String> onViewTake;

  /// «Añadir parte»: el padre abre la hoja.
  final VoidCallback onAddPart;

  /// «Ajustar desfase…» del menú de toma; sin él la entrada queda inactiva.
  final ValueChanged<String>? onAdjustOffset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RecordState st = ref.watch(recordStoreProvider);
    final RecordSnapshot? snap = st.snapshot;
    final RecordStore store = ref.read(recordStoreProvider.notifier);
    final AppLocalizations l = AppLocalizations.of(context);
    final bool busy = st.isBusy;
    final List<RecordPart> parts = snap?.parts ?? const <RecordPart>[];
    return TfCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: TfSpace.s20, vertical: TfSpace.s18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(l.record_parts, style: TfText.display(18).copyWith(color: TfColors.text, decoration: TextDecoration.none)),
            const SizedBox(height: TfSpace.s12),
            Text(
              l.record_partsHelp,
              style: TfText.body(TfSize.font13).copyWith(color: TfColors.muted, decoration: TextDecoration.none),
            ),
            for (final RecordPart p in parts) ...<Widget>[
              const SizedBox(height: TfSpace.s12),
              PartBox(
                part: p,
                active: p.id == snap?.activePartId,
                // RecordController.status(of:) (RC:211): activa y fase distinta de idle/adjusting.
                recording: st.phase != RecordPhase.idle && st.phase != RecordPhase.adjusting && st.phase != RecordPhase.unknown,
                busy: busy,
                replacesName: _replacesName(p, snap),
                selectedTakeId: snap?.selectedTakeId,
                onSelectPart: () => store.selectPart(p.id),
                onSelectTake: store.selectTake,
                onMarkBest: store.markBest,
                onPunch: store.startPunch,
                onDeleteTake: (String id) => _confirmDelete(context, store, id),
                onViewTake: onViewTake,
                onAdjustOffset: onAdjustOffset,
              ),
            ],
            const SizedBox(height: TfSpace.s12),
            _AddPartButton(label: l.record_addPart, onTap: busy ? null : onAddPart),
          ],
        ),
      ),
    );
  }

  // El DTO de parte no trae «replaces»; solo se sabe `isLead` (ver informe).
  static String? _replacesName(RecordPart p, RecordSnapshot? snap) {
    if (!p.isLead || snap == null) return null;
    for (final RecordGuitarRole r in snap.guitarRoles) {
      if (r.role == 'lead') return r.name;
    }
    return null;
  }

  Future<void> _confirmDelete(BuildContext context, RecordStore store, String takeId) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool ok = await showTfConfirm(
      context: context,
      title: l.record_deleteTitle,
      message: l.record_deleteBody,
      confirmLabel: l.record_deleteConfirm,
      cancelLabel: l.record_cancel,
      destructive: true,
    );
    if (ok) await store.deleteTake(takeId);
  }
}

class _AddPartButton extends StatelessWidget {
  const _AddPartButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      child: Opacity(
        opacity: onTap == null ? TfOpacity.disabled : 1,
        child: MouseRegion(
          cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: CustomPaint(
              painter: const DashedRRectPainter(color: TfColors.muted),
              child: SizedBox(
                height: TfSize.controlLg,
                width: double.infinity,
                child: Center(
                  child: Text(
                    label,
                    style: TfText.body(TfSize.font14, TfWeight.medium).copyWith(color: TfColors.text2, decoration: TextDecoration.none),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
