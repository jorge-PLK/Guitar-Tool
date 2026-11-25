import 'package:flutter/widgets.dart';
import 'package:toneforge/contract/study.dart';
import 'package:toneforge/features/backing/widgets/chord_grid_geometry.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';

/// Pulso de la rejilla (CG:8-17).
class GridBeat {
  const GridBeat({
    required this.time,
    required this.end,
    required this.chord,
    required this.label,
    required this.name,
    required this.isChange,
  });

  final double time;
  final double end;

  /// Posición en `chords` del tramo que suena en este pulso; null si no hay ninguno.
  final int? chord;

  /// `StudyChord.index` (sin transponer); -1 sin acorde.
  final int label;

  /// Nombre que se ve (transpuesto si el núcleo lo da).
  final String name;
  final bool isChange;

  /// Acorde de verdad (no «?» ni «N»: índices < 168).
  bool get isChord => label >= 0 && label < 168;

  /// El pulso 1 de cada compás lleva siempre el acorde; el resto, solo si cambia (CG:232).
  bool named(bool first) => first || isChange;

  bool contains(double t) => time <= t + ChordGridLayout.eps && t < end;
}

class GridBar {
  const GridBar({required this.number, required this.start, required this.end, required this.cells});

  final int number;
  final double start;
  final double end;
  final List<GridBeat> cells;

  bool contains(double t) => start <= t + ChordGridLayout.eps && t < end;
}

/// Compases y pulsos de la rejilla (CG:7-77). Regla de presentación portada de SwiftUI: el núcleo no la ofrece.
class ChordGridLayout {
  const ChordGridLayout._(this.bars);

  static const double eps = 1e-6;

  /// El acorde de un pulso se toma un poco después del pulso (CG:27).
  static const double probeFraction = 0.35;

  /// Nombre de «sin acorde» cuando ningún tramo cubre el pulso (símbolo de acorde, no texto de interfaz).
  static const String noChordName = 'N';

  final List<GridBar> bars;

  /// Null si no hay rejilla de pulso o ningún compás tiene pulsos.
  static ChordGridLayout? build({
    required List<double> beats,
    required List<double> downbeats,
    required double? bpm,
    required List<StudyChord> chords,
  }) {
    if (beats.isEmpty || downbeats.isEmpty) return null;
    final double beatDur = bpm != null && bpm > 0 ? 60 / bpm : 0.5;
    final List<GridBar> bars = <GridBar>[];
    int j = 0;
    int? previous;
    int pointer = 0;
    for (int n = 0; n < downbeats.length; n++) {
      final double start = downbeats[n];
      final double end = n + 1 < downbeats.length
          ? downbeats[n + 1]
          : (beats.last + beatDur > start + beatDur ? beats.last + beatDur : start + beatDur);
      while (j < beats.length && beats[j] < start - eps) {
        j++;
      }
      final List<double> times = <double>[];
      while (j < beats.length && beats[j] < end - eps) {
        times.add(beats[j++]);
      }
      if (times.isEmpty) continue;
      final List<GridBeat> cells = <GridBeat>[];
      for (int k = 0; k < times.length; k++) {
        final double t = times[k];
        final double e = k + 1 < times.length ? times[k + 1] : end;
        final double probe = t + probeFraction * (e - t);
        while (pointer + 1 < chords.length && chords[pointer + 1].start <= probe) {
          pointer++;
        }
        int? seg;
        if (pointer < chords.length && chords[pointer].start <= probe && probe < chords[pointer].end) {
          seg = pointer;
        }
        final int label = seg == null ? -1 : chords[seg].index;
        final String name = seg == null ? noChordName : (chords[seg].display ?? chords[seg].name);
        cells.add(GridBeat(time: t, end: e, chord: seg, label: label, name: name, isChange: label != previous));
        previous = label;
      }
      bars.add(GridBar(number: n + 1, start: start, end: end, cells: cells));
    }
    return bars.isEmpty ? null : ChordGridLayout._(bars);
  }

