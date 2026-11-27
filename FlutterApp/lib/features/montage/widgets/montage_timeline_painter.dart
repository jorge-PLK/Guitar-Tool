import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../../theme/tokens.dart';
import '../../../theme/typography.dart';

/// Tramo de tiempo en segundos.
@immutable
class TimeSpan {
  const TimeSpan(this.start, this.end);
  final double start;
  final double end;

  @override
  bool operator ==(Object other) => other is TimeSpan && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// Carril de una parte con toma (MV:821-835). `take` = lo grabado (contorno
/// discontinuo); `presence` = lo que se ve en pantalla (barra llena).
@immutable
class MontageLaneData {
  const MontageLaneData({
    required this.take,
    required this.presence,
    this.solo = false,
    this.hasVideo = true,
    this.colorIndex = 0,
  });
  final TimeSpan take;
  final List<TimeSpan> presence;
  final bool solo;
  final bool hasVideo;

  /// Posición entre las partes no solistas (indexa `TfColors.laneColors` con módulo).
  final int colorIndex;
}

@immutable
class MontageSectionData {
  const MontageSectionData({required this.name, required this.start, required this.end, this.solo = false});
  final String name;
  final double start;
  final double end;
  final bool solo;
}

/// Tramo del carril «Plano»: qué carril se ve (`laneIndex` en `lanes`, null = automático) o negro.
@immutable
class MontagePlaneShot {
  const MontagePlaneShot({required this.start, required this.end, this.laneIndex, this.black = false});
  final double start;
  final double end;
  final int? laneIndex;
  final bool black;
}

@immutable
class MontageCutMark {
  const MontageCutMark({required this.time, required this.covered});
  final double time;

  /// Cubierto = la parte elegida tiene toma ahí (marca `text`); si no, `accent`.
  final bool covered;
}

/// Todo lo que pinta la línea de tiempo (segundos). El eje se calcula con [MontageTimelineData.axisFor].
@immutable
class MontageTimelineData {
  const MontageTimelineData({
    required this.axisStart,
    required this.axisEnd,
    required this.spanStart,
    required this.spanEnd,
    this.barDuration = 0,
    this.fadeIn = false,
    this.fadeOut = false,
    this.sections = const [],
    this.lanes = const [],
    this.missingCount = 0,
    this.showPlane = false,
    this.planeShots = const [],
    this.cuts = const [],
    this.gaps = const [],
    this.cursor = 0,
  });

  final double axisStart, axisEnd;

  /// Tramo del vídeo (banda de 8).
  final double spanStart, spanEnd;
  final double barDuration;
  final bool fadeIn, fadeOut;
  final List<MontageSectionData> sections;
  final List<MontageLaneData> lanes;

  /// Partes sin toma: carril vacío (solo fondo) tras los carriles.
  final int missingCount;

  /// Carril «Plano» (solo en plano único).
  final bool showPlane;
  final List<MontagePlaneShot> planeShots;
  final List<MontageCutMark> cuts;

  /// Huecos cortados («Cortar huecos sin tomas»): rayados.
  final List<TimeSpan> gaps;
  final double cursor;

  /// Eje (MV:524-528): tramo con margen del 10 % (mín. un compás), dentro del tema.
  static TimeSpan axisFor({
    required double spanStart,
    required double spanEnd,
    required double songDuration,
    double barDuration = 0,
  }) {
    final songEnd = math.max(songDuration, math.max(spanEnd, 1.0));
    final margin = math.max((spanEnd - spanStart) * MontageTimelineGeometry.axisMarginFraction, barDuration);
    return TimeSpan(math.max(0, spanStart - margin), math.min(songEnd, spanEnd + margin));
  }
}

/// Geometría pura (hit-testing y pintado). Coordenadas locales del área de carriles,
/// sin la columna de etiquetas (que compone el widget padre con [labelWidth] + 10 de separación).
class MontageTimelineGeometry {
  const MontageTimelineGeometry(this.data, this.width);
  final MontageTimelineData data;
  final double width;

  static const double axisMarginFraction = 0.10;
  static const double labelWidth = 270;
  static const double rowSpacing = TfSpace.s6;
  static const double laneHeight = 30;
  static const double sectionHeight = 24;
  static const double bandHeight = TfSpace.s8;
  static const double cutMarkWidth = TfSpace.s8;

  double get duration => math.max(data.axisEnd - data.axisStart, 1);

  double timeToX(double t) => (t - data.axisStart) / duration * width;

  /// Inverso, acotado al eje.
  double xToTime(double x) {
    if (width <= 0) return data.axisStart;
    return data.axisStart + (x / width).clamp(0.0, 1.0) * duration;
  }

  int get rowCount => data.lanes.length + data.missingCount + (data.showPlane ? 1 : 0);

  double get totalHeight => bandHeight + sectionHeight + rowCount * laneHeight + (rowCount + 1) * rowSpacing;

