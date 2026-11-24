import 'package:flutter/widgets.dart';

import '../theme/icons.dart';
import '../theme/tokens.dart';

/// Carátula del tema: `SongCover` (LibraryView.swift:410). 44x44, radio 8, borde `line`. Sin [image]
/// (o si falla): fondo `field` + `musicNote` 18 `muted`. La miniatura se decodifica a 88 px.
class TfSongCover extends StatelessWidget {
  const TfSongCover({super.key, this.image});

  final ImageProvider? image;

  @override
  Widget build(BuildContext context) {
    const BorderRadius radius = BorderRadius.all(Radius.circular(TfRadius.field));
    final ImageProvider? img = image;
    const Widget placeholder = ColoredBox(
      color: TfColors.field,
      child: Center(child: TfIconView(TfIcon.musicNote, size: TfSize.coverIcon, color: TfColors.muted)),
    );
    final int px = TfSize.coverThumbPixels.round();
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: TfSize.coverSide,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: TfColors.line, width: TfStroke.hairline),
          ),
          position: DecorationPosition.foreground,
          child: ClipRRect(
            borderRadius: radius,
            child: img == null
                ? placeholder
                : Image(
                    image: ResizeImage(img, width: px, height: px, policy: ResizeImagePolicy.fit),
                    fit: BoxFit.cover,
                    errorBuilder: (BuildContext c, Object e, StackTrace? s) => placeholder,
                  ),
          ),
        ),
      ),
    );
  }
}
