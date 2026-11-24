import 'package:flutter/widgets.dart';

part 'icons_data.dart';
part 'icons_data_2.dart';
part 'icons_data_3.dart';
part 'icons_data_4.dart';

/// Iconos de la app, uno por SF Symbol de la tabla de §4 de tokens-componentes.md.
/// Dibujo: Lucide 1.70.0 (ISC), trazo 24x24, stroke 2, extremos y uniones redondos.
/// Los datos los genera Tools/flutter/lucide_to_dart.py (icons_data*.dart).
enum TfIcon {
  musicNoteList,
  sliderVertical3,
  musicQuarternote3,
  recordCircle,
  film,
  gearshape,
  magnifyingglass,
  xmark,
  trash,
  folder,
  pencil,
  chevronLeft,
  chevronDown,
  checkmarkCircle,
  infoCircle,
  exclamationmarkTriangle,
  arrowUpRightSquare,
  playFill,
  arrowUturnBackward,
  arrowUturnForward,
  plus,
  minus,
  arrowUpArrowDown,
  personFill,
  musicNote,
  xmarkCircleFill,
  checkmarkCircleFill,
  exclamationmarkTriangleFill,
  chevronRight,
  chevronUp,
  chevronUpChevronDown,
  checkmark,
  checkmarkSquareFill,
  square,
  circle,
  largecircleFillCircle,
  pencilCircleFill,
  pauseFill,
  playpauseFill,
  backwardEndFill,
  repeat,
  arrowLeft,
  arrowRight,
  video,
  cameraFill,
  lockFill,
  rotateRight,
  line3Horizontal,
  guitars,
  guitarsFill,
  waveform,
  mic,
  circleGrid2x2,
  speakerWave2Fill,
  speakerSlashFill,
  rectangleDashed,
}

/// Comandos de Path, en el espacio 24x24 del icono.
sealed class _Cmd {
  const _Cmd();
}

final class _M extends _Cmd {
  const _M(this.x, this.y);
  final double x;
  final double y;
}

final class _L extends _Cmd {
  const _L(this.x, this.y);
  final double x;
  final double y;
}

final class _C extends _Cmd {
  const _C(this.x1, this.y1, this.x2, this.y2, this.x, this.y);
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final double x;
  final double y;
}

final class _A extends _Cmd {
  const _A(this.rx, this.ry, this.rotation, this.largeArc, this.sweep, this.x, this.y);
  final double rx;
  final double ry;
  final double rotation;
  final bool largeArc;
  final bool sweep;
  final double x;
  final double y;
}

final class _Z extends _Cmd {
  const _Z();
}

const Map<TfIcon, List<_Cmd>> _tfIconData = {
  ..._tfIconDataA,
  ..._tfIconDataB,
  ..._tfIconDataC,
  ..._tfIconDataD,
};

/// Numero de comandos de Path del icono (0 si no tiene datos). Solo para tests.
@visibleForTesting
int tfIconCommandCount(TfIcon icon) => _tfIconData[icon]?.length ?? 0;

/// Icono de trazo. El tamaño escala el dibujo 24x24; el color pinta el trazo.
class TfIconView extends StatelessWidget {
  const TfIconView(this.icon, {super.key, this.size = 24, required this.color});

  final TfIcon icon;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _TfIconPainter(icon, color),
    );
  }
}

class _TfIconPainter extends CustomPainter {
  _TfIconPainter(this.icon, this.color);

  final TfIcon icon;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final cmds = _tfIconData[icon] ?? const <_Cmd>[];
    final path = Path();
    for (final c in cmds) {
      switch (c) {
        case _M(:final x, :final y):
          path.moveTo(x, y);
        case _L(:final x, :final y):
          path.lineTo(x, y);
        case _C(:final x1, :final y1, :final x2, :final y2, :final x, :final y):
          path.cubicTo(x1, y1, x2, y2, x, y);
        case _A(:final rx, :final ry, :final rotation, :final largeArc, :final sweep, :final x, :final y):
          path.arcToPoint(
            Offset(x, y),
            radius: Radius.elliptical(rx, ry),
            rotation: rotation,
            largeArc: largeArc,
            clockwise: sweep,
          );
        case _Z():
          path.close();
      }
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TfIconPainter old) => old.icon != icon || old.color != color;
}
