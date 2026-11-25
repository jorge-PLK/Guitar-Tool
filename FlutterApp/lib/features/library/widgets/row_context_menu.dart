import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/library.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/features/library/dialogs/clean_dialog.dart';
import 'package:toneforge/features/library/dialogs/trash_dialog.dart';
import 'package:toneforge/features/library/import_store.dart';
import 'package:toneforge/features/library/library_errors.dart';
import 'package:toneforge/features/library/library_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/widgets/tf_menu.dart';

/// Texto de «Mostrar en Finder» / «Explorador de archivos» según la plataforma.
bool get isMacHost => defaultTargetPlatform == TargetPlatform.macOS;

/// Revela el tema en el gestor de archivos; si el núcleo falla, avisa.
Future<void> revealProject(BuildContext context, WidgetRef ref, String id) async {
  final error = await ref.read(libraryStoreProvider.notifier).reveal(id);
  if (error != null && context.mounted) unawaited(showCoreErrorAlert(context, error));
}

/// Menú contextual de una fila de tema (LV:245-253).
class RowContextMenu extends ConsumerWidget {
  const RowContextMenu({super.key, required this.entry, required this.child});

  final ProjectSummary entry;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final state = ref.watch(importStoreProvider.select((s) => s.separationStateFor(entry)));
    final separating = state == SeparationState.queued || state == SeparationState.running;
    final store = ref.read(libraryStoreProvider.notifier);

    Future<void> run(Future<CoreError?> Function() action) async {
      final error = await action();
      if (error != null && context.mounted) unawaited(showCoreErrorAlert(context, error));
    }

    return TfContextMenu(
      entries: [
        TfMenuItem(
          label: l.library_menuSeparate,
          enabled: !separating,
          onSelected: () => run(() => store.separate(entry.id)),
        ),
        if (separating)
          TfMenuItem(
            label: l.library_menuCancelSeparation,
            onSelected: () => run(() => store.cancelSeparation(entry.id)),
          ),
        TfMenuItem(
          label: l.library_menuClean,
          enabled: !separating,
          onSelected: () => showCleanDialog(context, ref, projectId: entry.id, title: entry.title),
        ),
        TfMenuItem(
          label: isMacHost ? l.library_menuRevealMac : l.library_menuRevealWindows,
          onSelected: () => revealProject(context, ref, entry.id),
        ),
        const TfMenuDivider(),
        TfMenuItem(
          label: l.library_menuDelete,
          destructive: true,
          onSelected: () => showTrashDialog(context, ref, projectId: entry.id, title: entry.title),
        ),
      ],
      child: child,
    );
  }
}
