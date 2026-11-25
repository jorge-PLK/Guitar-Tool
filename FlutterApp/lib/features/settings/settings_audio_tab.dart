import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/audio.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_dropdown.dart';
import 'package:toneforge/widgets/tf_input_meters.dart';
import 'package:toneforge/widgets/tf_notice.dart';
import 'package:toneforge/widgets/tf_segmented.dart';
import 'package:toneforge/widgets/tf_settings_group.dart';

import 'audio_store.dart';
import 'widgets/audio_texts.dart';
import 'widgets/latency_status.dart';
import 'widgets/rate_mismatch.dart';

/// Ajustes · Audio: dispositivo, canales y calibración. [onCalibrate] abre la hoja de calibración
/// (otra parte); por defecto solo lanza `audio.calibrate`.
class SettingsAudioTab extends ConsumerWidget {
  const SettingsAudioTab({super.key, this.onCalibrate});

  final VoidCallback? onCalibrate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final AudioStoreState s = ref.watch(audioStoreProvider);
    final AudioStore store = ref.read(audioStoreProvider.notifier);
    final AudioSettings? cfg = s.settings;
    if (cfg == null) return const SizedBox.shrink();
    final AudioDevices? dev = s.devices;
    final bool noInput = cfg.inputDeviceUID == null;
    final String? block =
        calibrateBlockText(l, s.calibrateBlockMessage, fallback: s.calibrateBlock);
    final bool canCalibrate = block == null && !s.calibrating && !s.calibrationRunning;
    final List<double>? levels = noInput || (s.levels?.levels.isEmpty ?? true) ? null : s.levels!.levels;
    final AudioRateMismatch? mm = cfg.rateMismatch;
    final int bi = backingIndex(cfg);
    final int gi = guitarIndex(cfg);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: TfSpace.s20,
      children: <Widget>[
        if (s.error != null)
          TfNotice(
            messages: <String>[s.error!.message], // TODO(ola3): traducir por code (sin claves error_*)
            tone: TfNoticeTone.danger,
            onDismiss: store.clearError,
          ),
        TfSettingsGroup(
          title: l.settings_audio_deviceTitle,
          note: l.settings_audio_deviceNote,
          children: <Widget>[
            TfInfoRow(
              label: l.settings_audio_output,
              trailing: TfDropdown<String?>(
                items: deviceItems(l, dev?.outputs ?? const <AudioDeviceItem>[],
                    cfg.outputDeviceUID, nullLabel: l.settings_audio_systemOutput),
                value: cfg.outputDeviceUID,
                onChanged: store.setOutput,
              ),
            ),
            TfInfoRow(
              label: l.settings_audio_input,
              trailing: TfDropdown<String?>(
                items: deviceItems(l, dev?.inputs ?? const <AudioDeviceItem>[],
                    cfg.inputDeviceUID, nullLabel: l.settings_audio_noInput),
                value: cfg.inputDeviceUID,
                onChanged: store.setInput,
              ),
            ),
            TfInfoRow(
              label: l.settings_audio_rate,
              trailing: TfSegmented<int>(
                segments: <TfSegment<int>>[
                  for (final AudioSampleRate r in cfg.allowedSampleRates)
                    TfSegment<int>(value: r.rate.round(), label: r.label),
                ],
                value: cfg.workingSampleRate.round(),
                onChanged: store.setWorkingSampleRate,
              ),
            ),
            if (mm != null)
              RateMismatchNotice(
                mismatch: mm,
                deviceRate: rateLabel(cfg, mm.deviceRate),
                workingRate: rateLabel(cfg, mm.workingRate),
                onUseDeviceRate: store.useDeviceRate,
              ),
          ],
        ),
        TfSettingsGroup(
          title: l.settings_audio_channelsTitle,
          note: l.settings_audio_channelsNote,
          children: <Widget>[
            TfInfoRow(
              label: l.settings_audio_backingOut,
              trailing: TfDropdown<int>(
                items: <TfDropdownItem<int>>[
                  for (int i = 0; i < cfg.backingChoices.length; i++)
                    TfDropdownItem<int>(value: i, label: backingLabel(l, cfg.backingChoices[i])),
                ],
                value: bi < 0 ? null : bi,
                onChanged: (int i) =>
                    store.setBackingOut(cfg.backingChoices[i].left, cfg.backingChoices[i].right),
              ),
            ),
            TfInfoRow(
              label: l.settings_audio_guitarIn,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: TfSpace.s12,
                children: <Widget>[
                  TfInputMeters(levels: levels),
                  TfDropdown<int>(
                    items: <TfDropdownItem<int>>[
                      for (int i = 0; i < cfg.guitarChoices.length; i++)
                        TfDropdownItem<int>(value: i, label: guitarLabel(l, cfg.guitarChoices[i])),
                    ],
                    value: gi < 0 ? null : gi,
                    placeholder: l.settings_audio_unassigned,
                    onChanged: noInput
                        ? null
                        : (int i) => store.setGuitarIn(cfg.guitarChoices[i].channels),
                  ),
                ],
              ),
            ),
          ],
        ),
        TfSettingsGroup(
          title: l.settings_audio_calTitle,
          note: l.settings_audio_calNote,
          children: <Widget>[
            TfInfoRow(
              label: l.settings_audio_latency,
              trailing: LatencyStatus(calibration: cfg.calibration),
            ),
            TfSecondaryButton(
              label: l.settings_audio_calibrate,
              onPressed: canCalibrate ? (onCalibrate ?? () => store.calibrate()) : null,
            ),
            if (block != null)
              Text(block, style: TfText.body(TfSize.font12).copyWith(color: TfColors.muted)),
          ],
        ),
      ],
    );
  }
}
