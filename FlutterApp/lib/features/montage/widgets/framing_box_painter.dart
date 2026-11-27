import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../../theme/tokens.dart';

/// Caja de encuadre normalizada (0..1 sobre el fotograma) y si lleva punto de escala.
@immutable
class FramingBoxData {
  const FramingBoxData({required this.box, required this.showScaleHandle});

  /// x, y, ancho y alto en 0..1.
  final Rect box;

  /// Solo en modo fijo; en modo seguir no hay punto.
  final bool showScaleHandle;
}

/// Geometría pura de la caja para un fotograma de [size] (hit-testing de la hoja «Encuadre»).
class FramingBoxGeometry {
  const FramingBoxGeometry(this.box, this.size);
  final Rect box;
  final Size size;

  static const double handleDiameter = 14;

  /// Radio de captura del arrastre de escala (FS:20).
  static const double handleHitRadius = 16;

  Rect get boxRect => Rect.fromLTWH(
        box.left * size.width,
        box.top * size.height,
        box.width * size.width,
        box.height * size.height,
      );

  /// Centro del punto de escala: esquina inferior derecha de la caja.
  Offset get handleCenter => boxRect.bottomRight;

  Rect get handleRect => Rect.fromCenter(center: handleCenter, width: handleDiameter, height: handleDiameter);

  /// ¿Cae [p] en la zona de captura del punto de escala?
  bool hitsHandle(Offset p) => (p - handleCenter).distance <= handleHitRadius;
}

class FramingBoxPainter extends CustomPainter {
  const FramingBoxPainter(this.data);
  final FramingBoxData data;

  static const double _maskOpacity = 0.5;

  @override
  void paint(Canvas canvas, Size size) {
    final g = FramingBoxGeometry(data.box, size);
    final r = g.boxRect;
    final mask = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(r);
    canvas.drawPath(mask, Paint()..color = TfColors.black.withValues(alpha: _maskOpacity));
    canvas.drawRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = TfStroke.thick
        ..color = TfColors.accent,
    );
    if (data.showScaleHandle) {
      canvas.drawCircle(g.handleCenter, FramingBoxGeometry.handleDiameter / 2, Paint()..color = TfColors.accent);
    }
  }

  @override
  bool shouldRepaint(FramingBoxPainter old) => old.data.box != data.box || old.data.showScaleHandle != data.showScaleHandle;
}
