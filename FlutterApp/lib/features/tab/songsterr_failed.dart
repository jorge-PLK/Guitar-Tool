import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/tab.dart';
import 'package:toneforge/features/tab/songsterr_issue_box.dart';
import 'package:toneforge/features/tab/songsterr_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_buttons.dart';

/// Paso `.failed(issue)` de la hoja de Songsterr (TSS:191-201): caja de problema con el
/// reintento de importación, `Spacer`, «Volver» a la izquierda y «Transcribir
/// automáticamente» a la derecha.
class SongsterrFailed extends ConsumerWidget {
  const SongsterrFailed({super.key, required this.issue});

  final SongsterrIssueInfo? issue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final SongsterrStore store = ref.read(songsterrStoreProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: TfSpace.s12,
      children: <Widget>[
        if (issue != null) SongsterrIssueBox(issue: issue!, onRetry: store.retryImport),
        const Spacer(),
        Row(
          children: <Widget>[
            TfSecondaryButton(label: l.tab_sheetBack, height: TfSpace.s36, onPressed: store.back),
            const Spacer(),
            TfSecondaryButton(
              label: l.tab_sheetAutomatic,
              height: TfSpace.s36,
              onPressed: store.automatic,
            ),
          ],
        ),
      ],
    );
  }
}
