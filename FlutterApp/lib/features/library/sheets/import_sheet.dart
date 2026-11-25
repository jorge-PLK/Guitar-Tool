import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/features/library/dialogs/duplicate_dialog.dart';
import 'package:toneforge/features/library/library_metrics.dart';
import 'package:toneforge/features/library/link_import_store.dart';
import 'package:toneforge/features/library/playlist_store.dart';
import 'package:toneforge/features/library/sheets/import_candidates_view.dart';
import 'package:toneforge/features/library/sheets/import_empty_view.dart';
import 'package:toneforge/features/library/sheets/import_status_views.dart';
import 'package:toneforge/features/library/sheets/import_working_view.dart';
import 'package:toneforge/features/library/sheets/playlist_import_view.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_sheet.dart';

/// Abre la hoja «Importar tema» (LinkImportSheet): un único `TfSheet` que conmuta por pantalla.
/// Si hay una lista abierta en `playlistStore`, entra directamente en la pantalla de lista.
Future<void> showImportSheet(BuildContext context) async {
  final container = ProviderScope.containerOf(context);
  final p = container.read(playlistStoreProvider);
  final resume = p.snapshot != null && p.sheetOpen;
  if (!resume) container.read(linkImportStoreProvider.notifier).reset();
  var closed = false;
  void close(BuildContext ctx) {
    if (closed || !container.read(linkImportStoreProvider).canCancel) return;
    closed = true;
    container.read(linkImportStoreProvider.notifier).reset();
    Navigator.of(ctx).maybePop();
  }

  late BuildContext sheetContext;
  await showTfSheet<void>(
    context: context,
    onCancel: () => close(sheetContext),
    onPrimary: () {
      final s = container.read(linkImportStoreProvider);
      if (s.screen == LinkImportScreen.empty) container.read(linkImportStoreProvider.notifier).submit();
    },
    builder: (ctx) {
      sheetContext = ctx;
      return ImportSheetBody(resumePlaylist: resume, onClose: () => close(ctx), parent: context);
    },
  );
}

/// Contenido de la hoja de importación.
class ImportSheetBody extends ConsumerStatefulWidget {
  const ImportSheetBody({super.key, required this.onClose, required this.parent, this.resumePlaylist = false});

  final VoidCallback onClose;

  /// Contexto desde el que se abrió la hoja (para la alerta de duplicado).
  final BuildContext parent;

  /// Abierta con una lista ya cargada: muestra la pantalla de lista.
  final bool resumePlaylist;

  @override
  ConsumerState<ImportSheetBody> createState() => _ImportSheetBodyState();
}

class _ImportSheetBodyState extends ConsumerState<ImportSheetBody> {
  late bool _resume = widget.resumePlaylist;

  Future<void> _duplicate(String id) async {
    final store = ref.read(linkImportStoreProvider.notifier);
    await showDuplicateDialog(widget.parent, ref, id);
    if (!mounted) return;
    store.dismissDuplicate();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    ref.listen(linkImportStoreProvider, (prev, s) {
      final id = s.duplicateOf;
      if (id != null && prev?.duplicateOf != id && s.screen == LinkImportScreen.empty) {
        _duplicate(id);
      } else if (s.screen == LinkImportScreen.done && s.notices.isEmpty && prev?.screen != s.screen) {
        widget.onClose();
      }
    });
    ref.listen(playlistStoreProvider.select((p) => p.snapshot), (prev, snap) {
      if (snap == null && _resume) setState(() => _resume = false);
    });
    final screen = ref.watch(linkImportStoreProvider.select((s) => s.screen));
    final effective = _resume && screen == LinkImportScreen.empty ? LinkImportScreen.playlist : screen;
    final wide = effective == LinkImportScreen.playlist;
    final empty = effective == LinkImportScreen.empty;
    final title = wide
        ? l.library_importTitleList
        : empty
        ? l.library_importTitleEmpty
        : l.library_importTitleLink;
    final width = wide
        ? LibraryMetrics.playlistSheetWidth
        : empty
        ? LibraryMetrics.importSheetEmptyWidth
        : LibraryMetrics.importSheetWidth;
    final body = switch (effective) {
      LinkImportScreen.empty => ImportEmptyView(onClose: widget.onClose),
      LinkImportScreen.resolving => const ImportResolvingView(),
      LinkImportScreen.preparing => const ImportPreparingView(),
      LinkImportScreen.candidates => ImportCandidatesView(onClose: widget.onClose),
      LinkImportScreen.working => const ImportWorkingView(),
      LinkImportScreen.error => ImportErrorView(onClose: widget.onClose),
      LinkImportScreen.done => ImportDoneView(onClose: widget.onClose),
      LinkImportScreen.repeated => ImportRepeatedView(onClose: widget.onClose),
      LinkImportScreen.playlist => const PlaylistImportView(),
    };
    return Semantics(
      container: true,
      explicitChildNodes: true,
      scopesRoute: true,
      namesRoute: true,
      label: title,
      child: SizedBox(
        width: width,
        height: wide ? LibraryMetrics.playlistSheetHeight : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: TfColors.card,
            borderRadius: BorderRadius.circular(TfRadius.card),
            border: Border.all(color: TfColors.line, width: TfStroke.hairline),
          ),
          child: Padding(
            padding: const EdgeInsets.all(TfSpace.s24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: TfSpace.s18,
              children: [
                Text(title, style: TfText.display(22).copyWith(color: TfColors.text)),
                wide ? Expanded(child: body) : Flexible(child: body),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
