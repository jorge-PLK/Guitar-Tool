import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/study.dart';
import 'package:toneforge/features/backing/widgets/chord_grid_geometry.dart';
import 'package:toneforge/features/backing/widgets/chord_grid_painter.dart';
import 'package:toneforge/features/backing/widgets/chord_strip.dart';

/// Vista previa del borde en arrastre (`study.previewSectionEdge`); las cajas se pintan con `preview ?? sections`.
final NotifierProvider<SectionEdgePreview, List<StudySectionInfo>?> sectionEdgePreviewProvider =
    NotifierProvider<SectionEdgePreview, List<StudySectionInfo>?>(SectionEdgePreview.new);

class SectionEdgePreview extends Notifier<List<StudySectionInfo>?> {
  @override
  List<StudySectionInfo>? build() => null;

  void set(List<StudySectionInfo> sections) => state = sections;

  void clear() => state = null;
}

/// Posición (en coordenadas de la capa de cajas) → tiempo en segundos. Geometría de presentación;
/// el imán lo calcula el núcleo (SectionEdgeDrag.swift:66-80).
abstract interface class EdgeTimeMapper {
  double? timeAt(Offset p);
}

/// Tira: acorde bajo la x (en un hueco, el más cercano) e interpolación dentro de su marco.
class StripEdgeMapper implements EdgeTimeMapper {
  const StripEdgeMapper({required this.chords, required this.layout});

  final List<StudyChord> chords;
  final ChordStripLayout layout;

  @override
  double? timeAt(Offset p) {
    final int n = math.min(chords.length, layout.rects.length);
    final int? i = layout.indexAt(p.dx);
    if (n == 0 || i == null || i >= n) return null;
    final Rect r = layout.rects[i];
    final StudyChord c = chords[i];
    final double k = r.width <= 0 ? 0 : ((p.dx - r.left) / r.width).clamp(0.0, 1.0);
    return c.start + (c.end - c.start) * k;
  }
}

/// Rejilla: fila cuya franja vertical contiene la y (si no, la más cercana); en ella, la celda bajo la x
/// (en un hueco, la más cercana) e interpolación dentro de la celda.
class GridEdgeMapper implements EdgeTimeMapper {
  const GridEdgeMapper({required this.rows, required this.geometry});

  final List<List<GridBar>> rows;
  final ChordGridGeometry geometry;

  @override
  double? timeAt(Offset p) {
    int? row;
    double best = double.infinity;
    for (int r = 0; r < rows.length; r++) {
      if (rows[r].isEmpty) continue;
      final double top = r * ChordGridGeometry.rowPitch;
      final double bottom = top + ChordGridGeometry.sectionGutter + ChordGridGeometry.rowHeight;
      final double d = p.dy < top ? top - p.dy : (p.dy > bottom ? p.dy - bottom : 0);
      if (d < best) {
        best = d;
        row = r;
      }
    }
    if (row == null) return null;
    GridBeat? cell;
    Rect? rect;
    double bestX = double.infinity;
    for (int c = 0; c < rows[row].length; c++) {
      final List<GridBeat> cells = rows[row][c].cells;
      for (int b = 0; b < cells.length; b++) {
        final Rect r = geometry.cellRect(row, c, b, cells.length);
        final double d = p.dx < r.left ? r.left - p.dx : (p.dx > r.right ? p.dx - r.right : 0);
        if (d < bestX) {
          bestX = d;
          cell = cells[b];
          rect = r;
        }
      }
    }
    if (cell == null || rect == null) return null;
    final double k = rect.width <= 0 ? 0 : ((p.dx - rect.left) / rect.width).clamp(0.0, 1.0);
    return cell.time + (cell.end - cell.time) * k;
  }
}

typedef EdgePreviewCall = Future<List<StudySectionInfo>?> Function(StudyPreviewSectionEdgeParams p);
typedef EdgeCommitCall = Future<void> Function(StudyUpdateSectionParams p);

/// Un arrastre de borde (SectionEdgeDrag.swift). Una sola llamada de vista previa en vuelo; vale la última
/// posición. Al soltar, `updateSection` y se limpia la vista previa; al cancelar, solo se limpia.
class SectionEdgeDragController {
  SectionEdgeDragController({
    required this.id,
    required this.isStart,
    required this.mapper,
    required this.anchor,
    required this.grab,
    required this.preview,
    required this.commit,
    required this.onPreview,
    required this.onClear,
  });

  final String id;
  final bool isStart;
  final EdgeTimeMapper mapper;

  /// Donde está dibujado el borde al empezar; el puntero se mide desde aquí, no desde el punto de agarre.
  final Offset anchor;
  final Offset grab;
  final EdgePreviewCall preview;
  final EdgeCommitCall commit;
  final void Function(List<StudySectionInfo> sections) onPreview;
  final void Function() onClear;

  bool _inFlight = false;
  bool _closed = false;
  ({double to, StudySnap snap})? _latest;
  ({double to, StudySnap snap})? _sent;

  ({double to, StudySnap snap})? _target(Offset location, bool bar) {
    final double? to = mapper.timeAt(anchor + (location - grab));
    return to == null ? null : (to: to, snap: bar ? StudySnap.bar : StudySnap.chord);
  }

  void update(Offset location, {required bool bar}) {
    if (_closed) return;
    _latest = _target(location, bar);
    unawaited(_pump());
  }

  Future<void> _pump() async {
    if (_inFlight) return;
    final ({double to, StudySnap snap})? t = _latest;
    if (t == null || t == _sent) return;
    _inFlight = true;
    _sent = t;
    List<StudySectionInfo>? sections;
    try {
      sections = await preview(StudyPreviewSectionEdgeParams(id: id, start: isStart, to: t.to, snap: t.snap));
    } catch (_) {
      sections = null;
    }
    _inFlight = false;
    if (_closed) return;
    if (sections != null) onPreview(sections);
    unawaited(_pump());
  }

  /// Suelta en [location]: una final con `updateSection`.
  Future<void> end(Offset location, {required bool bar}) async {
    if (_closed) return;
    _closed = true;
    final ({double to, StudySnap snap})? t = _target(location, bar) ?? _latest;
    try {
      if (t != null) {
        await commit(StudyUpdateSectionParams(
          id: id,
          start: isStart ? t.to : null,
          end: isStart ? null : t.to,
          snap: t.snap,
        ));
      }
    } finally {
      onClear();
    }
  }

  /// El sistema cancela el gesto: se descarta la vista previa sin llamar.
  void cancel() {
    if (_closed) return;
    _closed = true;
    onClear();
  }
}
