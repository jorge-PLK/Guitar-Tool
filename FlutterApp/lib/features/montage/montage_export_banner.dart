import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:toneforge/contract/montage.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_accent_bar.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_middle_ellipsis.dart';

/// Ancho máximo de la barra de progreso (MV:174).
const double _kBarMaxWidth = 320;

/// Banda de estado de la exportación (MV:167-214): en curso, hecha o fallida.
class MontageExportBanner extends StatelessWidget {
  const MontageExportBanner({super.key, required this.export, required this.onReveal, required this.onDismiss});

  final MontageExportEvent export;
  final VoidCallback onReveal;
  final VoidCallback onDismiss;

  static TextStyle _line(Color c) => TfText.body(TfSize.font12).copyWith(color: c);

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    switch (export.phase) {
      case MontageExportPhase.running:
        return _box(
          TfColors.field,
          Row(
            spacing: TfSpace.s12,
            children: <Widget>[
              Text(
                l.montageExportStage(export.stage ?? ''),
                style: TfText.body(TfSize.font13, TfWeight.medium).copyWith(color: TfColors.text),
              ),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _kBarMaxWidth),
                  child: TfAccentBar(value: export.progress),
                ),
              ),
              Text(
                NumberFormat.percentPattern(Localizations.localeOf(context).toString()).format(export.progress),
                style: TfText.body(TfSize.font13, TfWeight.regular, true).copyWith(color: TfColors.muted),
              ),
            ],
          ),
        );
      case MontageExportPhase.done when export.result != null:
        return _done(context, l, export.result!);
      case MontageExportPhase.failed:
        return _box(
          TfColors.dangerBg,
          Row(
            spacing: TfSpace.s12,
            children: <Widget>[
              Expanded(child: Text(l.montageErrExport(export.message ?? ''), style: _line(TfColors.danger))),
              TfSecondaryButton(label: l.montageClose, height: TfSize.control32, onPressed: onDismiss),
            ],
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _box(Color color, Widget child) => DecoratedBox(
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(TfRadius.control)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: TfSpace.s14, vertical: TfSpace.s10),
          child: child,
        ),
      );

  Widget _done(BuildContext context, AppLocalizations l, MontageExportResultInfo r) {
    final bool windows = defaultTargetPlatform == TargetPlatform.windows;
    final String suffix = !r.normalized
        ? l.montageNotNormalized
        : !r.limiterEnabled
            ? ''
            : r.limiterApplied
                ? l.montageLimiterApplied(r.limiterMaxReductionDB)
                : l.montageLimiterIdle;
    return _box(
      TfColors.okBg,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TfSpace.s6,
        children: <Widget>[
          Row(
            spacing: TfSpace.s12,
            children: <Widget>[
              const TfIconView(TfIcon.checkmarkCircleFill, size: TfSize.font16, color: TfColors.ok, filled: true),
              Expanded(
                child: TfMiddleEllipsisText(
                  l.montageExportDone(r.path),
                  style: TfText.body(TfSize.font13, TfWeight.medium).copyWith(color: TfColors.text),
                ),
              ),
              TfSecondaryButton(
                label: windows ? l.montageRevealExplorer : l.montageRevealFinder,
                height: TfSize.control32,
                onPressed: onReveal,
              ),
              TfSecondaryButton(label: l.montageClose, height: TfSize.control32, onPressed: onDismiss),
            ],
          ),
          if (r.finalLUFS != null)
            Text(l.montageLoudness(r.finalLUFS!, r.finalTruePeakDB, suffix), style: _line(TfColors.muted)),
          if (r.limitedByPeak) Text(l.montageLimiterPeak, style: _line(TfColors.accent)),
          if (r.limiterOutOfTolerance) Text(l.montageLimiterBoth, style: _line(TfColors.accent)),
          if (r.clippedFiles.isNotEmpty)
            Text(r.clippedFiles.map(l.montageClipped).join(' · '), style: _line(TfColors.accent)),
          if (r.tracksDirectory != null) Text(l.montageTracksDir(r.tracksDirectory!), style: _line(TfColors.muted)),
        ],
      ),
    );
  }
}
