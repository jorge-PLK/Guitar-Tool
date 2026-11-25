import 'package:flutter/widgets.dart';
import 'package:toneforge/contract/audio.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';

import 'audio_texts.dart';

/// Estado de la latencia (AS:223-227): calibrada en `ok`, sin calibrar en `accent`.
class LatencyStatus extends StatelessWidget {
  const LatencyStatus({super.key, required this.calibration});

  final AudioCalibrationSummary calibration;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool ok = calibration.calibrated;
    return Text(
      ok ? calibratedText(l, calibration) : l.settings_audio_uncalibrated,
      style: TfText.body(TfSize.font14, TfWeight.semibold).copyWith(color: ok ? TfColors.ok : TfColors.accent),
    );
  }
}
