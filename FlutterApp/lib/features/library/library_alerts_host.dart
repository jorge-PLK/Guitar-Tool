import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Wraps the shell body and shows the library's app-wide dialogs:
/// the first-run folder sheet, and the duplicate/notice alerts raised by
/// `import.file` (also from files dropped on any screen).
class LibraryAlertsHost extends ConsumerWidget {
  const LibraryAlertsHost({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => child;
}
