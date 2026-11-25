import 'package:flutter/widgets.dart';

/// Recorta el centro de [text] con «…» para que quepa en [maxWidth] (una línea), como
/// `.truncationMode(.middle)` de SwiftUI. Búsqueda binaria del nº de caracteres conservados.
String tfMiddleEllipsis(
  String text,
  TextStyle style,
  double maxWidth, {
  TextDirection textDirection = TextDirection.ltr,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  const ellipsis = '…';
  final chars = text.characters.toList();

  double widthOf(String s) {
    final p = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    final w = p.width;
    p.dispose();
    return w;
  }

  if (chars.isEmpty || widthOf(text) <= maxWidth) return text;

  String build(int keep) {
    final head = (keep + 1) ~/ 2;
    final tail = keep ~/ 2;
    return '${chars.take(head).join()}$ellipsis${chars.skip(chars.length - tail).join()}';
  }

  var lo = 0;
  var hi = chars.length - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) ~/ 2;
    if (widthOf(build(mid)) <= maxWidth) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return build(lo);
}

/// Texto de una línea con truncado al medio (rutas). Usa el ancho disponible del padre.
class TfMiddleEllipsisText extends StatelessWidget {
  const TfMiddleEllipsisText(this.text, {super.key, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final shown = constraints.hasBoundedWidth
            ? tfMiddleEllipsis(text, style, constraints.maxWidth, textDirection: direction, textScaler: scaler)
            : text;
        return Text(shown, maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: style);
      },
    );
  }
}
