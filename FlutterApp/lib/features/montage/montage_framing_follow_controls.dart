import 'package:flutter/widgets.dart';

import '../../contract/montage.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import 'montage_framing_controls.dart';
import 'montage_models.dart';

/// Línea de estado del análisis (FS `status`): sin dato o en cola → «en cola».
class FramingStatusLine extends StatelessWidget {
  const FramingStatusLine({super.key, required this.state, required this.takeId});

  final MontageState state;
  final String takeId;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ({int? samples, int? detected, String? error}) d = state.framingDetails(takeId);
    final String text;
    final Color color;
    switch (state.framingStatus(takeId)) {
      case MontageFramingStatus.analyzing:
        text = l.montageFramingStatusAnalyzing(((state.framingProgress(takeId) ?? 0) * 100).round());
        color = TfColors.accent;
      case MontageFramingStatus.ready:
        if ((d.detected ?? 0) == 0) {
          text = l.montageFramingStatusNoDetection;
          color = TfColors.accent;
        } else {
          text = l.montageFramingStatusDetected(d.detected ?? 0, d.samples ?? 0);
          color = TfColors.muted;
        }
      case MontageFramingStatus.failed:
        text = l.montageFramingStatusFailed(d.error ?? '');
        color = TfColors.danger;
      case MontageFramingStatus.pending || MontageFramingStatus.unknown || null:
        text = l.montageFramingStatusQueued;
        color = TfColors.muted;
    }
    return Text(text, style: TfText.body(TfSize.font12).copyWith(color: color));
  }
}

/// Deslizadores del modo «seguir» de la hoja Encuadre: zoom y desplazamiento X/Y (FS) más la ayuda.
class FramingFollowControls extends StatelessWidget {
  const FramingFollowControls({super.key, required this.zoom, required this.offset, required this.onZoom, required this.onOffset});

  final double zoom;
  final MontageOffsetInfo offset;
  final ValueChanged<double> onZoom;
  final ValueChanged<MontageOffsetInfo> onOffset;

  static const double zoomMin = 0.5;
  static const double zoomMax = 3;
  static const double offsetMax = 0.5;

  static String _sign(double v) => '${v < 0 ? '-' : '+'}${v.abs().toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: TfSpace.s12,
      children: <Widget>[
        FramingSliderRow(
          title: l.montageFramingZoomLabel,
          semanticLabel: l.montageFramingZoom(zoom.toStringAsFixed(2)),
          value: zoom,
          min: zoomMin,
          max: zoomMax,
          valueText: '×${zoom.toStringAsFixed(2)}',
          onChanged: onZoom,
        ),
        FramingSliderRow(
          title: l.montageFramingOffsetXLabel,
          semanticLabel: l.montageFramingOffsetX(_sign(offset.x)),
          value: offset.x,
          min: -offsetMax,
          max: offsetMax,
          valueText: _sign(offset.x),
          onChanged: (double v) => onOffset(MontageOffsetInfo(x: v, y: offset.y)),
        ),
        FramingSliderRow(
          title: l.montageFramingOffsetYLabel,
          semanticLabel: l.montageFramingOffsetY(_sign(offset.y)),
          value: offset.y,
          min: -offsetMax,
          max: offsetMax,
          valueText: _sign(offset.y),
          onChanged: (double v) => onOffset(MontageOffsetInfo(x: offset.x, y: v)),
        ),
        Text(l.montageFramingFollowHelp, style: TfText.body(TfSize.font12).copyWith(color: TfColors.muted)),
      ],
    );
  }
}
