import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/study.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/features/backing/widgets/chord_grid_geometry.dart';
import 'package:toneforge/features/backing/widgets/chord_grid_painter.dart';
import 'package:toneforge/features/backing/widgets/chord_strip.dart';
import 'package:toneforge/features/backing/widgets/section_boxes_geometry.dart';
import 'package:toneforge/features/backing/widgets/section_boxes_painter.dart';
import 'package:toneforge/features/backing/widgets/section_selection.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';

// TOKEN: sectionIconSize 10 (SB:76)
const double _iconSize = 10;
// TOKEN: sectionLabelSize 12 (SB:76)
const double _labelSize = 12;
// TOKEN: loopSameTime 0.01 s (SectionEditor.sameTime, ficha §6.3)
const double _sameTime = 0.01;

/// SLOT de [ChordStrip.sectionsLayer]: cajas de sección sobre la tira (SB:191-265).
Widget stripSectionBoxes(BuildContext context, ChordStripLayout layout) => StripSectionBoxes(layout: layout);

/// SLOT de [ChordGrid.sectionsLayer]: cajas de sección sobre la rejilla (SG:9-108).
Widget gridSectionBoxes(BuildContext context, ChordGridGeometry geometry) => GridSectionBoxes(geometry: geometry);

/// Capa de cajas de la tira. [onOpenSection] (hoja «Sección / Solo») no está implementado aún: opcional.
class StripSectionBoxes extends ConsumerWidget {
  const StripSectionBoxes({required this.layout, this.onOpenSection, super.key});

  final ChordStripLayout layout;
  final void Function(String id)? onOpenSection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final StudyAnalysisInfo? a = ref.watch(studyStoreProvider.select((s) => s.study?.analysis));
    final List<StudySectionInfo> sections =
        ref.watch(studyStoreProvider.select((s) => s.study?.sections ?? const <StudySectionInfo>[]));
    if (a == null) return const SizedBox.shrink();
    return SectionBoxesLayer(
      placements: SectionBoxesGeometry.strip(sections, a.chords, layout),
      onOpenSection: onOpenSection,
    );
  }
}

/// Capa de cajas de la rejilla (una por fila ocupada).
class GridSectionBoxes extends ConsumerStatefulWidget {
  const GridSectionBoxes({required this.geometry, this.onOpenSection, super.key});

  final ChordGridGeometry geometry;
  final void Function(String id)? onOpenSection;

  @override
  ConsumerState<GridSectionBoxes> createState() => _GridSectionBoxesState();
}

class _GridSectionBoxesState extends ConsumerState<GridSectionBoxes> {
  StudyAnalysisInfo? _analysis;
  ChordGridLayout? _layout;
  int _perRow = 0;
  List<List<GridBar>> _rows = const <List<GridBar>>[];

  @override
  Widget build(BuildContext context) {
    final StudyAnalysisInfo? a = ref.watch(studyStoreProvider.select((s) => s.study?.analysis));
    final List<StudySectionInfo> sections =
        ref.watch(studyStoreProvider.select((s) => s.study?.sections ?? const <StudySectionInfo>[]));
    if (a == null) return const SizedBox.shrink();
    if (!identical(a, _analysis)) {
      _analysis = a;
      _layout = ChordGridLayout.build(beats: a.beats, downbeats: a.downbeats, bpm: a.bpm, chords: a.chords);
      _perRow = 0;
    }
    final ChordGridLayout? layout = _layout;
    if (layout == null) return const SizedBox.shrink();
    if (_perRow != widget.geometry.perRow) {
      _perRow = widget.geometry.perRow;
      _rows = layout.rows(_perRow);
    }
    return SectionBoxesLayer(
      placements: SectionBoxesGeometry.grid(sections, _rows, widget.geometry),
      onOpenSection: widget.onOpenSection,
    );
  }
}

/// Pinta los trozos ya colocados y gestiona la selección por clic en la cabecera (SB:96).
class SectionBoxesLayer extends ConsumerWidget {
  const SectionBoxesLayer({required this.placements, this.onOpenSection, super.key});

  final List<SectionPlacement> placements;
  final void Function(String id)? onOpenSection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? selected = ref.watch(sectionSelectionProvider);
    final StudyLoop? loop = ref.watch(studyStoreProvider.select((s) => s.study?.transport.loop));
    final SectionSelectionNotifier selection = ref.read(sectionSelectionProvider.notifier);
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        for (int i = 0; i < placements.length; i++)
          Positioned.fromRect(
            key: ValueKey<String>('section-box-${placements[i].section.id}-$i'),
            rect: placements[i].rect,
            child: _SectionBox(
              placement: placements[i],
              selected: placements[i].section.id == selected,
              loopActive: loop != null &&
                  (loop.start - placements[i].section.start).abs() < _sameTime &&
                  (loop.end - placements[i].section.end).abs() < _sameTime,
              onTap: () {
                selection.select(placements[i].section.id);
                onOpenSection?.call(placements[i].section.id);
              },
            ),
          ),
      ],
    );
  }
}

class _SectionBox extends StatelessWidget {
  const _SectionBox({
    required this.placement,
    required this.selected,
    required this.loopActive,
    required this.onTap,
  });

  final SectionPlacement placement;
  final bool selected;
  final bool loopActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final StudySectionInfo s = placement.section;
    final Color color = sectionColor(solo: s.solo, paletteIndex: s.paletteIndex ?? placement.index);
    final Color ink = s.solo ? TfColors.accent : color;
    final Widget icon = TfIconView(TfIcon.guitarsFill, size: _iconSize, color: ink);
    final TextStyle nameStyle = TfText.body(_labelSize, TfWeight.semibold).copyWith(color: ink);
    final Widget name = Text(s.name, maxLines: 1, softWrap: false, style: nameStyle);
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: SectionBoxPainter(
                color: color,
                solo: s.solo,
                selected: selected,
                loopActive: loopActive,
                headerHeight: placement.headerHeight,
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          right: 0,
          height: placement.headerHeight,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: !placement.labeled
                  ? const SizedBox.expand()
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: TfSpace.s8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        // Como `ViewThatFits`: nombre con icono, solo el icono (si es solo) o nada.
                        child: LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
                          final double text = (TextPainter(
                            text: TextSpan(text: s.name, style: nameStyle),
                            maxLines: 1,
                            textDirection: TextDirection.ltr,
                          )..layout())
                              .width;
                          final double full = text + (s.solo ? _iconSize + TfSpace.s4 : 0);
                          if (full <= c.maxWidth) {
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              spacing: TfSpace.s4,
                              children: <Widget>[if (s.solo) icon, name],
                            );
                          }
                          return s.solo && _iconSize <= c.maxWidth ? icon : const SizedBox.shrink();
                        }),
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
