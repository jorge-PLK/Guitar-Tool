import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/fmt.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_sheet.dart';

import '../library_errors.dart';
import '../library_store.dart';

/// Diálogo «Limpiar» (LV:33-40): enseña los bytes que se liberan y, si se confirma, limpia.
/// Sin [projectId] limpia toda la biblioteca (título global).
Future<void> showCleanDialog(
  BuildContext context,
  WidgetRef ref, {
  String? projectId,
  String? title,
}) async {
  final l = AppLocalizations.of(context);
  final locale = Localizations.localeOf(context).languageCode;
  final store = ref.read(libraryStoreProvider.notifier);
  final int bytes;
  try {
    bytes = await store.cleanupInfo(id: projectId);
  } on CoreError catch (e) {
    if (context.mounted) await showCoreErrorAlert(context, e);
    return;
  }
  if (!context.mounted) return;
  final size = TfFmt.bytes(bytes, locale);
  final nav = Navigator.of(context);
  // Botones apilados (320 de ancho no da para dos con «Limpiar {bytes}»), como el diálogo nativo.
  final ok = await showTfSheet<bool>(
    context: context,
    centered: true,
    onCancel: () => nav.pop(false),
    builder: (BuildContext ctx) => TfSheetScaffold(
      width: TfSize.alertWidth,
      title: projectId == null ? l.library_cleanTitleAll : l.library_cleanTitle(title ?? ''),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TfSpace.s12,
        children: <Widget>[
          Text(l.library_cleanMessage(size)),
          TfDangerButton(label: l.library_cleanConfirm(size), onPressed: () => nav.pop(true)),
          TfSecondaryButton(label: l.library_cancel, onPressed: () => nav.pop(false)),
        ],
      ),
    ),
  );
  if (ok != true) return;
  try {
    await store.cleanup(id: projectId);
  } on CoreError catch (e) {
    if (context.mounted) await showCoreErrorAlert(context, e);
  }
}
