import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/video.dart';
import 'package:toneforge/features/settings/video_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_dropdown.dart';
import 'package:toneforge/widgets/tf_segmented.dart';
import 'package:toneforge/widgets/tf_settings_group.dart';
import 'package:toneforge/widgets/tf_switch.dart';

String _codecLabel(String codec) => switch (codec) {
      'h264' => 'H.264',
      _ => codec.toUpperCase(),
    };

/// Grupo «Exportación por defecto» (VS:354-383): formato + resolución en la misma fila, volumen fijo y
/// dos interruptores. Cada cambio envía solo su campo por `setExport`.
class ExportGroup extends ConsumerWidget {
  const ExportGroup({super.key, required this.settings});

  final VideoSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final VideoStore store = ref.read(videoStoreProvider.notifier);
    final VideoExport e = settings.export;
    final List<VideoResolution> res = settings.choices.exportResolutions;
    int idx = res.indexWhere((VideoResolution r) => r.width == e.resolution.width && r.height == e.resolution.height);
    if (idx < 0) idx = 0;
    return TfSettingsGroup(
      title: l.settings_video_exportTitle,
      note: l.settings_video_exportNote,
      children: <Widget>[
        TfInfoRow(
          label: l.settings_video_format,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: TfSpace.s12,
            children: <Widget>[
              TfSegmented<String>(
                width: TfSize.exportCodecWidth,
                value: e.codec,
                segments: <TfSegment<String>>[
                  for (final String c in settings.choices.codecs)
                    TfSegment<String>(value: c, label: _codecLabel(c)),
                ],
                onChanged: (String c) => store.setExport(VideoExportParams(codec: c)),
              ),
              TfDropdown<int>(
                width: TfSize.exportResolutionWidth,
                value: res.isEmpty ? null : idx,
                items: <TfDropdownItem<int>>[
                  for (int i = 0; i < res.length; i++)
                    TfDropdownItem<int>(value: i, label: res[i].label ?? '${res[i].height}p'),
                ],
                onChanged: (int i) => store.setExport(VideoExportParams(
                    resolution: VideoResolution(width: res[i].width, height: res[i].height))),
              ),
            ],
          ),
        ),
        TfInfoRow(
          label: l.settings_video_volume,
          trailing: Text(
            l.settings_video_volumeValue,
            style: TfText.body(TfSize.font14, TfWeight.semibold).copyWith(color: TfColors.text2),
          ),
        ),
        TfInfoRow(
          label: l.settings_video_titleOverlay,
          trailing: TfSwitch(
            value: e.titleOverlay,
            semanticLabel: l.settings_video_titleOverlay,
            onChanged: (bool v) => store.setExport(VideoExportParams(titleOverlay: v)),
          ),
        ),
        TfInfoRow(
          label: l.settings_video_stemWavs,
          trailing: TfSwitch(
            value: e.exportStemWAVs,
            semanticLabel: l.settings_video_stemWavs,
            onChanged: (bool v) => store.setExport(VideoExportParams(exportStemWAVs: v)),
          ),
        ),
      ],
    );
  }
}
