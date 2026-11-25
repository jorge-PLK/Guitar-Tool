import 'package:flutter/widgets.dart';
import 'package:toneforge/contract/audio.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_buttons.dart';

/// Aviso de frecuencia distinta (AS:164-175). [deviceRate] y [workingRate] son las etiquetas del
/// núcleo («44,1 kHz»); sin ellas cae al texto ya compuesto por el núcleo.
class RateMismatchNotice extends StatelessWidget {
  const RateMismatchNotice({
    super.key,
    required this.mismatch,
    required this.onUseDeviceRate,
    this.deviceRate,
    this.workingRate,
  });

  final AudioRateMismatch mismatch;
  final String? deviceRate;
  final String? workingRate;
  final VoidCallback onUseDeviceRate;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String? d = deviceRate;
    final String? w = workingRate;
    final String message =
        d != null && w != null ? l.settings_audio_rateMismatch(d, w) : mismatch.message;
    final String use =
        d != null ? l.settings_audio_useRate(d) : mismatch.useLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: TfSpace.s8,
      children: <Widget>[
        Text(message, style: TfText.body(13).copyWith(color: TfColors.accent)),
        Text(l.settings_audio_rateMismatchHint,
            style: TfText.body(12).copyWith(color: TfColors.muted)),
        if (mismatch.canUseDeviceRate) TfSecondaryButton(label: use, onPressed: onUseDeviceRate),
      ],
    );
  }
}
