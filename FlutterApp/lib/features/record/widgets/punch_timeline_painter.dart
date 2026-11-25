import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../../contract/record_state.dart';
import '../../../theme/tokens.dart';
import '../../../theme/typography.dart';

/// Zona de dibujo del punch-in (PunchTimeline.swift:23-68): fondo, secciones, tramo, asas y cabezal.
class PunchTimelinePainter extends CustomPainter {
  const PunchTimelinePainter({
    required this.duration,
    required this.sections,
    this.entry,
    this.exit,
    this.cursor,
    this.entryLabel,
    this.exitLabel,
  });

  /// Alto fijo de la zona (PT:14).
  static const double height = 54;
  static const double handleWidth = 6;
  static const double _sectionInset = 7;
  static const double _sectionHeight = height - 14;

  final num duration;
  final List<RecordSection> sections;
  final num? entry;
  final num? exit;

  /// Posición del cabezal en segundos; null = oculto.
  final num? cursor;
  final String? entryLabel;
  final String? exitLabel;

  double _x(num t, double w) => t / math.max(duration, 0.001) * w;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(TfRadius.field)),
      Paint()..color = TfColors.bg,
    );
    for (final s in sections) {
      _section(canvas, s, w);
    }
    final a = entry;
    if (a != null) {
      final b = exit ?? a;
      canvas.drawRect(
        Rect.fromLTWH(_x(a, w), 0, math.max(_x(b, w) - _x(a, w), 2), height),
        Paint()..color = TfColors.accent.withValues(alpha: 0.28),
      );
      canvas.drawRRect(_handle(a, w), Paint()..color = TfColors.accent);
    }
    final b = exit;
    if (b != null) canvas.drawRRect(_handle(b, w), Paint()..color = TfColors.accent);
    final c = cursor;
    if (c != null) {
      canvas.drawRect(
        Rect.fromLTWH(_x(c, w), 0, 1, height),
        Paint()..color = TfColors.white.withValues(alpha: 0.8),
      );
    }
  }

  RRect _handle(num t, double w) => RRect.fromRectAndRadius(
        Rect.fromLTWH(_x(t, w) - handleWidth / 2, 0, handleWidth, height),
        const Radius.circular(TfRadius.r2),
      );

  void _section(Canvas canvas, RecordSection s, double w) {
    final color = TfColors.sectionPalette[(s.paletteIndex ?? 0) % TfColors.sectionPalette.length];
    final left = _x(s.start, w);
    final rect = Rect.fromLTWH(left, _sectionInset, math.max(_x(s.end, w) - left, 2), _sectionHeight);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(TfRadius.xs)),
      Paint()..color = color.withValues(alpha: 0.30),
    );
    final tp = TextPainter(
      text: TextSpan(text: s.name, style: TfText.body(TfSize.font10, TfWeight.medium).copyWith(color: color)),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(rect.width - 2 * TfSpace.s4, 0));
    canvas.save();
    canvas.clipRect(rect);
    tp.paint(canvas, rect.topLeft + const Offset(TfSpace.s4, 0));
    canvas.restore();
    tp.dispose();
  }

  @override
  SemanticsBuilderCallback? get semanticsBuilder => (size) {
        final w = size.width;
        CustomPainterSemantics node(int key, num t, String label) => CustomPainterSemantics(
              key: ValueKey<int>(key),
              rect: _handle(t, w).outerRect,
              properties: SemanticsProperties(label: label, textDirection: ui.TextDirection.ltr),
            );
        return [
          if (entry != null && entryLabel != null) node(0, entry!, entryLabel!),
          if (exit != null && exitLabel != null) node(1, exit!, exitLabel!),
        ];
      };

  @override
  bool shouldRepaint(PunchTimelinePainter old) =>
      old.duration != duration ||
      !listEquals(old.sections, sections) ||
      old.entry != entry ||
      old.exit != exit ||
      old.cursor != cursor ||
      old.entryLabel != entryLabel ||
      old.exitLabel != exitLabel;
}
