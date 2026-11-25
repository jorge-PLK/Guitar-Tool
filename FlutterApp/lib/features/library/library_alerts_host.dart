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

  Future<void> _duplicate(String id) async {
    ref.read(importStoreProvider.notifier).dismissDuplicate();
    await showDuplicateDialog(context, ref, id);
  }

  Future<void> _notice(ImportNotice n) async {
    ref.read(importStoreProvider.notifier).dismissNotice();
    await showCoreErrorAlert(context, CoreError(n.code, n.message));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(libraryStoreProvider.select((s) => s.needsFolder), (_, needs) {
      if (needs) _firstRun();
    });
    ref.listen(importStoreProvider.select((s) => s.duplicateOf), (_, id) {
      if (id != null) _duplicate(id);
    });
    ref.listen(importStoreProvider.select((s) => s.notice), (_, n) {
      if (n != null) _notice(n);
    });
    if (ref.read(libraryStoreProvider).needsFolder && !_firstRunOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ref.read(libraryStoreProvider).needsFolder) _firstRun();
      });
    }
    return widget.child;
  }
}