  /// Índice del compás que contiene [time] (el primero antes de empezar).
  int barIndexAt(double time) {
    int lo = 0, hi = bars.length - 1;
    while (lo < hi) {
      final int mid = (lo + hi + 1) ~/ 2;
      if (bars[mid].start <= time + eps) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  List<List<GridBar>> rows(int perRow) => <List<GridBar>>[
        for (int i = 0; i < bars.length; i += perRow)
          bars.sublist(i, i + perRow < bars.length ? i + perRow : bars.length),
      ];
}

/// Una celda cuyo punto medio cae dentro del bucle (CG:230).
bool gridCellInLoop(GridBeat c, (double, double)? loop) =>
    loop != null && (c.time + c.end) / 2 >= loop.$1 && (c.time + c.end) / 2 <= loop.$2;

/// Pinta compases, celdas, bucle y pulso actual (CG:216-257). Una sola geometría para pintar y pulsar.
class ChordGridPainter extends CustomPainter {
  ChordGridPainter({
    required this.rows,
    required this.geometry,
    required this.seconds,
    required this.loop,
    required this.barLabel,
  });

  /// Radio de las celdas (CG:240).
  static const double cellRadius = TfRadius.small;

  /// Padding vertical de la celda dentro del compás (`padding v 3`, CG:244).
  static const double cellInsetV = TfSpace.s3;

  /// Alto de la cápsula del pulso actual (CG:242).
  static const double capsuleHeight = TfSpace.s3;

  /// Escala mínima del texto de la celda (CG:237).
  static const double minTextScale = 0.6;

  final List<List<GridBar>> rows;
  final ChordGridGeometry geometry;
  final double seconds;

  /// Bucle activo o vista previa del arrastre (inicio, fin) en segundos.
  final (double, double)? loop;
  final String Function(int number) barLabel;

  @override
  void paint(Canvas canvas, Size size) {
    for (int r = 0; r < rows.length; r++) {
      _label(canvas, r);
      for (int c = 0; c < rows[r].length; c++) {
        _bar(canvas, r, c, rows[r][c]);
      }
    }
  }

  void _label(Canvas canvas, int r) {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: barLabel(rows[r].first.number), style: TfText.body(11).copyWith(color: TfColors.muted)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: ChordGridGeometry.labelWidth - 8);
    final Rect bar = geometry.barRect(r, 0);
    tp.paint(canvas, Offset(0, bar.top + (bar.height - tp.height) / 2));
  }

  void _bar(Canvas canvas, int r, int c, GridBar bar) {
    final bool current = bar.contains(seconds);
    final RRect frame = RRect.fromRectAndRadius(geometry.barRect(r, c), const Radius.circular(TfRadius.field));
    canvas.drawRRect(frame, Paint()..color = current ? TfColors.accentBg : TfColors.field);
    final int n = bar.cells.length;
    for (int k = 0; k < n; k++) {
      _cell(canvas, geometry.cellRect(r, c, k, n), bar.cells[k], k == 0, current && bar.cells[k].contains(seconds));
    }
    canvas.drawRRect(
      frame.deflate(TfStroke.hairline / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = TfStroke.hairline
        ..color = current ? TfColors.accent : TfColors.fieldLine,
    );
  }

  void _cell(Canvas canvas, Rect cell, GridBeat b, bool first, bool current) {
    final Rect inner = Rect.fromLTRB(cell.left, cell.top + cellInsetV, cell.right, cell.bottom - cellInsetV);
    if (gridCellInLoop(b, loop)) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(inner, const Radius.circular(cellRadius)),
        Paint()..color = TfColors.accent.withValues(alpha: TfOpacity.tint28),
      );
    }
    final bool named = b.named(first);
    final String text = named ? b.name : '·';
    _text(canvas, inner, text, named, named && b.isChord ? TfColors.text : TfColors.muted);
    if (current) {
      final double w = (inner.width - TfSpace.s8) > 4 ? inner.width - TfSpace.s8 : 4;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(inner.center.dx - w / 2, inner.bottom - capsuleHeight, w, capsuleHeight),
          const Radius.circular(capsuleHeight / 2),
        ),
        Paint()..color = TfColors.accent,
      );
    }
  }

  void _text(Canvas canvas, Rect inner, String text, bool named, Color color) {
    final TextStyle style = named
        ? TfText.body(14, TfWeight.bold).copyWith(color: color)
        : TfText.body(13).copyWith(color: color);
    final double padLeft = named ? TfSpace.s6 : 0;
    final double avail = inner.width - padLeft;
    if (avail <= 0) return;
    TextPainter tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, maxLines: 1)
      ..layout();
    double scale = 1;
    if (tp.width > avail) {
      scale = (avail / tp.width) < minTextScale ? minTextScale : avail / tp.width;
      tp = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: avail / scale);
    }
    final double w = tp.width * scale;
    final double x = named ? inner.left + padLeft : inner.left + (inner.width - w) / 2;
    final double y = inner.top + (inner.height - tp.height * scale) / 2;
    canvas.save();
    canvas.translate(x, y);
    canvas.scale(scale);
    tp.paint(canvas, Offset.zero);
    canvas.restore();
  }

  @override
  bool shouldRepaint(ChordGridPainter old) =>
      !identical(old.rows, rows) ||
      old.geometry.width != geometry.width ||
      old.seconds != seconds ||
      old.loop != loop;
}
