import 'package:flutter/widgets.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/widgets/tf_alert.dart';

/// Texto de un error del núcleo: traduce por `code` si hay clave `library_err*` y cae a `message`
/// (o a «Error desconocido» si tampoco hay mensaje).
String coreErrorText(AppLocalizations l, CoreError e) {
  switch (e.code) {
    case 'busy':
      return l.library_errBusy;
    case 'work-in-progress':
      return l.library_errWorkInProgress;
    case 'unsafe-deletion':
      return l.library_errUnsafeDeletion;
    case 'not-found':
      return l.library_errProjectNotFound;
    case 'duplicate':
      return l.library_errDuplicate;
    case 'empty-title':
      return l.library_errTitleEmptyBody;
  }
  return e.message.trim().isEmpty ? l.error_unknown : e.message;
}

/// Aviso modal de un solo botón con el error traducido. [title] específico (p. ej. «No se pudo
/// eliminar del disco»); sin él, el título genérico.
Future<void> showCoreErrorAlert(BuildContext context, CoreError error, {String? title, String? message}) {
  final l = AppLocalizations.of(context);
  return showTfAlert(
    context: context,
    title: title ?? l.library_noticeTitle,
    message: message ?? coreErrorText(l, error),
    okLabel: l.library_noticeOk,
  );
}
