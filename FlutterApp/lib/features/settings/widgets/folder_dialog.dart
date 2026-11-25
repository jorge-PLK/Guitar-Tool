import 'package:flutter/widgets.dart';
import 'package:toneforge/contract/library_storage.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_sheet.dart';

/// Diálogo «Carpeta de proyectos» (SettingsView.swift:91-99): mover, solo apuntar o cancelar.
/// Devuelve el modo elegido o null si se cancela.
Future<RelocateMode?> showFolderDialog(BuildContext context, String path) {
  final l = AppLocalizations.of(context);
  final nav = Navigator.of(context);
  return showTfSheet<RelocateMode?>(
    context: context,
    centered: true,
    onCancel: () => nav.pop(),
    builder: (BuildContext ctx) => TfSheetScaffold(
      width: TfSize.alertWidth,
      title: l.settings_lib_folder,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TfSpace.s12,
        children: <Widget>[
          Text(l.settings_lib_relocateMessage(path)),
          TfPrimaryButton(label: l.settings_lib_moveHere, onPressed: () => nav.pop(RelocateMode.move)),
          TfSecondaryButton(label: l.settings_lib_pointOnly, onPressed: () => nav.pop(RelocateMode.point)),
          TfSecondaryButton(label: l.settings_lib_cancel, onPressed: () => nav.pop()),
        ],
      ),
    ),
  );
}
