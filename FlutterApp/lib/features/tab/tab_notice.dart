import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/features/tab/tab_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/widgets/tf_notice.dart';

/// Aviso descartable entre la cabecera y la tarjeta (TabScreen.swift:169-181). Vacío sin `notices`.
class TabNotice extends ConsumerWidget {
  const TabNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notices = ref.watch(tabStoreProvider.select((s) => s.notices));
    if (notices.isEmpty) return const SizedBox.shrink();
    return TfNotice(
      messages: notices,
      dismissLabel: AppLocalizations.of(context).tab_a11yCloseNotice,
      onDismiss: ref.read(tabStoreProvider.notifier).dismissNotices,
    );
  }
}
