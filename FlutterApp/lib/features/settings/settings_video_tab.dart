import 'package:flutter/widgets.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/shell_route.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/widgets/tf_state_message.dart';

/// Pestaña provisional de Ajustes: la sustituye su ola.
class SettingsVideoTab extends StatelessWidget {
  const SettingsVideoTab({super.key});

  @override
  Widget build(BuildContext context) {
    return TfStateMessage(
      icon: TfIcon.video,
      text: SettingsTab.video.label(AppLocalizations.of(context)),
    );
  }
}
