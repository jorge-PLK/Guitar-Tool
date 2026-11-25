import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/study.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/shell_providers.dart';
import 'package:toneforge/shell/shell_route.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_pill.dart';
import 'package:toneforge/widgets/tf_tooltip.dart';

/// Cabecera (BackingView.swift:117-146): «artista · título», «Backing track» y las dos acciones.
class BackingHeader extends ConsumerWidget {
  const BackingHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final study = ref.watch(studyStoreProvider.select((s) => s.study));
    final guitars = [
      for (final c in study?.transport.channels ?? const <StudyChannel>[])
        if (c.kind == StudyStemKind.guitar) c,
    ];
    final guitarsOff = guitars.isNotEmpty && guitars.every((c) => c.muted);
    final subtitle = [
      for (final p in [study?.artist, study?.title])
        if (p != null && p.isNotEmpty) p,
    ].join(' · ');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: TfSpace.s2,
            children: [
              if (subtitle.isNotEmpty)
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TfText.body(TfSize.font13).copyWith(color: TfColors.muted)),
              Text(l.backing_title, style: TfText.display(26).copyWith(color: TfColors.text)),
            ],
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: TfSpace.s10,
          children: [
            if (guitars.isNotEmpty)
              TfPill(
                label: l.backing_withoutGuitars,
                active: guitarsOff,
                onPressed: () => ref.read(studyStoreProvider.notifier).toggleNoGuitars(),
              ),
            TfTooltip(
              message: l.backing_tabButtonTooltip,
              child: TfSecondaryButton(
                label: l.backing_tabButton,
                height: TfSize.pillHeight,
                onPressed: () => ref.read(shellRouteProvider.notifier).select(ShellRoute.tab),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
