import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/core/core_client.dart';

import 'dialogs/duplicate_dialog.dart';
import 'import_store.dart';
import 'library_errors.dart';
import 'library_store.dart';
import 'sheets/first_run_sheet.dart';

/// Wraps the shell body and shows the library's app-wide dialogs:
/// the first-run folder sheet, and the duplicate/notice alerts raised by
/// `import.file` (also from files dropped on any screen).
class LibraryAlertsHost extends ConsumerStatefulWidget {
  const LibraryAlertsHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<LibraryAlertsHost> createState() => _LibraryAlertsHostState();
}

class _LibraryAlertsHostState extends ConsumerState<LibraryAlertsHost> {
  bool _firstRunOpen = false;

  Future<void> _firstRun() async {
    if (_firstRunOpen) return;
    _firstRunOpen = true;
    await showFirstRunSheet(context);
    _firstRunOpen = false;
  }

  // Cola FIFO: una sola alerta visible; al cerrarla sale la siguiente.
  final List<Future<void> Function()> _queue = [];
  bool _draining = false;

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    while (_queue.isNotEmpty && mounted) {
      await _queue.removeAt(0)();
    }
    _draining = false;
  }

  void _duplicate(String id) {
    ref.read(importStoreProvider.notifier).dismissDuplicate();
    _queue.add(() => showDuplicateDialog(context, ref, id));
    _drain();
  }

  void _notice(ImportNotice n) {
    ref.read(importStoreProvider.notifier).dismissNotice();
    _queue.add(() => showCoreErrorAlert(context, CoreError(n.code, n.message)));
    _drain();
  }

  @override
  Widget build(BuildContext context) {
    // Sin núcleo (store en error) el host no tumba la app: ignora los errores.
    void ignore(Object _, StackTrace _) {}
    ref.listen(libraryStoreProvider.select((s) => s.needsFolder), (_, needs) {
      if (needs) _firstRun();
    }, onError: ignore);
    ref.listen(importStoreProvider.select((s) => s.duplicateOf), (_, id) {
      if (id != null) _duplicate(id);
    }, onError: ignore);
    ref.listen(importStoreProvider.select((s) => s.notice), (_, n) {
      if (n != null) _notice(n);
    }, onError: ignore);
    if (_needsFolder && !_firstRunOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _needsFolder) _firstRun();
      });
    }
    return widget.child;
  }

  bool get _needsFolder {
    try {
      return ref.read(libraryStoreProvider).needsFolder;
    } catch (_) {
      return false;
    }
  }
}
