import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/shell_providers.dart';
import 'package:toneforge/shell/shell_route.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_scroll.dart';
import 'package:toneforge/widgets/tf_tab_bar.dart';

import 'settings_audio_tab.dart';
import 'settings_library_tab.dart';
import 'settings_video_tab.dart';
import 'sheets/calibration_sheet.dart';

/// Ajustes (SettingsView.swift:8-43): título, subtítulo, barra de pestañas y el contenido de la pestaña,
/// con scroll y padding 36 × 28.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    // Captura de validación: `--screen calibration-sheet` abre la hoja una vez tras el primer frame
    // (el paso lo fija `--state`, p. ej. `success`).
    if (ref.read(launchOptionsProvider).screen == 'calibration-sheet') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(showCalibrationSheet(context));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tab = ref.watch(settingsTabProvider);
    return TfScroll(
      builder: (context, controller) => SingleChildScrollView(
        controller: controller,
        padding: const EdgeInsets.symmetric(horizontal: TfSpace.s36, vertical: TfSpace.s28),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: TfSpace.s20,
            children: <Widget>[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: TfSpace.s6,
                children: <Widget>[
                  Text(l.shell_navSettings, style: TfText.display(30).copyWith(color: TfColors.text)),
                  Text(l.settings_subtitle, style: TfText.body().copyWith(color: TfColors.muted)),
                ],
              ),
              TfTabBar(
                labels: <String>[for (final t in SettingsTab.values) t.label(l)],
                selected: tab.index,
                onSelect: (i) => ref.read(settingsTabProvider.notifier).select(SettingsTab.values[i]),
              ),
              switch (tab) {
                SettingsTab.audio => SettingsAudioTab(onCalibrate: () => showCalibrationSheet(context)),
                SettingsTab.video => const SettingsVideoTab(),
                SettingsTab.library => const SettingsLibraryTab(),
              },
            ],
          ),
        ),
      ),
    );
  }
}
