import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/library_detail.dart';
import 'package:toneforge/shell/selected_project.dart';
import 'package:toneforge/widgets/tf_alert.dart';

/// Alerta «Este tema ya está en la biblioteca» (RootView.swift:38-47): «Abrir el existente»
/// (Intro) selecciona el tema [existingId]; «Cancelar» (Esc) no hace nada.
Future<void> showDuplicateDialog(BuildContext context, WidgetRef ref, String existingId) async {
  final l = AppLocalizations.of(context);
  final open = await showTfConfirm(
    context: context,
    title: l.library_duplicateTitle,
    message: l.library_duplicateMessage,
    confirmLabel: l.library_duplicateOpen,
    cancelLabel: l.library_importCancel,
  );
  if (!open) return;
  // AppModel.open(id): selecciona y abre la página del tema.
  ref.read(selectedProjectProvider.notifier).select(existingId);
  ref.read(libraryDetailProvider.notifier).open(existingId);
}
