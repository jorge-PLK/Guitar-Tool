import 'package:flutter/widgets.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/fmt.dart';
import '../../../theme/tokens.dart';
import '../../../theme/typography.dart';

/// «m:ss / m:ss» (RV:491-494). `position` llega del store (`record.position`, 30 Hz), que ya
/// supera el refresco de 0,05 s de SwiftUI: no hace falta `Ticker` local.
class TimeReadout extends StatelessWidget {
  const TimeReadout({super.key, required this.position, required this.total, this.autoStop = false});

  final double position;
  final double total;

  /// Para sola (hay `plannedStop`): ayuda distinta a «Duración del tema».
  final bool autoStop;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    const List<FontFeature> mono = <FontFeature>[FontFeature.tabularFigures()];
    return Semantics(
      tooltip: autoStop ? l.record_durationHelpAuto : l.record_durationHelpTheme,
      child: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(
              text: TfFmt.duration(position < 0 ? 0 : position),
              style: TfText.display(20).copyWith(color: TfColors.text, fontFeatures: mono),
            ),
            TextSpan(
              text: ' / ${TfFmt.duration(total)}',
              style: TfText.body(16, TfWeight.medium).copyWith(color: TfColors.muted, fontFeatures: mono),
            ),
          ],
        ),
        maxLines: 1,
      ),
    );
  }
}
