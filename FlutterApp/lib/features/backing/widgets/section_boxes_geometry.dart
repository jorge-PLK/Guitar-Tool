import 'dart:math' as math;
import 'dart:ui';

import 'package:toneforge/contract/study.dart';
import 'package:toneforge/features/backing/widgets/chord_grid_geometry.dart';
import 'package:toneforge/features/backing/widgets/chord_grid_painter.dart';
import 'package:toneforge/features/backing/widgets/chord_strip.dart';

/// Un trozo de caja de sección ya colocado: la tira tiene uno por sección; la rejilla, uno por fila ocupada.
class SectionPlacement {
  const SectionPlacement({
    required this.section,
    required this.index,
    required this.rect,
    required this.headerHeight,
    required this.labeled,
  });

  final StudySectionInfo section;

  /// Posición de la sección en `analysis.sections` (color por defecto).
  final int index;
  final Rect rect;
  final double headerHeight;

  /// Solo el primer trozo lleva nombre.
  final bool labeled;
}

/// Geometría de las cajas de sección (SB:35-120; ficha backing §2.3). Funciones puras.
abstract final class SectionBoxesGeometry {
  /// `SectionBoxes.headerHeight` de la tira (= `ChordStripLayout.topGap`).
  static const double stripHeader = ChordStripLayout.topGap;

  /// `inset`: lo que la caja sobresale de las celdas.
  static const double inset = 2;

  /// Ancho mínimo de una caja en la tira (SB:254).
  static const double minWidth = 8;

  /// Tira (SB:191-265): la caja sigue los marcos de los chips.
  static List<SectionPlacement> strip(
    List<StudySectionInfo> sections,
    List<StudyChord> chords,
    ChordStripLayout layout,
  ) {
    final int n = math.min(chords.length, layout.rects.length);
    if (n == 0) return const <SectionPlacement>[];
    final double first = chords.first.start;
    final double last = chords[n - 1].end;
    final double top = layout.rects.first.top;
    final double chipsBottom = layout.rects.map((Rect r) => r.bottom).reduce(math.max);
    double? startX(double t) {
      for (int i = 0; i < n; i++) {
        if (chords[i].end > t) return _lerp(chords[i], layout.rects[i], t);
      }
      return null;
    }

    double? endX(double t) {
      for (int i = n - 1; i >= 0; i--) {
        if (chords[i].start < t) return _lerp(chords[i], layout.rects[i], t);
      }
      return null;
    }

    final List<SectionPlacement> out = <SectionPlacement>[];
    for (int i = 0; i < sections.length; i++) {
      final StudySectionInfo s = sections[i];
      if (!(s.end > first && s.start < last)) continue;
      final double? a = startX(s.start), b = endX(s.end);
      if (a == null || b == null) continue;
      final double x0 = a - inset;
      final double x1 = math.max(b + inset, x0 + minWidth);
      out.add(SectionPlacement(
        section: s,
        index: i,
        rect: Rect.fromLTRB(x0, top - ChordStripLayout.chipTop, x1, chipsBottom + inset),
        headerHeight: stripHeader,
        labeled: true,
      ));
    }
    return out;
  }

  static double _lerp(StudyChord c, Rect r, double t) {
    final double span = c.end - c.start;
    final double k = span <= 0 ? 0 : ((t - c.start) / span).clamp(0.0, 1.0);
    return r.left + r.width * k;
  }

  /// Rejilla (SG:9-108): una caja por fila con celdas cuyo punto medio cae en `[inicio, fin)`.
  static List<SectionPlacement> grid(
    List<StudySectionInfo> sections,
    List<List<GridBar>> rows,
    ChordGridGeometry g,
  ) {
    final List<SectionPlacement> out = <SectionPlacement>[];
    for (int i = 0; i < sections.length; i++) {
      final StudySectionInfo s = sections[i];
      bool labeled = true;
      for (int r = 0; r < rows.length; r++) {
        double? minX, maxX;
        for (int c = 0; c < rows[r].length; c++) {
          final List<GridBeat> cells = rows[r][c].cells;
          for (int b = 0; b < cells.length; b++) {
            final double mid = (cells[b].time + cells[b].end) / 2;
            if (mid < s.start || mid >= s.end) continue;
            final Rect cell = g.cellRect(r, c, b, cells.length);
            minX = minX == null ? cell.left : math.min(minX, cell.left);
            maxX = maxX == null ? cell.right : math.max(maxX, cell.right);
          }
        }
        if (minX == null || maxX == null) continue;
        out.add(SectionPlacement(
          section: s,
          index: i,
          rect: Rect.fromLTWH(
            minX - inset,
            r * ChordGridGeometry.rowPitch,
            maxX - minX + 2 * inset,
            ChordGridGeometry.sectionGutter + ChordGridGeometry.rowHeight + inset,
          ),
          headerHeight: ChordGridGeometry.sectionGutter,
          labeled: labeled,
        ));
        labeled = false;
      }
    }
    return out;
  }
}
