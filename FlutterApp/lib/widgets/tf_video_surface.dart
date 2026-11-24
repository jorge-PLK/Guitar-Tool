import 'package:flutter/widgets.dart';

import '../core/frame_channel.dart';

/// Ajuste del fotograma en la superficie.
enum TfVideoFit { contain, cover }

/// Pinta el `Texture` de un canal de fotogramas del núcleo. `FrameChannel` solo da el id de la textura;
/// el tamaño del fotograma lo pasa el llamador en [frameSize] (lo trae el estado del núcleo). Sin
/// [frameSize] la textura rellena la caja. Con rotación 90/270 el ancho y el alto efectivos se intercambian.
/// Recortado a [radius]. Sin textura (nulo o negativo: MockCore, −1) sale [placeholder].
class TfVideoSurface extends StatelessWidget {
  const TfVideoSurface({
    super.key,
    required this.textureId,
    this.frameSize,
    this.fit = TfVideoFit.contain,
    this.rotation = 0,
    this.radius = 0,
    this.placeholder = const SizedBox.shrink(),
  }) : assert(rotation == 0 || rotation == 90 || rotation == 180 || rotation == 270);

  /// Toma el id de [channel] en este momento (`FrameChannel.create` ya hecho por el store).
  TfVideoSurface.channel(
    FrameChannel channel, {
    Key? key,
    Size? frameSize,
    TfVideoFit fit = TfVideoFit.contain,
    int rotation = 0,
    double radius = 0,
    Widget placeholder = const SizedBox.shrink(),
  }) : this(
          key: key,
          textureId: channel.textureId,
          frameSize: frameSize,
          fit: fit,
          rotation: rotation,
          radius: radius,
          placeholder: placeholder,
        );

  final int? textureId;
  final Size? frameSize;
  final TfVideoFit fit;
  final int rotation;
  final double radius;
  final Widget placeholder;

  @override
  Widget build(BuildContext context) {
    final int? id = textureId;
    final Size? frame = frameSize;
    final bool swapped = rotation == 90 || rotation == 270;
    final Size? effective = frame == null ? null : (swapped ? Size(frame.height, frame.width) : frame);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
        final double w = c.hasBoundedWidth ? c.maxWidth : (effective?.width ?? c.minWidth);
        final double h = c.hasBoundedHeight ? c.maxHeight : (effective?.height ?? c.minHeight);
        return SizedBox(
          width: w,
          height: h,
          child: id == null || id < 0
              ? placeholder
              : effective == null
                  ? RotatedBox(quarterTurns: rotation ~/ 90, child: Texture(textureId: id))
                  : FittedBox(
                      fit: fit == TfVideoFit.cover ? BoxFit.cover : BoxFit.contain,
                      clipBehavior: Clip.hardEdge,
                      child: SizedBox.fromSize(
                        size: effective,
                        child: RotatedBox(
                          quarterTurns: rotation ~/ 90,
                          child: SizedBox.fromSize(size: frame, child: Texture(textureId: id)),
                        ),
                      ),
                    ),
        );
      }),
    );
  }
}
