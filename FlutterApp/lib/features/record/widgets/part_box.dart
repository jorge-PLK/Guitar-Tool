import 'package:flutter/widgets.dart';
import 'package:toneforge/contract/record.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/tokens.dart';
import '../../../theme/typography.dart';
import 'take_button.dart';

enum PartChipKind { done, recording, pending }

/// Chip de estado de la parte (RV:233-241): 11 pt, padding 9/3 (más pequeño que `TfChip`).
class PartStatusChip extends StatelessWidget {
  const PartStatusChip(this.kind, {super.key});

  final PartChipKind kind;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final (String text, Color fg, Color bg) = switch (kind) {
      PartChipKind.done => (l.record_statusDone, TfColors.ok, TfColors.okBg),
      PartChipKind.recording => (l.record_statusRecording, TfColors.danger, TfColors.dangerBg),
      PartChipKind.pending => (l.record_statusPending, TfColors.text2, TfColors.neutralBg),
    };
    return DecoratedBox(
      decoration: ShapeDecoration(color: bg, shape: const StadiumBorder()),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: TfSpace.s8 + TfSpace.s1, vertical: TfSpace.s3),
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          style: TfText.body(TfSize.font11, TfWeight.semibold).copyWith(color: fg, decoration: TextDecoration.none),
        ),
      ),
    );
  }
}

/// Caja de una parte (RV:210-231). Clic en toda la caja = elegir parte.
class PartBox extends StatelessWidget {
  const PartBox({
    super.key,
    required this.part,
    required this.active,
    required this.recording,
    required this.busy,
    required this.replacesName,
    required this.selectedTakeId,
    required this.onSelectPart,
    required this.onSelectTake,
    required this.onMarkBest,
    required this.onPunch,
    required this.onDeleteTake,
    required this.onViewTake,
    this.onAdjustOffset,
  });

  final RecordPart part;
  final bool active;

  /// `phase == recording`: solo la parte activa muestra «Grabando».
  final bool recording;
  final bool busy;

  /// Nombre de la guitarra que sustituye; nulo = «Parte añadida».
  final String? replacesName;
  final String? selectedTakeId;
  final VoidCallback onSelectPart;
  final ValueChanged<String> onSelectTake;
  final ValueChanged<String> onMarkBest;
  final ValueChanged<String> onPunch;
  final ValueChanged<String> onDeleteTake;
  final ValueChanged<String> onViewTake;
  final ValueChanged<String>? onAdjustOffset;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    // RecordController.status(of:): el núcleo emite `recording` para la parte activa en curso.
    final PartChipKind chip = part.status == PartStatus.recording || (active && recording)
        ? PartChipKind.recording
        : (part.status == PartStatus.done ? PartChipKind.done : PartChipKind.pending);
    return Semantics(
      container: true,
      selected: active,
      label: part.name,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: busy || active ? null : onSelectPart,
        child: MouseRegion(
          cursor: busy || active ? MouseCursor.defer : SystemMouseCursors.click,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: TfSpace.s14, vertical: TfSpace.s12),
            decoration: BoxDecoration(
              color: active ? TfColors.accentBg : TfColors.field,
              borderRadius: BorderRadius.circular(TfRadius.tile),
              border: Border.all(color: active ? TfColors.accent : TfColors.fieldLine),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        part.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TfText.body(TfSize.font14, TfWeight.semibold).copyWith(color: TfColors.text, decoration: TextDecoration.none),
                      ),
                    ),
                    PartStatusChip(chip),
                  ],
                ),
                const SizedBox(height: TfSpace.s8),
                Text(
                  replacesName == null ? l.record_partAdded : l.record_partReplaces(replacesName!),
                  style: TfText.body(TfSize.font12).copyWith(color: TfColors.muted, decoration: TextDecoration.none),
                ),
                if (part.takes.isNotEmpty) ...<Widget>[
                  const SizedBox(height: TfSpace.s8),
                  Wrap(
                    spacing: TfSpace.s6,
                    runSpacing: TfSpace.s6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      for (final RecordTake t in part.takes)
                        TakeButton(
                          take: t,
                          best: part.bestTakeId == t.id,
                          selected: selectedTakeId == t.id,
                          busy: busy,
                          onSelect: () => onSelectTake(t.id),
                          onMarkBest: () => onMarkBest(t.id),
                          onPunch: () => onPunch(t.id),
                          onDelete: () => onDeleteTake(t.id),
                          onView: () => onViewTake(t.id),
                          onAdjustOffset: onAdjustOffset == null ? null : () => onAdjustOffset!(t.id),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
