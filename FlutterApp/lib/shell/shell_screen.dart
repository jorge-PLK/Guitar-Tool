import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/features/backing/backing_screen.dart';
import 'package:toneforge/features/library/library_screen.dart';
import 'package:toneforge/features/montage/montage_screen.dart';
import 'package:toneforge/features/record/record_screen.dart';
import 'package:toneforge/features/settings/settings_screen.dart';
import 'package:toneforge/features/tab/tab_screen.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_sidebar.dart';

import 'device_card.dart';
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
    TfSidebarEntry entry(ShellRoute r) =>
        TfSidebarEntry(icon: r.icon, label: r.label(l), selected: route == r, onTap: () => notifier.select(r));
    return ColoredBox(
      color: TfColors.bg,
      child: DefaultTextStyle(
        style: TfText.body().copyWith(color: TfColors.text),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Ola 1 añade aquí (en `bottom`) la tarjeta del tema seleccionado; la ola 3, la del dispositivo de audio.
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
                const DeviceCard(),
              ],
            ),
            Expanded(child: _screen(route)),
          ],
        ),
      ),
    );
  }
}
