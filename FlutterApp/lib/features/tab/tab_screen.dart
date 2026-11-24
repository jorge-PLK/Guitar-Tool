import 'package:flutter/widgets.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/shell_route.dart';
import 'package:toneforge/widgets/tf_state_message.dart';

/// Pantalla provisional: la sustituye la ola de su feature sin tocar la carcasa.
class TabScreen extends StatelessWidget {
  const TabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TfStateMessage(
        icon: ShellRoute.tab.icon,
        text: ShellRoute.tab.label(AppLocalizations.of(context)),
      ),
    );
  }
}
