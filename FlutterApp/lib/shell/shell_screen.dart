import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/features/backing/backing_screen.dart';
import 'package:toneforge/features/library/import_store.dart';
import 'package:toneforge/features/library/library_alerts_host.dart';
import 'package:toneforge/features/library/library_screen.dart';
import 'package:toneforge/features/library/library_store.dart';
import 'package:toneforge/features/montage/montage_screen.dart';
import 'package:toneforge/features/record/record_screen.dart';
import 'package:toneforge/features/settings/settings_screen.dart';
import 'package:toneforge/features/tab/tab_screen.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_drop_target.dart';
import 'package:toneforge/widgets/tf_sidebar.dart';
import 'package:toneforge/widgets/tf_sidebar_cards.dart';
import 'package:toneforge/widgets/tf_tooltip.dart';

import 'library_detail.dart';
import 'selected_project.dart';
import 'shell_providers.dart';
import 'shell_route.dart';

/// Carcasa (RootView.swift:10-24): barra lateral de 240 y, a la derecha, la pantalla de la ruta actual.
class ShellScreen extends ConsumerWidget {
  const ShellScreen({super.key});

  static const List<ShellRoute> _navRoutes = <ShellRoute>[
    ShellRoute.library,
    ShellRoute.backing,
    ShellRoute.tab,
    ShellRoute.record,
    ShellRoute.montage,
  ];

  Widget _screen(ShellRoute route) => switch (route) {
        ShellRoute.library => const LibraryScreen(),
        ShellRoute.backing => const BackingScreen(),
        ShellRoute.tab => const TabScreen(),
        ShellRoute.record => const RecordScreen(),
        ShellRoute.montage => const MontageScreen(),
        ShellRoute.settings => const SettingsScreen(),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(coreProbeProvider);
    final l = AppLocalizations.of(context);
    final route = ref.watch(shellRouteProvider);
    final notifier = ref.read(shellRouteProvider.notifier);
    final detailId = ref.watch(libraryDetailProvider);
    final selectedId = ref.watch(selectedProjectProvider);
    final selected = selectedId == null
        ? null
        : ref.watch(libraryStoreProvider.select((s) => s.entries.where((e) => e.id == selectedId).firstOrNull));
    TfSidebarEntry entry(ShellRoute r) => TfSidebarEntry(
          icon: r.icon,
          label: r.label(l),
          selected: route == r,
          onTap: () {
            // RV:58: la fila «Biblioteca» también cierra la página del tema.
            if (r == ShellRoute.library) ref.read(libraryDetailProvider.notifier).close();
            notifier.select(r);
          },
        );
    return TfDropTarget(
      onPaths: (paths) => ref.read(importStoreProvider.notifier).importPaths(paths),
      child: ColoredBox(
        color: TfColors.bg,
        child: DefaultTextStyle(
          style: TfText.body().copyWith(color: TfColors.text),
          child: LibraryAlertsHost(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // La ola 3 añade la tarjeta del dispositivo de audio en `bottom`.
                TfSidebar(
                  logoTone: l.shell_logoTone,
                  logoForge: l.shell_logoForge,
                  entries: <TfSidebarEntry>[for (final r in _navRoutes) entry(r)],
                  bottom: <Widget>[
                    TfNavRow(
                      icon: ShellRoute.settings.icon,
                      label: ShellRoute.settings.label(l),
                      active: route == ShellRoute.settings,
                      onTap: () => notifier.select(ShellRoute.settings),
                    ),
                    if (selected != null)
                      TfTooltip(
                        message: l.shell_selectedThemeHelp,
                        child: TfSelectedTrackCard(
                          title: selected.title,
                          artist: selected.artist ?? '',
                          active: route == ShellRoute.library && detailId == selected.id,
                          semanticLabel: l.shell_selectedThemeLabel(selected.title),
                          onTap: () {
                            ref.read(libraryDetailProvider.notifier).open(selected.id);
                            notifier.select(ShellRoute.library);
                          },
                        ),
                      ),
                  ],
                ),
                Expanded(child: _screen(route)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
