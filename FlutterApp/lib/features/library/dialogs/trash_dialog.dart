import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Diálogo «¿Eliminar “{título}”?» (LV:41-49): pide el contenido, confirma y llama a `trash`/`delete`.
/// Devuelve true si el tema se eliminó. Provisional: lo rellena la parte B.
Future<bool> showTrashDialog(
  BuildContext context,
  WidgetRef ref, {
  required String projectId,
  required String title,
}) async =>
    false;
