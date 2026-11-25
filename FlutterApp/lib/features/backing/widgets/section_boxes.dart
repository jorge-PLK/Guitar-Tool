import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/study.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/features/backing/widgets/chord_grid_geometry.dart';
import 'package:toneforge/features/backing/widgets/chord_grid_painter.dart';
import 'package:toneforge/features/backing/widgets/chord_strip.dart';
import 'package:toneforge/features/backing/widgets/section_boxes_geometry.dart';
import 'package:toneforge/features/backing/widgets/section_boxes_painter.dart';
import 'package:toneforge/features/backing/widgets/section_edge_drag.dart';
import 'package:toneforge/features/backing/widgets/section_edge_handles.dart';
import 'package:toneforge/features/backing/widgets/section_menu.dart';
import 'package:toneforge/features/backing/widgets/section_popover.dart';
import 'package:toneforge/features/backing/widgets/section_popover_state.dart';
import 'package:toneforge/features/backing/widgets/section_selection.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_menu.dart';
import 'package:toneforge/widgets/tf_popover.dart';

// TOKEN: sectionIconSize 10 (SB:76)
const double _iconSize = 10;
// TOKEN: sectionLabelSize 12 (SB:76)
const double _labelSize = 12;
// TOKEN: loopSameTime 0.01 s (SectionEditor.sameTime, ficha §6.3)
const double _sameTime = 0.01;

/// SLOT de [ChordStrip.sectionsLayer]: cajas de sección sobre la tira (SB:191-265).
Widget stripSectionBoxes(BuildContext context, ChordStripLayout layout) =>
    StripSectionBoxes(layout: layout);

/// SLOT de [ChordGrid.sectionsLayer]: cajas de sección sobre la rejilla (SG:9-108).
Widget gridSectionBoxes(BuildContext context, ChordGridGeometry geometry) =>
    GridSectionBoxes(geometry: geometry);

/// Capa de cajas de la tira.
class StripSectionBoxes extends ConsumerWidget {
  const StripSectionBoxes({required this.layout, super.key});

  final ChordStripLayout layout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final StudyAnalysisInfo? a = ref.watch(
      studyStoreProvider.select((s) => s.study?.analysis),
    );
    final List<StudySectionInfo> sections =
        ref.watch(sectionEdgePreviewProvider) ??
        ref.watch(
          studyStoreProvider.select(
            (s) => s.study?.sections ?? const <StudySectionInfo>[],
          ),
        );
    if (a == null) return const SizedBox.shrink();
    return SectionBoxesLayer(
      placements: SectionBoxesGeometry.strip(sections, a.chords, layout),
      mapper: StripEdgeMapper(chords: a.chords, layout: layout),
    );
  }
}

/// Capa de cajas de la rejilla (una por fila ocupada).
class GridSectionBoxes extends ConsumerStatefulWidget {
  const GridSectionBoxes({required this.geometry, super.key});

  final ChordGridGeometry geometry;

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
    final StudyAnalysisInfo? a = ref.watch(
      studyStoreProvider.select((s) => s.study?.analysis),
    );
    final List<StudySectionInfo> sections =
        ref.watch(sectionEdgePreviewProvider) ??
        ref.watch(
          studyStoreProvider.select(
            (s) => s.study?.sections ?? const <StudySectionInfo>[],
          ),
        );
    if (a == null) return const SizedBox.shrink();
    if (!identical(a, _analysis)) {
      _analysis = a;
      _layout = ChordGridLayout.build(
        beats: a.beats,
        downbeats: a.downbeats,
        bpm: a.bpm,
        chords: a.chords,
      );
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
      mapper: GridEdgeMapper(rows: _rows, geometry: widget.geometry),
    );
  }
}

/// Pinta los trozos ya colocados y gestiona la selección por clic en la cabecera (SB:96).
class SectionBoxesLayer extends ConsumerWidget {
  const SectionBoxesLayer({required this.placements, this.mapper, super.key});

  final List<SectionPlacement> placements;

