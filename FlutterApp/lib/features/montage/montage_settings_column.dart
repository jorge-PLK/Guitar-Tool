import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../contract/montage.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/tf_card.dart';
import '../../widgets/tf_checkbox.dart';
import '../../widgets/tf_dropdown.dart';
import '../../widgets/tf_tooltip.dart';
import 'montage_store.dart';
import 'montage_transitions_popover.dart';

/// Columna «Exportación» de Montaje (MV:406-497): pickers de menú y casillas; cada cambio va al núcleo.
/// Todo se deshabilita mientras se exporta.
class MontageSettingsColumn extends ConsumerWidget {
  const MontageSettingsColumn({super.key});

  static String _resKey(int w, int h) => '${w}x$h';

  String _resolutionLabel(AppLocalizations l, MontageResolutionInfo r) {
    if (r.width == 1280 && r.height == 720) return l.montageResolutionLabel720;
    if (r.width == 1920 && r.height == 1080) return l.montageResolutionLabel1080;
    if (r.width == 3840 && r.height == 2160) return l.montageResolutionLabel4K;
    return l.montageResolutionCustom(r.width, r.height);
  }

  String _codecLabel(AppLocalizations l, String c) => c == 'hevc' ? l.montageCodecHevc : l.montageCodecH264;

  String _containerLabel(AppLocalizations l, String c) => c == 'mov' ? l.montageContainerMov : l.montageContainerMp4;

  Widget _pickerRow(String title, Widget picker) => Padding(
        padding: const EdgeInsets.only(top: TfSpace.s6),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                title,
                style: TfText.body(13).copyWith(color: TfColors.text2, decoration: TextDecoration.none),
              ),
            ),
            picker,
          ],
        ),
      );

  Widget _check(String label, bool value, ValueChanged<bool>? onChanged, {Key? key, String? help}) {
    Widget w = TfCheckbox(key: key, value: value, onChanged: onChanged, label: label);
    if (help != null) w = TfTooltip(message: help, child: w);
    return Padding(padding: const EdgeInsets.only(top: TfSpace.s6), child: w);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final MontageState st = ref.watch(montageStoreProvider);
    final MontageSnapshot? snap = st.snapshot;
    if (snap == null) return const SizedBox.shrink();
    final MontageStore store = ref.read(montageStoreProvider.notifier);
    final AppLocalizations l = AppLocalizations.of(context);
    final MontageExportInfo ex = snap.export;
    final bool idle = !st.exportRunning;
    final MontageExportOptions opts = ex.options;

    final List<MontageResolutionInfo> resolutions = <MontageResolutionInfo>[
      ...opts.resolutions,
      if (!opts.resolutions.any((r) => r.width == ex.resolution.width && r.height == ex.resolution.height)) ex.resolution,
    ];
    final List<double> fpsList = <double>{...opts.fps, ex.fps}.toList()..sort();

    ValueChanged<T>? on<T>(void Function(T) f) => idle ? f : null;

    final Widget title = Row(
      children: <Widget>[
        Text(
          l.montageExportSection,
          style: TfText.display(18).copyWith(color: TfColors.text, decoration: TextDecoration.none),
        ),
        const SizedBox(width: TfSpace.s6),
        MontageTransitionsButton(anticipation: snap.anticipationLabel),
      ],
    );

    return TfCard(
      child: SizedBox(
        width: double.infinity,
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: TfSpace.s18, vertical: TfSpace.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                title,
                if (st.formatVisible)
                  _pickerRow(
                    l.montageFormat,
                    TfDropdown<String>(
                      key: const ValueKey<String>('montage-codec'),
                      items: <TfDropdownItem<String>>[
                        for (final String c in opts.codecs) TfDropdownItem<String>(value: c, label: _codecLabel(l, c)),
                      ],
                      value: ex.codec,
                      onChanged: on<String>((String v) => store.setExport(codec: v)),
                    ),
                  ),
                _pickerRow(
                  l.montageContainer,
                  TfDropdown<String>(
                    key: const ValueKey<String>('montage-container'),
                    items: <TfDropdownItem<String>>[
                      for (final String c in opts.containers) TfDropdownItem<String>(value: c, label: _containerLabel(l, c)),
                    ],
                    value: ex.container,
                    onChanged: on<String>((String v) => store.setExport(container: v)),
                  ),
                ),
                _pickerRow(
                  l.montageResolution,
                  TfDropdown<String>(
                    key: const ValueKey<String>('montage-resolution'),
                    items: <TfDropdownItem<String>>[
                      for (final MontageResolutionInfo r in resolutions)
                        TfDropdownItem<String>(value: _resKey(r.width, r.height), label: _resolutionLabel(l, r)),
                    ],
                    value: _resKey(ex.resolution.width, ex.resolution.height),
                    onChanged: on<String>((String v) {
                      final MontageResolutionInfo r = resolutions.firstWhere((r) => _resKey(r.width, r.height) == v);
                      store.setExport(resolution: r);
                    }),
                  ),
                ),
                _pickerRow(
                  l.montageFrames,
                  TfDropdown<double>(
                    key: const ValueKey<String>('montage-fps'),
                    items: <TfDropdownItem<double>>[
                      for (final double f in fpsList) TfDropdownItem<double>(value: f, label: l.montageFpsLabel(f)),
                    ],
                    value: ex.fps,
                    onChanged: on<double>((double v) => store.setExport(fps: v)),
                  ),
                ),
                _check(l.montageNormalize, ex.normalize, idle ? (v) => store.setExport(normalize: v) : null,
                    key: const ValueKey<String>('montage-normalize')),
                _check(l.montageLimiter, ex.limiter, idle && ex.normalize ? (v) => store.setExport(limiter: v) : null,
                    key: const ValueKey<String>('montage-limiter')),
                _check(l.montageCaption, snap.caption, idle ? store.setCaption : null,
                    key: const ValueKey<String>('montage-caption')),
                _check(l.montagePartNames, snap.showPartLabels, idle ? store.setShowPartLabels : null,
                    key: const ValueKey<String>('montage-part-names')),
                _check(
                  l.montageKeepAspect,
                  snap.keepVideoAspect,
                  idle && st.keepAspectApplies ? store.setKeepVideoAspect : null,
                  key: const ValueKey<String>('montage-keep-aspect'),
                  help: st.keepAspectApplies ? null : l.montageKeepAspectHelp,
                ),
                _check(l.montageCutGapsToggle, snap.cutGaps, idle ? store.setCutGaps : null,
                    key: const ValueKey<String>('montage-cut-gaps')),
                _check(l.montageTrackWAVs, ex.trackWAVs, idle ? (v) => store.setExport(trackWAVs: v) : null,
                    key: const ValueKey<String>('montage-track-wavs')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
