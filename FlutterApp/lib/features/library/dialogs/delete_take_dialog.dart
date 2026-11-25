import 'package:flutter/widgets.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/widgets/tf_alert.dart';

/// «¿Eliminar la toma?» (PR:39-45). [label] = «Toma N · {parte}». Devuelve true si se confirma.
Future<bool> confirmDeleteTake(BuildContext context, {required String label}) {
  final l = AppLocalizations.of(context);
  return showTfConfirm(
    context: context,
    title: l.library_takeDeleteTitle,
    confirmLabel: l.library_takeDeleteConfirm(label),
    cancelLabel: l.library_cancel,
    message: l.library_takeDeleteMessage,
    destructive: true,
  );
}