  /// Posición → tiempo para las asas de borde; sin él no hay asas.
  final EdgeTimeMapper? mapper;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? selected = ref.watch(sectionSelectionProvider);
    final StudyLoop? loop = ref.watch(
      studyStoreProvider.select((s) => s.study?.transport.loop),
    );
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
              loopActive:
                  loop != null &&
                  (loop.start - placements[i].section.start).abs() <
                      _sameTime &&
                  (loop.end - placements[i].section.end).abs() < _sameTime,
            ),
          ),
        if (mapper != null && selected != null)
          ...sectionEdgeHandles(
            pieces: <SectionPlacement>[
              for (final SectionPlacement p in placements)
                if (p.section.id == selected) p,
            ],
            mapper: mapper!,
          ),
      ],
    );
  }
}

class _SectionBox extends ConsumerStatefulWidget {
  const _SectionBox({
    required this.placement,
    required this.selected,
    required this.loopActive,
  });

  final SectionPlacement placement;
  final bool selected;
  final bool loopActive;

  @override
  ConsumerState<_SectionBox> createState() => _SectionBoxState();
}

class _SectionBoxState extends ConsumerState<_SectionBox> {
  final TfPopoverController _pop = TfPopoverController();

  /// Sincroniza la hoja con `sectionPopoverProvider` (una a la vez; solo el primer trozo la ancla).
  void _syncPopover(bool open) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (open && !_pop.isShowing) _pop.show();
      if (!open && _pop.isShowing) _pop.hide();
    });
  }

  void _open() {
    final String id = widget.placement.section.id;
    ref.read(sectionSelectionProvider.notifier).select(id);
    ref.read(sectionPopoverProvider.notifier).open(id);
  }

  @override
  Widget build(BuildContext context) {
    final SectionPlacement placement = widget.placement;
    final bool selected = widget.selected;
    final bool loopActive = widget.loopActive;
    final StudySectionInfo s = placement.section;
    final bool open =
        placement.labeled && ref.watch(sectionPopoverProvider) == s.id;
    _syncPopover(open);
    final Color color = sectionColor(
      solo: s.solo,
      paletteIndex: s.paletteIndex ?? placement.index,
    );
    final Color ink = s.solo ? TfColors.accent : color;
    final Widget icon = TfIconView(
      TfIcon.guitarsFill,
      size: _iconSize,
      color: ink,
    );
    final TextStyle nameStyle = TfText.body(
      _labelSize,
      TfWeight.semibold,
    ).copyWith(color: ink);
    final Widget name = Text(
      s.name,
      maxLines: 1,
      softWrap: false,
      style: nameStyle,
    );
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
          child: _header(s, ink, icon, nameStyle, name),
        ),
      ],
    );
  }

  Widget _header(
    StudySectionInfo s,
    Color ink,
    Widget icon,
    TextStyle nameStyle,
    Widget name,
  ) {
    final SectionPlacement placement = widget.placement;
    final Widget box = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _open,
        onLongPress: () => toggleSectionLoop(ref, s, sameTime: _sameTime),
        child: !placement.labeled
            ? const SizedBox.expand()
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: TfSpace.s8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  // Como `ViewThatFits`: nombre con icono, solo el icono (si es solo) o nada.
                  child: LayoutBuilder(
                    builder: (BuildContext context, BoxConstraints c) {
                      final double text = (TextPainter(
                        text: TextSpan(text: s.name, style: nameStyle),
                        maxLines: 1,
                        textDirection: TextDirection.ltr,
                      )..layout()).width;
                      final double full =
                          text + (s.solo ? _iconSize + TfSpace.s4 : 0);
                      if (full <= c.maxWidth) {
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          spacing: TfSpace.s4,
                          children: <Widget>[if (s.solo) icon, name],
                        );
                      }
                      return s.solo && _iconSize <= c.maxWidth
                          ? icon
                          : const SizedBox.shrink();
                    },
                  ),
                ),
              ),
      ),
    );
    final Widget anchored = placement.labeled
        ? TfPopover(
            controller: _pop,
            onClosed: ref.read(sectionPopoverProvider.notifier).close,
            popoverBuilder: (BuildContext _) => SectionPopover(sectionId: s.id),
            child: box,
          )
        : box;
    return TfContextMenu(
      entries: sectionMenuEntries(ref, s, AppLocalizations.of(context)),
      child: anchored,
    );
  }
}
