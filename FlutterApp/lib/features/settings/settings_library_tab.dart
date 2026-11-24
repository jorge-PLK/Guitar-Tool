import 'package:flutter/widgets.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/shell_route.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/widgets/tf_state_message.dart';

/// Pestaña provisional de Ajustes: la sustituye su ola.
class SettingsLibraryTab extends StatelessWidget {
  const SettingsLibraryTab({super.key});

  @override
  Widget build(BuildContext context) {
    return TfStateMessage(
      icon: TfIcon.folder,
      text: SettingsTab.library.label(AppLocalizations.of(context)),
    );
  }
}
