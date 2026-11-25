import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/study.dart';
import 'package:toneforge/features/backing/study_position.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/features/backing/widgets/chord_editor_grid.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_divider.dart';
import 'package:toneforge/widgets/tf_tooltip.dart';

/// Hoja «Acorde» (`ChordEditor`, BackingTimeline.swift:480-557) del tramo [start]...[end]. [time] = punto de
/// partida (celda de la rejilla); sin él, la posición de reproducción. No se cierra al elegir.
class ChordEditor extends ConsumerStatefulWidget {
  const ChordEditor({super.key, required this.start, required this.end, this.time});

  /// Margen respecto a los extremos para poder partir (BT:509).
  static const double splitMargin = 0.05;

  final double start;
  final double end;
  final double? time;

  @override
  ConsumerState<ChordEditor> createState() => _ChordEditorState();
}

class _ChordEditorState extends ConsumerState<ChordEditor> {
  int? _root;
  int? _quality;
  late final int _initialIndex;

  @override
  void initState() {
    super.initState();
    final StudyOpenResult? study = ref.read(studyStoreProvider).study;
    final Iterable<StudyChord> hit =
        (study?.analysis.chords ?? const <StudyChord>[]).where((StudyChord c) => c.start == widget.start);
    _initialIndex = hit.isEmpty ? -1 : hit.first.index;
    if (_initialIndex >= 0 && _initialIndex < chordRootNames.length * chordQualityCount) {
      _root = _initialIndex ~/ chordQualityCount;
      _quality = _initialIndex % chordQualityCount;
    }
  }

  StudyStore get _store => ref.read(studyStoreProvider.notifier);

  void _commit() {
    final int? r = _root, q = _quality;
    if (r == null || q == null) return;
    _store.setChord(widget.start, widget.end, index: r * chordQualityCount + q);
  }

  /// Pulso más cercano al punto, si queda a más de 0,05 s de ambos extremos (BT:506-510).
  double? _splitBeat(List<double> beats, double time) {
    if (!(time > widget.start && time < widget.end) || beats.isEmpty) return null;
    double best = beats.first;
    for (final double b in beats) {
      if ((b - time).abs() < (best - time).abs()) best = b;
    }
    return best > widget.start + ChordEditor.splitMargin && best < widget.end - ChordEditor.splitMargin ? best : null;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final StudyOpenResult? study = ref.watch(studyStoreProvider.select((s) => s.study));
    final double seconds = widget.time ?? ref.watch(studyPositionProvider.select((p) => p.seconds));
    final double? beat = _splitBeat(study?.analysis.beats ?? const <double>[], seconds);
    final bool hasOverride = (study?.chordOverrides ?? const <StudyOverrideInfo>[])
        .any((StudyOverrideInfo o) => o.start < widget.end && o.end > widget.start);
    return Padding(
      padding: const EdgeInsets.all(TfSpace.s16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l.backing_chordSheetTitle, style: TfText.display(16).copyWith(color: TfColors.text)),
          const SizedBox(height: TfSpace.s12),
          ChordEditorGrid(
            cell: TfSize.controlLg,
            columns: 6,
            children: <Widget>[
              for (int r = 0; r < chordRootNames.length; r++)
                ChordEditorChip(
                  text: chordRootNames[r],
                  on: _root == r,
                  onTap: () {
                    setState(() => _root = r);
                    _commit();
                  },
                ),
            ],
          ),
          const SizedBox(height: TfSpace.s12),
          ChordEditorGrid(
            cell: TfSize.controlLg + TfSpace.s16,
            columns: 4,
            children: <Widget>[
              for (int q = 0; q < chordQualitySuffixes.length; q++)
                ChordEditorChip(
                  text: chordQualitySuffixes[q].isEmpty ? l.backing_chordMajor : chordQualitySuffixes[q],
                  on: _quality == q,
                  onTap: () {
                    setState(() => _quality = q);
                    _commit();
                  },
                ),
            ],
          ),
          const SizedBox(height: TfSpace.s12),
          ChordEditorChip(
            text: l.backing_chordNone,
            on: _initialIndex == chordNoChordIndex,
            onTap: () => _store.setChord(widget.start, widget.end, index: chordNoChordIndex),
          ),
          const SizedBox(height: TfSpace.s12),
          const SizedBox(width: TfSize.controlLg * 6 + TfSpace.s6 * 5, child: TfDivider()),
          const SizedBox(height: TfSpace.s12),
          SizedBox(
            width: TfSize.controlLg * 6 + TfSpace.s6 * 5,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                TfTooltip(
                  message: l.backing_chordSplitTooltip,
                  child: TfSecondaryButton(
                    label: l.backing_chordSplit,
                    height: TfSize.controlMd,
                    onPressed: beat == null ? null : () => _store.splitChord(beat),
                  ),
                ),
                TfSecondaryButton(
                  label: l.backing_chordRemoveOverride,
                  height: TfSize.controlMd,
                  onPressed: hasOverride ? () => _store.removeChordOverrides(widget.start, widget.end) : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
