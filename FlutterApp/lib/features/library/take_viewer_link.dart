import 'package:flutter/widgets.dart';
import 'package:toneforge/contract/library_detail.dart';
import 'package:toneforge/features/library/project_detail_store.dart';
import 'package:toneforge/features/record/sheets/take_viewer_sheet.dart';
import 'package:toneforge/l10n/app_localizations.dart';

/// Abre el visor de una toma desde la Biblioteca. Como SwiftUI (ProjectRecordingsView.swift:92-97), no abre el
/// proyecto antes: `takeview.open` lleva el `projectId`; «mejor» y «Eliminar» van por `library.*` y recargan el detalle.
Future<void> openTakeViewer(
  BuildContext context, {
  required String projectId,
  required String takeId,
  required PartInfo part,
  required TakeInfo take,
}) {
  final title = AppLocalizations.of(context).library_takeLabel(take.number, part.name);
  return showTakeViewer(
    context,
    projectId: projectId,
    takeId: takeId,
    host: TakeViewerHost(
      title: title,
      isBest: (ref) {
        final d = ref.watch(projectDetailStoreProvider(projectId)).detail;
        if (d == null) return take.isBest;
        for (final p in d.parts) {
          for (final t in p.takes) {
            if (t.id == takeId) return t.isBest;
          }
        }
        return false;
      },
      markBest: (ref) => ref.read(projectDetailStoreProvider(projectId).notifier).markBest(takeId),
      delete: (ref) => ref.read(projectDetailStoreProvider(projectId).notifier).deleteTake(takeId),
    ),
  );
}
