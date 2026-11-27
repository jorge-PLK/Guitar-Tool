import 'package:flutter/widgets.dart';

import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/tf_slider.dart';
import 'widgets/framing_box_painter.dart';

/// Geometría de la caja de la hoja «Encuadre» (FS:164-177). Todo en coordenadas normalizadas 0..1.
abstract final class FramingBoxMath {
  /// Lado mínimo de la caja (FS:21).
  static const double minSide = 0.05;

  static double clampTo(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

  /// Mueve la caja sin salirse del fotograma.
  static Rect moved(Rect b, double dx, double dy) => Rect.fromLTWH(
        clampTo(b.left + dx, 0, 1 - b.width),
        clampTo(b.top + dy, 0, 1 - b.height),
        b.width,
        b.height,
      );

  /// Escala desde la esquina superior izquierda conservando la proporción en píxeles
  /// ([aspect] = ancho/alto del fotograma).
  static Rect resized(Rect b, double dx, double aspect) {
    final double boxAspect = (b.width * aspect) / (b.height < 1e-6 ? 1e-6 : b.height);
    final double maxW = (1 - b.left) < (1 - b.top) * boxAspect / aspect ? (1 - b.left) : (1 - b.top) * boxAspect / aspect;
    final double w = clampTo(b.width + dx, minSide, maxW < minSide ? minSide : maxW);
    return Rect.fromLTWH(b.left, b.top, w, w * aspect / boxAspect);
  }
}

/// Fotograma con la máscara y la caja; el arrastre se notifica con el punto de partida y el
/// desplazamiento acumulado en píxeles locales.
class FramingFrameArea extends StatefulWidget {
  const FramingFrameArea({
    super.key,
    required this.aspect,
    required this.box,
    required this.showHandle,
    required this.image,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final double aspect;
  final Rect box;
  final bool showHandle;
  final Widget image;
  final void Function(Offset start, Size size) onDragStart;
  final void Function(Offset translation, Size size) onDragUpdate;
  final VoidCallback onDragEnd;

  /// Altura máxima del fotograma (FS:105).
  static const double maxHeight = 400;

  @override
  State<FramingFrameArea> createState() => _FramingFrameAreaState();
}

class _FramingFrameAreaState extends State<FramingFrameArea> {
  Offset _start = Offset.zero;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: FramingFrameArea.maxHeight),
      child: Center(
        child: AspectRatio(
          aspectRatio: widget.aspect,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(TfRadius.control),
              border: Border.all(color: TfColors.fieldLine, width: TfStroke.hairline),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(TfRadius.control),
              child: ColoredBox(
                color: TfColors.black,
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints c) {
                    final Size size = c.biggest;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanDown: (DragDownDetails d) {
                        _start = d.localPosition;
                        widget.onDragStart(_start, size);
                      },
                      onPanUpdate: (DragUpdateDetails d) => widget.onDragUpdate(d.localPosition - _start, size),
                      onPanEnd: (_) => widget.onDragEnd(),
                      onPanCancel: widget.onDragEnd,
                      child: Stack(
                        fit: StackFit.expand,
                        children: <Widget>[
                          widget.image,
                          IgnorePointer(
                            child: CustomPaint(
                              painter: FramingBoxPainter(FramingBoxData(box: widget.box, showScaleHandle: widget.showHandle)),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fila título (130) + deslizador + valor (56) de los controles del modo seguir (FS:205-211).
class FramingSliderRow extends StatelessWidget {
  const FramingSliderRow({
    super.key,
    required this.title,
    required this.semanticLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.valueText,
    required this.onChanged,
  });

  final String title;
  final String semanticLabel;
  final double value;
  final double min;
  final double max;
  final String valueText;
  final ValueChanged<double> onChanged;

  static const double titleWidth = 130;
  static const double valueWidth = 56;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: TfSpace.s10,
      children: <Widget>[
        SizedBox(
          width: titleWidth,
          child: Text(title, style: TfText.body(TfSize.font13).copyWith(color: TfColors.text2)),
        ),
        Expanded(
          child: Semantics(
            label: semanticLabel,
            child: TfSlider(value: value, min: min, max: max, onChanged: onChanged),
          ),
        ),
        SizedBox(
          width: valueWidth,
          child: Text(
            valueText,
            textAlign: TextAlign.right,
            style: TfText.body(TfSize.font13, TfWeight.regular, true).copyWith(color: TfColors.text),
          ),
        ),
      ],
    );
  }
}
