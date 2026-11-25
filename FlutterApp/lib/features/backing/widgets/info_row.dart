import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/study.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_dropdown.dart';
import 'package:toneforge/widgets/tf_menu.dart';
import 'package:toneforge/widgets/tf_slider.dart';

// Medidas de BackingTimeline.swift:342-385 sin token propio.
const double _flowSpacing = 10;
const double _chevronSize = 10;

const List<String> _tonics = <String>['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

/// Fila de info (BT:342-385): tempo detectado, tonalidad, transponer, capo y afinación fina.
class InfoRow extends ConsumerWidget {
  const InfoRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final study = ref.watch(studyStoreProvider.select((s) => s.study));
    final StudyStore store = ref.read(studyStoreProvider.notifier);
    final analysis = study?.analysis;
    final t = study?.transport;
    final double? bpm = analysis?.bpm;
    final TextStyle strong = TfText.body(TfSize.font13, TfWeight.semibold).copyWith(color: TfColors.text);
    return SizedBox(
      width: double.infinity,
      child: DefaultTextStyle(
        style: TfText.body(TfSize.font13).copyWith(color: TfColors.text2),
        child: Wrap(
          spacing: _flowSpacing,
          runSpacing: _flowSpacing,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
              Text('${l.backing_tempoDetected}:'),
              const SizedBox(width: TfSpace.s4),
              Text(bpm == null ? '—' : l.backing_bpm(bpm.round()), style: strong),
            ]),
            _keyMenu(l, store, analysis, strong),
            _labeled(
              l.backing_transpose,
              TfDropdown<int>(
                width: TfSize.infoPickerWidth,
                value: t?.transpose ?? 0,
                items: <TfDropdownItem<int>>[
                  for (int n = -12; n <= 12; n++)
                    TfDropdownItem<int>(
                      value: n,
                      label: n == 0 ? l.backing_transposeZero : (n > 0 ? '+$n' : '$n'),
                    ),
                ],
                onChanged: (int n) => store.setTranspose(semitones: n),
              ),
            ),
            _labeled(
              l.backing_capo,
              TfDropdown<int>(
                width: TfSize.infoPickerWidth,
                value: t?.capo ?? 0,
                items: <TfDropdownItem<int>>[
                  for (int n = 0; n <= 12; n++)
                    TfDropdownItem<int>(value: n, label: n == 0 ? l.backing_capoNone : l.backing_capoFret(n)),
                ],
                onChanged: store.setCapo,
              ),
            ),
            _labeled(
              l.backing_fineTune,
              Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                TfSlider(
                  value: t?.fineCents ?? 0,
                  min: -50,
                  max: 50,
                  step: 1,
                  width: TfSize.infoFineSliderWidth,
                  onChanged: (double v) => store.setTranspose(fineCents: v.roundToDouble()),
                ),
                const SizedBox(width: TfSpace.s6),
                SizedBox(
                  width: TfSize.infoCentsWidth,
                  child: Text(
                    l.backing_cents((t?.fineCents ?? 0).toInt()),
                    style: const TextStyle(fontFeatures: <FontFeature>[FontFeature.tabularFigures()]),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _labeled(String title, Widget child) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[Text(title), const SizedBox(width: TfSpace.s6), child],
      );

  String _keyName(AppLocalizations l, StudyKey key) {
    final StudyShownKey? d = key.display;
    if (d == null) return '—';
    final String note = l.backing_keyNote(d.tonic.replaceAll('#', 's'));
    final String name = d.mode == 'min' ? l.backing_keyMinor(note) : l.backing_keyMajor(note);
    return key.override != null ? '$name ${l.backing_keyCorrected}' : name;
  }

  Widget _keyMenu(AppLocalizations l, StudyStore store, StudyAnalysisInfo? analysis, TextStyle strong) {
    final bool enabled = analysis != null && analysis.state == StudyAnalysisState.ready;
    final StudyKey? key = analysis?.key;
    return Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
      Text(l.backing_key),
      const SizedBox(width: TfSpace.s6),
      TfMenu(
        entries: !enabled
            ? const <TfMenuEntry>[]
            : <TfMenuEntry>[
                for (final String mode in <String>['maj', 'min'])
                  for (final String tonic in _tonics)
                    TfMenuItem(
                      label: _keyName(l, StudyKey(display: StudyShownKey(tonic: tonic, mode: mode))),
                      onSelected: () => store.setKeyShown(StudyShownKey(tonic: tonic, mode: mode)),
                    ),
                if (key?.override != null) ...<TfMenuEntry>[
                  const TfMenuDivider(),
                  TfMenuItem(label: l.backing_keyBackToDetected, onSelected: () => store.setKey(null)),
                ],
              ],
        builder: (BuildContext context, VoidCallback toggle) => Opacity(
          opacity: enabled ? 1 : TfOpacity.disabled,
          child: MouseRegion(
            cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
            child: GestureDetector(
              key: const ValueKey<String>('key_menu'),
              behavior: HitTestBehavior.opaque,
              onTap: enabled ? toggle : null,
              child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                Text(key == null ? '—' : _keyName(l, key), style: strong),
                const SizedBox(width: TfSpace.s4),
                const TfIconView(TfIcon.chevronDown, size: _chevronSize, color: TfColors.text),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}
