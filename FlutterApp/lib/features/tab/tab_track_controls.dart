import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/tab.dart';
import 'package:toneforge/features/tab/tab_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_checkbox.dart';
import 'package:toneforge/widgets/tf_dropdown.dart';
import 'package:toneforge/widgets/tf_progress.dart';

/// Ancho del desplegable de afinación (`TabScreen.swift:306`); sin token en `theme/`.
const double tabTuningWidth = 170;

/// Controles de la pista seleccionada (`TabScreen.swift:294-319`).
class TabTrackControls extends ConsumerWidget {
  const TabTrackControls({super.key, required this.track});

  final TabTrackInfo track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final TabStore store = ref.read(tabStoreProvider.notifier);
    final String? header = ref.watch(tabStoreProvider.select((TabStoreState s) => s.tab?.header));
    final TextStyle base = TfText.body(TfSize.font13).copyWith(color: TfColors.text2);
    final TextStyle muted = base.copyWith(color: TfColors.muted);
    final TabTuningInfo? tuning = track.tuning;
    final TabTuningInfo? custom = track.customTuning;
    return DefaultTextStyle(
      style: base,
      child: Row(
        spacing: TfSpace.s16,
        children: <Widget>[
          if (track.kind != TabTrackKind.drums && tuning != null)
            Row(
              spacing: TfSpace.s8,
              children: <Widget>[
                Text(l.tab_tuning, style: muted, maxLines: 1),
                TfDropdown<TabTuningPreset>(
                  width: tabTuningWidth,
                  value: tuning.preset,
                  items: <TfDropdownItem<TabTuningPreset>>[
                    TfDropdownItem(value: TabTuningPreset.standard, label: l.tab_tuningStandard),
                    TfDropdownItem(value: TabTuningPreset.halfStepDown, label: l.tab_tuningHalfDown),
                    TfDropdownItem(value: TabTuningPreset.wholeStepDown, label: l.tab_tuningWholeDown),
                    TfDropdownItem(value: TabTuningPreset.dropD, label: l.tab_tuningDropD),
                    if (custom != null || tuning.preset == TabTuningPreset.custom)
                      TfDropdownItem(
                        value: TabTuningPreset.custom,
                        label: (custom ?? tuning).name.isEmpty ? l.tab_tuningCustom : (custom ?? tuning).name,
                      ),
                  ],
                  onChanged: (TabTuningPreset p) =>
                      store.edit(TabEditParams.tuning(track: track.id, preset: p.wire)),
                ),
              ],
            ),
          TfCheckbox(
            value: track.listening,
            label: l.tab_listenTrack,
            onChanged: (bool on) => store.setListening(track.id, on: on),
          ),
          if (track.synth == TabSynth.rendering)
            Row(
              spacing: TfSpace.s6,
              children: <Widget>[const TfSpinner.small(), Text(l.tab_synthRendering, style: muted)],
            ),
          const Spacer(),
          if (header != null && header.isNotEmpty) Text(header, style: muted),
        ],
      ),
    );
  }
}
