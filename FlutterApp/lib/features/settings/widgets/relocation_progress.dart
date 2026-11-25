import 'package:flutter/widgets.dart';
import 'package:toneforge/features/settings/settings_metrics.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/fmt.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_progress.dart';

/// Barra y «Moviendo N %» del traslado de carpeta (SettingsView.swift:121-126).
class RelocationProgress extends StatelessWidget {
  const RelocationProgress({super.key, required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Row(
      spacing: SettingsMetrics.progressGap,
      children: <Widget>[
        Expanded(child: TfProgress(value: fraction)),
        Text(
          l.settings_lib_moving(TfFmt.percent(fraction)),
          style: TfText.body(13).copyWith(color: TfColors.muted),
        ),
      ],
    );
  }
}
