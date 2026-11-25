import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/features/backing/separated_projects.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/selected_project.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_progress.dart';

/// Sin tema elegido (BackingView.swift:33-52): lista de los temas ya separados.
class BackingChooser extends ConsumerWidget {
  const BackingChooser({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final projects = ref.watch(separatedProjectsProvider);
    final Widget body;
    if (projects.isLoading) {
      body = const Align(alignment: Alignment.centerLeft, child: TfSpinner.small());
    } else if ((projects.value ?? const []).isEmpty) {
      body = Text(l.backing_chooserEmpty, style: TfText.body().copyWith(color: TfColors.muted));
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TfSpace.s16,
        children: [
          Text(l.backing_chooserPick, style: TfText.body().copyWith(color: TfColors.muted)),
          for (final p in projects.value!)
            _Row(title: p.title, onTap: () => ref.read(selectedProjectProvider.notifier).select(p.id)),
        ],
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: TfSpace.s40, vertical: TfSpace.s32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TfSpace.s16,
        children: [
          Text(l.backing_title, style: TfText.display(30).copyWith(color: TfColors.text)),
          body,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: title,
      excludeSemantics: true,
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: TfColors.field,
              borderRadius: BorderRadius.circular(TfRadius.control),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: TfSpace.s12, vertical: TfSpace.s10),
              child: Text(title, style: TfText.body().copyWith(color: TfColors.text)),
            ),
          ),
        ),
      ),
    );
  }
}
