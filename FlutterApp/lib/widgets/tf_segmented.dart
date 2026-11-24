import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Un segmento: valor y texto ya localizado.
class TfSegment<T> {
  const TfSegment({required this.value, required this.label});

  final T value;
  final String label;
}

/// Control segmentado de macOS redibujado (`.pickerStyle(.segmented)`).
/// Segmento activo relleno con `accent`. Flechas izquierda/derecha con el foco.
/// `width` fijo reparte a partes iguales; sin él, cada segmento mide su contenido.
class TfSegmented<T> extends StatelessWidget {
  const TfSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.width,
  });

  final List<TfSegment<T>> segments;
  final T value;
  final ValueChanged<T>? onChanged;
  final double? width;

  void _move(int delta) {
    final int i = segments.indexWhere((TfSegment<T> s) => s.value == value);
    final int next = (i + delta).clamp(0, segments.length - 1);
    if (next != i) onChanged!(segments[next].value);
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = onChanged != null;
    final List<Widget> cells = <Widget>[];
    for (final TfSegment<T> s in segments) {
      final bool active = s.value == value;
      Widget cell = MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? () => onChanged!(s.value) : null,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: active ? TfColors.accent : null,
              borderRadius: BorderRadius.circular(TfRadius.xs),
            ),
            child: Center(
              widthFactor: width == null ? 1 : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: TfSize.segmentedPadH),
                child: Text(
                  s.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TfText.body(13).copyWith(
                    color: active ? TfColors.accentInk : TfColors.nativeSegmentText,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      if (width != null) cell = Expanded(child: cell);
      cells.add(cell);
    }
    Widget body = SizedBox(
      width: width,
      height: TfSize.segmentedHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: TfColors.nativeSegmentBg,
          borderRadius: BorderRadius.circular(TfRadius.native),
        ),
        child: Padding(
          padding: const EdgeInsets.all(TfSize.segmentedInset),
          child: Row(
            mainAxisSize: width == null ? MainAxisSize.min : MainAxisSize.max,
            children: cells,
          ),
        ),
      ),
    );
    if (!enabled) {
      return Opacity(opacity: TfOpacity.disabled, child: body);
    }
    body = Focus(
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _move(-1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          _move(1);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: body,
    );
    return body;
  }
}
