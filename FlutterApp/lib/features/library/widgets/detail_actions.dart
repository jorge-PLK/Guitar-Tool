import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/library.dart';
import 'package:toneforge/features/library/dialogs/trash_dialog.dart';
import 'package:toneforge/features/library/library_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/library_detail.dart';
import 'package:toneforge/shell/selected_project.dart';
import 'package:toneforge/shell/shell_providers.dart';
import 'package:toneforge/shell/shell_route.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_buttons.dart';

/// Texto plano pulsable (`.buttonStyle(.plain)` de SwiftUI), con [leading] opcional.
class DetailTextButton extends StatelessWidget {
  const DetailTextButton({super.key, required this.label, required this.color, required this.onTap, this.leading});

  final String label;
  final Color color;
  final VoidCallback onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ?leading,
              if (leading != null) const SizedBox(width: TfSpace.s6),
              Text(label, style: TfText.body().copyWith(color: color, decoration: TextDecoration.none)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Acciones del detalle (LV:350-361).
class DetailActions extends ConsumerWidget {
  const DetailActions({super.key, required this.projectId, required this.title, required this.separation});

  final String projectId;
  final String title;
  final SeparationState separation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return Row(
      children: [
        if (separation == SeparationState.done) ...[
          TfPrimaryButton(
            label: l.library_openInBacking,
            onPressed: () {
              ref.read(selectedProjectProvider.notifier).select(projectId);
              ref.read(shellRouteProvider.notifier).select(ShellRoute.backing);
            },
          ),
          const SizedBox(width: TfSpace.s10),
        ],
        TfSecondaryButton(
          label: Platform.isWindows ? l.library_revealButtonWindows : l.library_revealButtonMac,
          onPressed: () => ref.read(libraryStoreProvider.notifier).reveal(projectId),
        ),
        const Spacer(),
        DetailTextButton(
          label: l.library_deleteButton,
          color: TfColors.muted,
          onTap: () async {
            final gone = await showTrashDialog(context, ref, projectId: projectId, title: title);
            if (gone) ref.read(libraryDetailProvider.notifier).close();
          },
        ),
      ],
    );
  }
}
