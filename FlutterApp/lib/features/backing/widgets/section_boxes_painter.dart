import 'package:flutter/widgets.dart';
import 'package:toneforge/theme/tokens.dart';

// TOKEN: sectionFillAlpha 0.07 (SB:67)
const double _fillAlpha = 0.07;
// TOKEN: sectionFillSelectedAlpha 0.16 (SB:67)
const double _fillSelectedAlpha = 0.16;
// TOKEN: sectionHeaderAlpha 0.20 (SB:75)
const double _headerAlpha = 0.20;
// TOKEN: sectionStroke 1.2 (SB:68)
const double _stroke = 1.2;

/// Color de una sección: solo = `accent`; el resto, paleta `[paletteIndex % 7]` (SB:35-120).
Color sectionColor({required bool solo, required int paletteIndex}) =>
    solo ? TfColors.accent : TfColors.sectionPalette[paletteIndex % TfColors.sectionPalette.length];

/// Caja de una sección (SB:35-120): relleno, cabecera con esquinas superiores redondeadas y trazo.
class SectionBoxPainter extends CustomPainter {
  const SectionBoxPainter({
    required this.color,
    required this.solo,
    required this.selected,
    required this.loopActive,
    required this.headerHeight,
  });

  final Color color;
  final bool solo;
  final bool selected;

  /// El bucle activo coincide con la sección: trazo `accent`.
  final bool loopActive;
  final double headerHeight;

  @override
  void paint(Canvas canvas, Size size) {
    const Radius r = Radius.circular(TfRadius.r9);
    final bool thick = selected || loopActive;
    final double w = thick ? TfStroke.thick : _stroke;
    final Rect box = Offset.zero & size;
    final RRect body = RRect.fromRectAndRadius(box, r);
    canvas.drawRRect(
      body,
      Paint()..color = color.withValues(alpha: selected ? _fillSelectedAlpha : _fillAlpha),
    );
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(0, 0, size.width, headerHeight),
        topLeft: r,
        topRight: r,
      ),
      Paint()..color = solo ? TfColors.accentBg : color.withValues(alpha: _headerAlpha),
    );
    final Color line = selected
        ? color
        : loopActive
            ? TfColors.accent
            : color.withValues(alpha: TfOpacity.bars);
    canvas.drawRRect(
      body.deflate(w / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..color = line,
    );
  }

  @override
  bool shouldRepaint(SectionBoxPainter old) =>
      old.color != color ||
      old.solo != solo ||
      old.selected != selected ||
      old.loopActive != loopActive ||
      old.headerHeight != headerHeight;
}
