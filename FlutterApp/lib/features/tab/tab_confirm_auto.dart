import 'package:flutter/widgets.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/widgets/tf_alert.dart';

/// «¿Pasar a transcripción automática?» (TabScreen.swift:103-108). `true` si el usuario confirma.
Future<bool> confirmTabAuto(BuildContext context) {
  final l = AppLocalizations.of(context);
  return showTfConfirm(
    context: context,
    title: l.tab_confirmAutoTitle,
    message: l.tab_confirmAutoBody,
    confirmLabel: l.tab_confirmAutoAction,
    cancelLabel: l.tab_confirmAutoCancel,
    destructive: true,
  );
}