  double get _bandTop => 0;
  double get _sectionsTop => bandHeight + rowSpacing;
  double get _firstRowTop => _sectionsTop + sectionHeight + rowSpacing;
  double _rowTop(int row) => _firstRowTop + row * (laneHeight + rowSpacing);

  Rect get bandRect => Rect.fromLTWH(timeToX(data.spanStart), _bandTop, math.max(2, timeToX(data.spanEnd) - timeToX(data.spanStart)), bandHeight);
  Rect get sectionsRect => Rect.fromLTWH(0, _sectionsTop, width, sectionHeight);

  /// Rect del carril «Plano» (null si no se muestra).
  Rect? get planeRect => data.showPlane ? Rect.fromLTWH(0, _rowTop(0), width, laneHeight) : null;

  int get _laneRow0 => data.showPlane ? 1 : 0;

  /// Rect (de todo el ancho) del carril `i`.
  Rect laneRect(int i) => Rect.fromLTWH(0, _rowTop(_laneRow0 + i), width, laneHeight);

  /// Rect del carril sin toma `i`.
  Rect missingRect(int i) => Rect.fromLTWH(0, _rowTop(_laneRow0 + data.lanes.length + i), width, laneHeight);

  /// Rect de la barra de un tramo de presencia / de la toma de un carril.
  Rect spanRect(Rect lane, double start, double end) =>
      Rect.fromLTWH(timeToX(start), lane.top, math.max(2, timeToX(end) - timeToX(start)), laneHeight);

  /// Marca de corte `i` (8 de ancho, alto de carril), centrada en su instante. [time] sustituye al del dato (arrastre).
  Rect cutMarkRect(int i, {double? time}) {
    final plane = planeRect!;
    final x = timeToX(time ?? data.cuts[i].time);
    return Rect.fromLTWH(x - cutMarkWidth / 2, plane.top, cutMarkWidth, laneHeight);
  }

  /// Índice de la marca de corte bajo [p], o null.
  int? cutAt(Offset p) {
    if (!data.showPlane) return null;
    for (var i = data.cuts.length - 1; i >= 0; i--) {
      if (cutMarkRect(i).contains(p)) return i;
    }
    return null;
  }
}

class MontageTimelinePainter extends CustomPainter {
  const MontageTimelinePainter(this.data);
  final MontageTimelineData data;

  static const double _dimOutside = 0.6;
  static const double _dimGap = 0.7;
  static const double _dashLine = 0.4;
  static const double _takeOutline = 0.6;
  static const double _noVideo = 0.35;
  static const double _bandFill = 0.35;
  static const double _planeShot = 0.85;
  static const double _cursorWidth = TfStroke.thick;

  static Color laneColor(int colorIndex, {bool solo = false}) =>
      solo ? TfColors.soloViolet : TfColors.laneColors[colorIndex % TfColors.laneColors.length];

  @override
  void paint(Canvas canvas, Size size) {
    final g = MontageTimelineGeometry(data, size.width);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    _band(canvas, g);
    _sections(canvas, g);
    final plane = g.planeRect;
    if (plane != null) _plane(canvas, g, plane);
    for (var i = 0; i < data.lanes.length; i++) {
      _lane(canvas, g, data.lanes[i], g.laneRect(i));
    }
    for (var i = 0; i < data.missingCount; i++) {
      canvas.drawRRect(_rr(g.missingRect(i), TfRadius.small), Paint()..color = TfColors.field);
    }
    final h = g.totalHeight;
    final dim = Paint()..color = TfColors.bg.withValues(alpha: _dimOutside);
    canvas.drawRect(Rect.fromLTRB(0, 0, g.timeToX(data.spanStart).clamp(0, size.width), h), dim);
    canvas.drawRect(Rect.fromLTRB(g.timeToX(data.spanEnd).clamp(0, size.width), 0, size.width, h), dim);
    for (final gap in data.gaps) {
      final r = Rect.fromLTWH(g.timeToX(gap.start), 0, math.max(2, g.timeToX(gap.end) - g.timeToX(gap.start)), h);
      canvas.drawRect(r, Paint()..color = TfColors.bg.withValues(alpha: _dimGap));
      _dashedRect(canvas, r, 0, TfColors.muted.withValues(alpha: _dashLine), 2, 3);
    }
    canvas.drawRect(
      Rect.fromLTWH(g.timeToX(data.cursor) - _cursorWidth / 2, 0, _cursorWidth, h),
      Paint()..color = TfColors.text,
    );
    canvas.restore();
  }

  RRect _rr(Rect r, double radius) => RRect.fromRectAndRadius(r, Radius.circular(radius));

