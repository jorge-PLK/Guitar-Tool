import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/library_detail.dart';
import 'package:toneforge/shell/selected_project.dart';
import 'package:toneforge/shell/shell_providers.dart';
import 'package:toneforge/shell/shell_route.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_sheet.dart';

/// Alerta «Este tema ya está en la biblioteca» (RootView.swift:38-47): «Abrir el existente»
/// (Intro) selecciona el tema [existingId]; «Cancelar» (Esc) no hace nada.
/// Los botones se apilan como el `alert` nativo: en una fila no caben en 320 px.
Future<void> showDuplicateDialog(BuildContext context, WidgetRef ref, String existingId) async {
  final l = AppLocalizations.of(context);
  final nav = Navigator.of(context);
  final open = await showTfSheet<bool>(
    context: context,
    centered: true,
    onCancel: () => nav.pop(false),
    onPrimary: () => nav.pop(true),
    builder: (BuildContext ctx) => TfSheetScaffold(
      width: TfSize.alertWidth,
      title: l.library_duplicateTitle,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TfSpace.s12,
        children: <Widget>[
          Text(l.library_duplicateMessage),
          TfPrimaryButton(label: l.library_duplicateOpen, onPressed: () => nav.pop(true)),
          TfSecondaryButton(label: l.library_importCancel, onPressed: () => nav.pop(false)),
        ],
      ),
    ),
  );
  if (open != true) return;
  // AppModel.open(id): selecciona y abre la página del tema.
  ref.read(shellRouteProvider.notifier).select(ShellRoute.library);
  ref.read(selectedProjectProvider.notifier).select(existingId);
  ref.read(libraryDetailProvider.notifier).open(existingId);
}
