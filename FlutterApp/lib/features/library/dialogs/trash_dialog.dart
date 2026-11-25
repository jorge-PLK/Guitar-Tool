import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_sheet.dart';

import '../library_errors.dart';
import '../library_store.dart';

enum _Choice { bin, disk }

/// Mensaje con el contenido: «sus stems» / «1 stem» / «N stems», tomas y vídeos solo si hay.
String trashContentsText(AppLocalizations l, TrashContent c) => <String>[
  l.library_trashContentsStems(c.stems),
  if (c.takes > 0) l.library_trashContentsTakes(c.takes),
  if (c.videos > 0) l.library_trashContentsVideos(c.videos),
].join(', ');

/// Diálogo «¿Eliminar “{título}”?» (LV:41-49): pide el contenido, confirma y llama a `trash`/`delete`.
/// Devuelve true si el tema se eliminó.
Future<bool> showTrashDialog(
  BuildContext context,
  WidgetRef ref, {
  required String projectId,
  required String title,
}) async {
  final l = AppLocalizations.of(context);
  final windows = defaultTargetPlatform == TargetPlatform.windows;
  final store = ref.read(libraryStoreProvider.notifier);
  final content = await store.trashContent(projectId);
  if (!context.mounted) return false;
  final nav = Navigator.of(context);
  final choice = await showTfSheet<_Choice>(
    context: context,
    centered: true,
    onCancel: () => nav.pop(),
    onPrimary: () => nav.pop(_Choice.bin),
    builder: (BuildContext ctx) => TfSheetScaffold(
      width: TfSize.alertWidth,
      title: l.library_trashTitle(title),
      // Tres botones no caben en 320: se apilan, como el `confirmationDialog` nativo.
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TfSpace.s12,
        children: <Widget>[
          Text(
            windows
                ? l.library_trashMessageWindows(trashContentsText(l, content))
                : l.library_trashMessageMac(trashContentsText(l, content)),
          ),
          TfPrimaryButton(
            label: windows ? l.library_trashToBinWindows : l.library_trashToBinMac,
            onPressed: () => nav.pop(_Choice.bin),
          ),
          TfDangerButton(label: l.library_trashDelete, onPressed: () => nav.pop(_Choice.disk)),
          TfSecondaryButton(label: l.library_cancel, onPressed: () => nav.pop()),
        ],
      ),
    ),
  );
  if (choice == null) return false;
  final err = choice == _Choice.bin ? await store.trash(projectId) : await store.delete(projectId);
  if (err == null) return true;
  if (!context.mounted) return false;
  if (choice == _Choice.disk) {
    await showCoreErrorAlert(context, err, title: l.library_errDelete);
  } else {
    // AM:978-979: el título depende de la plataforma y el cuerpo añade «te queda Eliminar del disco».
    await showCoreErrorAlert(
      context,
      err,
      title: windows ? l.library_errTrashTitleWindows : l.library_errTrashTitleMac,
      message: l.library_errTrashBody(coreErrorText(l, err)),
    );
  }
  return false;
}
