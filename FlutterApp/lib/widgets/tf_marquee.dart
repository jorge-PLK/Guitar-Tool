import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:toneforge/theme/tokens.dart';

/// Una línea que, si no cabe, se trunca con «…» y, al pasar el ratón, corre hasta verse entera
/// (30 px/s lineal) y vuelve en 0,2 s easeOut. Cambiar el texto reinicia. Origen: MarqueeText.swift:5-38.
/// El alto es el de una línea del estilo dado y no cambia.
class TfMarquee extends StatefulWidget {
  const TfMarquee({super.key, required this.text, required this.style});

  final String text;
  final TextStyle style;

  /// Clave del texto desplazándose, para tests.
  static const Key runningKey = ValueKey<String>('tfMarqueeRunning');

  @override
  State<TfMarquee> createState() => _TfMarqueeState();
}

class _TfMarqueeState extends State<TfMarquee> with SingleTickerProviderStateMixin {
  static const Duration _backDuration = Duration(milliseconds: 200);

  late final AnimationController _controller = AnimationController(vsync: this);
  bool _hovering = false;
  double _overflow = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(TfMarquee old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _hovering = false;
      _controller.value = 0;
    }
  }

  void _setHover(bool value) {
    _hovering = value;
    if (value) {
      if (_overflow <= 0) return;
      final int ms = (_overflow / TfSize.marqueeSpeed * 1000).round();
      _controller.animateTo(1, duration: Duration(milliseconds: ms), curve: Curves.linear);
    } else {
      _controller.animateBack(0, duration: _backDuration, curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String shown = widget.text.isEmpty ? ' ' : widget.text;
    final TextPainter painter = TextPainter(
      text: TextSpan(text: shown, style: widget.style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final double fullWidth = painter.width;
    final double height = painter.height;
    painter.dispose();

    return MouseRegion(
      onEnter: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double box = constraints.maxWidth;
          _overflow = box.isFinite ? math.max(0, fullWidth - box) : 0;
          return SizedBox(
            width: box.isFinite ? box : null,
            height: height,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (BuildContext context, Widget? _) {
                final bool running = _overflow > 0 && (_hovering || _controller.value > 0);
                if (!running) {
                  return Text(
                    shown,
                    style: widget.style,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  );
                }
                return ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: 0,
                    maxWidth: double.infinity,
                    child: Transform.translate(
                      key: TfMarquee.runningKey,
                      offset: Offset(-_overflow * _controller.value, 0),
                      child: Text(shown, style: widget.style, maxLines: 1, softWrap: false),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
