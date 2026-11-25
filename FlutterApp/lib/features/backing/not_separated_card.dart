import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/shell_providers.dart';
import 'package:toneforge/shell/shell_route.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_card.dart';

/// «Tema sin separar» (BackingView.swift:148-157): título, explicación y salto a la biblioteca.
class NotSeparatedCard extends ConsumerWidget {
  const NotSeparatedCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return TfCard(
      child: Padding(
        padding: const EdgeInsets.all(TfSpace.s20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: TfSpace.s12,
          children: [
            Text(l.backing_notSeparatedTitle, style: TfText.display(18).copyWith(color: TfColors.text)),
            Text(l.backing_notSeparatedBody, style: TfText.body().copyWith(color: TfColors.muted)),
            TfSecondaryButton(
              label: l.backing_goToLibrary,
              onPressed: () => ref.read(shellRouteProvider.notifier).select(ShellRoute.library),
            ),
          ],
        ),
      ),
    );
  }
}
