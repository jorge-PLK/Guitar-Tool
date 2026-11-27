import 'package:flutter/widgets.dart';
import 'package:toneforge/contract/montage.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_progress.dart';
import 'package:toneforge/widgets/tf_tooltip.dart';

import 'widgets/montage_timeline_painter.dart';

const double _lane = MontageTimelineGeometry.laneHeight;

/// Columna de etiquetas (270) de la tarjeta (MV:542-554, 728-782). Sin lógica: callbacks.
class MontageTimelineLabels extends StatefulWidget {
  const MontageTimelineLabels({
    super.key,
    required this.snapshot,
    required this.analyzing,
    required this.onOpenFraming,
    required this.onRotate,
    required this.onMoveLane,
    required this.onAddCut,
  });

  final MontageSnapshot snapshot;

  /// Tomas con análisis de encuadre en curso.
  final Set<String> analyzing;
  final ValueChanged<String> onOpenFraming;
  final ValueChanged<String> onRotate;
  final void Function(String id, String to) onMoveLane;
  final VoidCallback onAddCut;

  @override
  State<MontageTimelineLabels> createState() => _LabelsState();
}

class _LabelsState extends State<MontageTimelineLabels> {
  String? _dragging;
  String? _over;

  bool _above(String id) {
    final ids = [for (final l in widget.snapshot.lanes) l.id];
    final from = _dragging == null ? -1 : ids.indexOf(_dragging!), to = ids.indexOf(id);
    return from < 0 || to < 0 || from > to;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = widget.snapshot;
    final small = TfText.body(TfSize.font11).copyWith(color: TfColors.muted);
    final name = TfText.body(TfSize.font13, TfWeight.semibold).copyWith(color: TfColors.text2);
    return SizedBox(
      width: MontageTimelineGeometry.labelWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: MontageTimelineGeometry.rowSpacing,
        children: [
          SizedBox(
            height: MontageTimelineGeometry.bandHeight,
            child: OverflowBox(
              maxHeight: double.infinity,
              alignment: Alignment.centerLeft,
              child: Text(l10n.montageBand, style: TfText.body(TfSize.font10).copyWith(color: TfColors.muted)),
            ),
          ),
          const SizedBox(height: MontageTimelineGeometry.sectionHeight),
          if (s.isSingleShot)
            SizedBox(
              height: _lane,
              child: Row(spacing: TfSpace.s6, children: [
                Text(l10n.montagePlane, style: name),
                const Spacer(),
                TfTooltip(
                  message: l10n.montageAddCutHelp,
                  child: _PillButton(
                    key: const ValueKey('montage-add-cut'),
                    onTap: widget.onAddCut,
                    child: Text(l10n.montageAddCut, style: TfText.body(TfSize.font12, TfWeight.medium).copyWith(color: TfColors.text)),
                  ),
                ),
              ]),
            ),
          for (final lane in s.lanes) _laneRow(context, lane, name, small),
          for (final part in s.missingParts)
            SizedBox(
              height: _lane,
              child: Row(children: [
                Flexible(child: Text(part, style: name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                const Spacer(),
                Text(l10n.montageNoTake, style: small),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _laneRow(BuildContext context, MontageLaneInfo lane, TextStyle name, TextStyle small) {
    final l10n = AppLocalizations.of(context);
    final row = SizedBox(
      height: _lane,
      child: Row(spacing: TfSpace.s6, children: [
        TfTooltip(
          message: l10n.montageLaneDragHelp,
          child: const TfIconView(TfIcon.line3Horizontal, size: TfSize.font12, color: TfColors.muted),
        ),
        Flexible(child: Text(lane.partName, style: name, maxLines: 1, overflow: TextOverflow.ellipsis)),
        const Spacer(),
        if (lane.presence.isEmpty)
          Text(l10n.montageLaneNoSolos, style: small)
        else if (lane.hasVideo) ...[
          if (widget.analyzing.contains(lane.takeId)) const TfSpinner.mini(),
          _PillButton(
            key: ValueKey('montage-framing-${lane.takeId}'),
            onTap: () => widget.onOpenFraming(lane.takeId),
            child: Text(l10n.montageLaneFraming, style: TfText.body(TfSize.font12, TfWeight.medium).copyWith(color: TfColors.text)),
          ),
          TfTooltip(
            message: l10n.record_rotateDegrees(lane.rotation),
            child: _PillButton(
              key: ValueKey('montage-rotate-${lane.takeId}'),
              onTap: () => widget.onRotate(lane.takeId),
              square: true,
              child: TfIconView(TfIcon.rotateRight, size: TfSize.font12, color: lane.rotation == 0 ? TfColors.text : TfColors.accent),
            ),
          ),
        ] else
          Text(l10n.montageLaneAudioOnly, style: small),
      ]),
    );
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) {
        setState(() => _over = lane.id);
        return d.data != lane.id;
      },
      onLeave: (_) => setState(() => _over = null),
      onAcceptWithDetails: (d) {
        setState(() => _over = null);
        widget.onMoveLane(d.data, lane.id);
      },
      builder: (context, _, _) => Draggable<String>(
        key: ValueKey('montage-lane-${lane.id}'),
        data: lane.id,
        maxSimultaneousDrags: 1,
        onDragStarted: () => setState(() => _dragging = lane.id),
        onDragEnd: (_) => setState(() => _dragging = null),
        feedback: SizedBox(width: MontageTimelineGeometry.labelWidth, child: DefaultTextStyle(style: name, child: Opacity(opacity: TfOpacity.disabled, child: row))),
        childWhenDragging: Opacity(opacity: TfOpacity.disabledSoft, child: row),
        child: Stack(clipBehavior: Clip.none, children: [
          row,
          if (_over == lane.id && _dragging != lane.id)
            Positioned(
              left: 0,
              right: 0,
              top: _above(lane.id) ? -MontageTimelineGeometry.rowSpacing / 2 : null,
              bottom: _above(lane.id) ? null : -MontageTimelineGeometry.rowSpacing / 2,
              child: const SizedBox(height: TfSpace.s3, child: ColoredBox(color: TfColors.accent)),
            ),
        ]),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({super.key, required this.onTap, required this.child, this.square = false});
  final VoidCallback onTap;
  final Widget child;
  final bool square;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: _lane - TfSpace.s4,
          width: square ? _lane - TfSpace.s4 : null,
          padding: square ? null : const EdgeInsets.symmetric(horizontal: TfSpace.s10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: TfColors.field,
            borderRadius: BorderRadius.circular(TfRadius.field),
            border: Border.all(color: TfColors.fieldLine, width: TfStroke.hairline),
          ),
          child: child,
        ),
      );
}
