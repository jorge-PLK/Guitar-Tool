import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/tokens.dart';
import '../../../theme/typography.dart';
import '../record_store.dart';
import '../record_texts.dart';

/// Líneas de estado bajo la barra (RV:168-188), en este orden: bloqueo (muted), sin calibrar,
/// cámara, mensajes y avisos de toma (accent), errores de carga o guardado (danger).
class RecordStatusLines extends ConsumerWidget {
  const RecordStatusLines({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final RecordState s = ref.watch(recordStoreProvider);
    final snap = s.snapshot;
    final List<(String, Color)> lines = <(String, Color)>[];
    final block = s.block;
    if (block != null) {
      lines.add((recordBlockText(l, block), TfColors.muted));
    } else if (s.blockReason != null) {
      lines.add((s.blockReason!, TfColors.muted));
    }
    if (s.showUncalibrated) lines.add((l.record_uncalibrated, TfColors.accent));
    if (snap != null) {
      final String? cam = recordCameraLine(l, snap.camera);
      if (cam != null) lines.add((cam, TfColors.accent));
      for (final String m in snap.messages) {
        lines.add((m, TfColors.accent));
      }
      for (final String n in snap.notices) {
        lines.add((n, TfColors.accent));
      }
      if (snap.loadError != null) lines.add((snap.loadError!, TfColors.danger));
      if (snap.takeSaveError != null) lines.add((snap.takeSaveError!, TfColors.danger));
    }
    // Error de una acción (p. ej. fallo al empezar a grabar): línea de aviso con el mensaje del núcleo.
    if (s.error != null && s.error!.message.isNotEmpty) lines.add((s.error!.message, TfColors.accent));
    if (lines.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: TfSpace.s4,
      children: <Widget>[
        for (final (String text, Color color) in lines)
          Text(text, style: TfText.body(TfSize.font12).copyWith(color: color)),
      ],
    );
  }
}
