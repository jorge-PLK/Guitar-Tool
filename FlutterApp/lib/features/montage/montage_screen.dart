import 'package:flutter/widgets.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/shell_route.dart';
import 'package:toneforge/widgets/tf_state_message.dart';

/// Pantalla provisional: la sustituye la ola de su feature sin tocar la carcasa.
class MontageScreen extends StatelessWidget {
  const MontageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TfStateMessage(
        icon: ShellRoute.montage.icon,
        text: ShellRoute.montage.label(AppLocalizations.of(context)),
      ),
    );
  }
}
