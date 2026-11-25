import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/video.dart';
import 'package:toneforge/features/settings/video_store.dart';
import 'package:toneforge/features/settings/widgets/camera_preview_box.dart';
import 'package:toneforge/features/settings/widgets/export_group.dart';
import 'package:toneforge/features/settings/widgets/offset_field.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_dropdown.dart';
import 'package:toneforge/widgets/tf_progress.dart';
import 'package:toneforge/widgets/tf_settings_group.dart';

/// Valor del selector de cámara para «Por defecto del sistema» (`cameraUID: null`).
const String _systemDefault = '';

/// Pestaña «Cámara y vídeo» de Ajustes (VS:244-384). Todo sale de `videoStoreProvider`.
class SettingsVideoTab extends ConsumerWidget {
  const SettingsVideoTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final VideoStoreState s = ref.watch(videoStoreProvider);
    final VideoSettings? v = s.settings;
    if (v == null) return const Center(child: TfSpinner.small());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: TfSpace.s20,
      children: <Widget>[
        _CameraGroup(state: s, settings: v),
        _SyncGroup(settings: v),
        ExportGroup(settings: v),
      ],
    );
  }
}

class _CameraGroup extends ConsumerWidget {
  const _CameraGroup({required this.state, required this.settings});

  final VideoStoreState state;
  final VideoSettings settings;

  CameraInfo? _effective() {
    final String? id = settings.effectiveCameraId;
    for (final CameraInfo c in state.cameras?.cameras ?? const <CameraInfo>[]) {
      if (c.id == id) return c;
    }
    return null;
  }

  String _note(AppLocalizations l, CameraInfo? cam) {
    if (settings.noCamera) return l.settings_video_none;
    if (settings.cameraUID != null && !settings.cameraConnected) return l.settings_video_chosenOff;
    final String name = cam?.name ?? state.preview?.cameraName ?? settings.cameraName ?? '';
    return l.settings_video_inUse(name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final VideoStore store = ref.read(videoStoreProvider.notifier);
    final CameraInfo? cam = _effective();
    final bool off = settings.noCamera;
    final String? uid = settings.cameraUID;

    final List<TfDropdownItem<String>> cams = <TfDropdownItem<String>>[
      TfDropdownItem<String>(value: _systemDefault, label: l.settings_video_systemDefault),
      for (final CameraInfo c in state.cameras?.cameras ?? const <CameraInfo>[])
        TfDropdownItem<String>(value: c.id, label: c.name),
    ];
    if (uid != null && !cams.any((TfDropdownItem<String> i) => i.value == uid)) {
      cams.add(TfDropdownItem<String>(
        value: uid,
        label: l.settings_video_cameraDisconnected(settings.cameraName ?? l.settings_video_chosenFallback),
      ));
    }

    final VideoResolution shown = settings.shown?.resolution ?? settings.resolution;
    final List<VideoResolution> resolutions = cam?.resolutions ?? const <VideoResolution>[];
    final int ri = resolutions.indexWhere((VideoResolution r) => r.width == shown.width && r.height == shown.height);
    final List<VideoFps> fpsList = ri < 0 ? const <VideoFps>[] : (resolutions[ri].fps ?? const <VideoFps>[]);
    final double fps = settings.shown?.fps ?? settings.fps;

    return TfSettingsGroup(
      title: l.settings_video_cameraTitle,
      note: _note(l, cam),
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: TfSpace.s20,
          children: <Widget>[
            Expanded(
              child: Column(
                spacing: TfSpace.s10,
                children: <Widget>[
                  TfInfoRow(
                    label: l.settings_video_camera,
                    trailing: TfDropdown<String>(
                      width: TfSize.settingsCameraWidth,
                      value: uid ?? _systemDefault,
                      items: cams,
                      onChanged: (String id) => store.setCamera(id == _systemDefault ? null : id),
                    ),
                  ),
                  TfInfoRow(
                    label: l.settings_video_resolution,
                    trailing: TfDropdown<int>(
                      width: TfSize.settingsResFpsWidth,
                      value: ri < 0 ? null : ri,
                      items: <TfDropdownItem<int>>[
                        for (int i = 0; i < resolutions.length; i++)
                          TfDropdownItem<int>(value: i, label: resolutions[i].label ?? '${resolutions[i].height}p'),
                      ],
                      onChanged: off
                          ? null
                          : (int i) => store.setResolution(resolutions[i].width, resolutions[i].height),
                    ),
                  ),
                  TfInfoRow(
                    label: l.settings_video_fps,
                    trailing: TfDropdown<double>(
                      width: TfSize.settingsResFpsWidth,
                      value: fpsList.any((VideoFps f) => f.value == fps) ? fps : null,
                      items: <TfDropdownItem<double>>[
                        for (final VideoFps f in fpsList) TfDropdownItem<double>(value: f.value, label: f.label),
                      ],
                      onChanged: off ? null : (double f) => store.setFps(f),
                    ),
                  ),
                  if (state.error != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      // TODO(ola3): traducir por `code` cuando exista el helper común de errores.
                      child: Text(
                        state.error!.message,
                        style: TfText.body(12).copyWith(color: TfColors.danger),
                      ),
                    ),
                ],
              ),
            ),
            const CameraPreviewBox(),
          ],
        ),
      ],
    );
  }
}

class _SyncGroup extends ConsumerWidget {
  const _SyncGroup({required this.settings});

  final VideoSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String? id = settings.effectiveCameraId;
    final VideoOffsetRange r = settings.choices.offsetRangeMs;
    return TfSettingsGroup(
      title: l.settings_video_syncTitle,
      note: l.settings_video_syncNote,
      children: <Widget>[
        TfInfoRow(
          label: l.settings_video_offset,
          trailing: OffsetField(
            value: settings.offsetMs,
            min: r.min,
            max: r.max,
            onChanged: id == null
                ? null
                : (int ms) => ref.read(videoStoreProvider.notifier).setOffset(ms.toDouble(), cameraId: id),
          ),
        ),
      ],
    );
  }
}
