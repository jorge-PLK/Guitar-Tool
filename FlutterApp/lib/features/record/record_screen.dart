import 'package:flutter/widgets.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/shell_route.dart';
import 'package:toneforge/widgets/tf_state_message.dart';

/// Pantalla provisional: la sustituye la ola de su feature sin tocar la carcasa.
class RecordScreen extends StatelessWidget {
  const RecordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TfStateMessage(
        icon: ShellRoute.record.icon,
        text: ShellRoute.record.label(AppLocalizations.of(context)),
      ),
    );
  }
}