  void _band(Canvas canvas, MontageTimelineGeometry g) {
    final r = g.bandRect;
    final rr = _rr(r, TfRadius.r3);
    canvas.drawRRect(rr, Paint()..color = TfColors.accent.withValues(alpha: _bandFill));
    final fade = math.max(2.0, g.timeToX(data.barDuration) - g.timeToX(0));
    void gradient(Rect fr, List<Color> colors) {
      canvas.save();
      canvas.clipRRect(_rr(fr, TfRadius.r3));
      canvas.drawRect(fr, Paint()..shader = ui.Gradient.linear(fr.centerLeft, fr.centerRight, colors));
      canvas.restore();
    }

    if (data.fadeIn) gradient(Rect.fromLTWH(r.left, r.top, fade, r.height), [TfColors.bg, TfColors.accent]);
    if (data.fadeOut) {
      gradient(Rect.fromLTWH(g.timeToX(data.spanEnd - data.barDuration), r.top, fade, r.height), [TfColors.accent, TfColors.bg]);
    }
  }

  void _sections(Canvas canvas, MontageTimelineGeometry g) {
    canvas.drawRRect(_rr(g.sectionsRect, TfRadius.small), Paint()..color = TfColors.bg.withValues(alpha: _dimOutside));
    for (final s in data.sections) {
      final a = math.max(s.start, data.axisStart), b = math.min(s.end, data.axisEnd);
      if (b <= a) continue;
      final r = Rect.fromLTWH(g.timeToX(a), g.sectionsRect.top, math.max(2, g.timeToX(b) - g.timeToX(a) - 2), MontageTimelineGeometry.sectionHeight);
      canvas.drawRRect(_rr(r, TfRadius.small), Paint()..color = s.solo ? TfColors.accentBg : TfColors.neutralBg);
      final tp = TextPainter(
        text: TextSpan(text: s.name, style: TfText.body(TfSize.font11, TfWeight.semibold).copyWith(color: s.solo ? TfColors.accent : TfColors.text2)),
        textDirection: ui.TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: math.max(r.width - 2 * TfSpace.s6, 0));
      canvas.save();
      canvas.clipRect(r);
      tp.paint(canvas, Offset(r.left + TfSpace.s6, r.top + (r.height - tp.height) / 2));
      canvas.restore();
      tp.dispose();
    }
  }

  void _lane(Canvas canvas, MontageTimelineGeometry g, MontageLaneData lane, Rect rect) {
    canvas.drawRRect(_rr(rect, TfRadius.small), Paint()..color = TfColors.field);
    final color = laneColor(lane.colorIndex, solo: lane.solo);
    _dashedRect(canvas, g.spanRect(rect, lane.take.start, lane.take.end), TfRadius.small, color.withValues(alpha: _takeOutline), TfStroke.dash, TfStroke.dash);
    final fill = Paint()..color = lane.hasVideo ? color : color.withValues(alpha: _noVideo);
    for (final p in lane.presence) {
      canvas.drawRRect(_rr(g.spanRect(rect, p.start, p.end), TfRadius.small), fill);
    }
  }

  void _plane(Canvas canvas, MontageTimelineGeometry g, Rect rect) {
    canvas.drawRRect(_rr(rect, TfRadius.small), Paint()..color = TfColors.field);
    for (final s in data.planeShots) {
      final a = math.max(s.start, data.axisStart), b = math.min(s.end, data.axisEnd);
      if (b <= a) continue;
      final lane = s.laneIndex != null && s.laneIndex! < data.lanes.length ? data.lanes[s.laneIndex!] : null;
      final c = lane == null ? null : laneColor(lane.colorIndex, solo: lane.solo);
      final r = Rect.fromLTWH(g.timeToX(a), rect.top + TfSpace.s2, math.max(2, g.timeToX(b) - g.timeToX(a) - 1), MontageTimelineGeometry.laneHeight - TfSpace.s4);
      final rr = _rr(r, TfRadius.xs);
      if (s.black) {
        canvas.drawRRect(rr, Paint()..color = TfColors.black);
        canvas.drawRRect(rr.deflate(0.5), Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = (c ?? TfColors.muted).withValues(alpha: c == null ? _dashLine : _takeOutline));
      } else if (c != null) {
        canvas.drawRRect(rr, Paint()..color = c.withValues(alpha: _planeShot));
      } else {
        canvas.drawRRect(rr, Paint()..color = TfColors.neutralBg);
        _dashedRect(canvas, r, TfRadius.xs, TfColors.muted.withValues(alpha: _dashLine), 2, 3);
      }
    }
    for (var i = 0; i < data.cuts.length; i++) {
      final r = _rr(g.cutMarkRect(i), TfRadius.r2);
      canvas.drawRRect(r, Paint()..color = data.cuts[i].covered ? TfColors.text : TfColors.accent);
      canvas.drawRRect(r.deflate(0.5), Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = TfColors.bg);
    }
  }

  /// Contorno de 1 px discontinuo por dentro del rect (strokeBorder).
  void _dashedRect(Canvas canvas, Rect r, double radius, Color color, double dash, double gap) {
    final path = Path()..addRRect(_rr(r.deflate(0.5), radius));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = TfStroke.hairline
      ..color = color;
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += dash + gap) {
        canvas.drawPath(m.extractPath(d, math.min(d + dash, m.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(MontageTimelinePainter old) => old.data != data;
}
