import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import 'tf_buttons.dart';
import 'tf_sheet.dart';

/// Alerta modal con un solo botón (`.alert` de SwiftUI). Esc e Intro la cierran.
Future<void> showTfAlert({
  required BuildContext context,
  required String title,
  required String okLabel,
  String? message,
}) async {
  final NavigatorState nav = Navigator.of(context);
  await showTfSheet<void>(
    context: context,
    centered: true,
    onCancel: () => nav.pop(),
    onPrimary: () => nav.pop(),
    builder: (BuildContext ctx) => TfSheetScaffold(
      width: TfSize.alertWidth,
      title: title,
      body: message == null ? null : Text(message),
      actions: <Widget>[
        TfPrimaryButton(label: okLabel, onPressed: nav.pop),
      ],
    ),
  );
}

/// Confirmación modal (`confirmationDialog`): `true` si confirma, `false` si cancela o pulsa Esc.
/// Con [destructive] el botón de confirmar es rojo (`danger`). Intro confirma.
Future<bool> showTfConfirm({
  required BuildContext context,
  required String title,
  required String confirmLabel,
  required String cancelLabel,
  String? message,
  bool destructive = false,
}) async {
  final NavigatorState nav = Navigator.of(context);
  final bool? result = await showTfSheet<bool>(
    context: context,
    centered: true,
    onCancel: () => nav.pop(false),
    onPrimary: () => nav.pop(true),
    builder: (BuildContext ctx) => TfSheetScaffold(
      width: TfSize.alertWidth,
      title: title,
      body: message == null ? null : Text(message),
      actions: <Widget>[
        TfSecondaryButton(label: cancelLabel, onPressed: () => nav.pop(false)),
        if (destructive)
          TfDangerButton(label: confirmLabel, onPressed: () => nav.pop(true))
        else
          TfPrimaryButton(label: confirmLabel, onPressed: () => nav.pop(true)),
      ],
    ),
  );
  return result ?? false;
}
