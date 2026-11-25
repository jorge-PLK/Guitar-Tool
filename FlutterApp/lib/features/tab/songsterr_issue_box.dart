import 'package:flutter/widgets.dart';
import 'package:toneforge/contract/tab.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_buttons.dart';

/// Texto del problema: traducido por `kind` (`tab_issue*`); `http`/`other`/desconocido caen al
/// mensaje del núcleo.
String songsterrIssueText(AppLocalizations l, SongsterrIssueInfo issue) => switch (issue.kind) {
      TabSongsterrIssueKind.noResults => l.tab_issueNoResults,
      TabSongsterrIssueKind.rateLimited => l.tab_issueRateLimited,
      TabSongsterrIssueKind.offline => l.tab_issueOffline,
      TabSongsterrIssueKind.formatChanged => l.tab_issueFormatChanged,
      TabSongsterrIssueKind.invalidLink => l.tab_issueInvalidLink,
      _ => issue.message,
    };

/// Caja de problema de la hoja de Songsterr (TSS:158-168): fondo `dangerBg`, mensaje,
/// sugerencia de transcripción automática y «Reintentar».
class SongsterrIssueBox extends StatelessWidget {
  const SongsterrIssueBox({super.key, required this.issue, this.onRetry});

  final SongsterrIssueInfo issue;

  /// Se usa con `issue.canRetry`.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool suggest = issue.suggestion != null &&
        (issue.kind == TabSongsterrIssueKind.noResults || !issue.canRetry);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(TfSpace.s12),
      decoration: BoxDecoration(
        color: TfColors.dangerBg,
        borderRadius: BorderRadius.circular(TfRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: TfSpace.s8,
        children: <Widget>[
          Text(songsterrIssueText(l, issue), style: const TextStyle(color: TfColors.text)),
          if (suggest)
            Text(l.tab_sheetSuggestAuto, style: const TextStyle(color: TfColors.muted)),
          if (issue.canRetry)
            TfSecondaryButton(
              label: l.tab_sheetRetry,
              height: TfSpace.s32,
              onPressed: onRetry,
            ),
        ],
      ),
    );
  }
}
