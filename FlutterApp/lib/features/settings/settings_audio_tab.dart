import 'package:flutter/widgets.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/shell_route.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/widgets/tf_state_message.dart';

/// Pestaña provisional de Ajustes: la sustituye su ola.
class SettingsAudioTab extends StatelessWidget {
  const SettingsAudioTab({super.key});

  @override
  Widget build(BuildContext context) {
    return TfStateMessage(
      icon: TfIcon.waveform,
      text: SettingsTab.audio.label(AppLocalizations.of(context)),
    );
  }
}
