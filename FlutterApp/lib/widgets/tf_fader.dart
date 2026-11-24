import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// Fader vertical de −60 a +6 dB (`Fader`, BackingMixer.swift:281-311).
/// Arrastre sin tolerancia (el valor sigue al puntero desde el primer contacto), imán a 0 dB
/// dentro de ±1,5 dB, doble clic = 0 dB, flechas = ±1 dB. Sin textos: la etiqueta y el
/// formato del valor para lectores de pantalla entran por parámetro.
class TfFader extends StatefulWidget {
  const TfFader({
    super.key,
    required this.dB,
    required this.onChanged,
    required this.semanticLabel,
    required this.semanticValue,
    this.height = TfSize.faderBaseHeight,
    this.focusNode,
    this.autofocus = false,
  });

  static const double minDb = -60;
  static const double maxDb = 6;
  static const double snapDb = 1.5;
  static const double stepDb = 1;

  final double dB;
  final ValueChanged<double> onChanged;
  final String semanticLabel;

  /// Texto del valor (p. ej. «−6,0 dB») para accesibilidad.
  final String Function(double dB) semanticValue;
  final double height;
  final FocusNode? focusNode;
  final bool autofocus;

  /// Fracción 0..1 (abajo..arriba) de un valor en dB.
  static double fractionOf(double dB) =>
      ((dB - minDb) / (maxDb - minDb)).clamp(0.0, 1.0);

  /// dB de una posición vertical `y` (0 = arriba) en un carril de alto `height`, con imán a 0.
  static double dbAt(double y, double height) {
    final double f = 1 - (y / height).clamp(0.0, 1.0);
    final double d = minDb + f * (maxDb - minDb);
    return d.abs() < snapDb ? 0 : d;
  }

  static double step(double dB, int direction) =>
      (dB + direction * stepDb).clamp(minDb, maxDb);

  @override
  State<TfFader> createState() => _TfFaderState();
}

class _TfFaderState extends State<TfFader> {
  FocusNode? _own;
  FocusNode get _node => widget.focusNode ?? (_own ??= FocusNode());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  void _set(double d) {
    if (d != widget.dB) widget.onChanged(d);
  }

  void _pointer(PointerEvent e) => _set(TfFader.dbAt(e.localPosition.dy, widget.height));

  KeyEventResult _key(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final LogicalKeyboardKey k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowRight) {
      _set(TfFader.step(widget.dB, 1));
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.arrowLeft) {
      _set(TfFader.step(widget.dB, -1));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final double up = TfFader.step(widget.dB, 1);
    final double down = TfFader.step(widget.dB, -1);
    return Semantics(
      slider: true,
      label: widget.semanticLabel,
      value: widget.semanticValue(widget.dB),
      increasedValue: widget.semanticValue(up),
      decreasedValue: widget.semanticValue(down),
      onIncrease: () => _set(up),
      onDecrease: () => _set(down),
      child: Focus(
        focusNode: _node,
        autofocus: widget.autofocus,
        onKeyEvent: _key,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (PointerDownEvent e) {
              _node.requestFocus();
              _pointer(e);
            },
            onPointerMove: _pointer,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: () => _set(0),
              child: CustomPaint(
                size: Size(TfSize.faderWidth, widget.height),
                painter: _FaderPainter(widget.dB),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FaderPainter extends CustomPainter {
  _FaderPainter(this.dB);
  final double dB;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect track = RRect.fromRectAndRadius(
      Rect.fromLTWH((size.width - TfSize.faderTrackWidth) / 2, 0, TfSize.faderTrackWidth, size.height),
      const Radius.circular(TfRadius.r3),
    );
    canvas.drawRRect(track, Paint()..color = TfColors.bg);

    final double cy = size.height * (1 - TfFader.fractionOf(dB));
    final RRect knob = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, cy - TfSize.faderKnobHeight / 2, size.width, TfSize.faderKnobHeight),
      const Radius.circular(TfRadius.xs),
    );
    canvas.drawRRect(knob.shift(TfShadow.knob.offset), TfShadow.knob.toPaint());
    canvas.drawRRect(knob, Paint()..color = TfColors.text2);
  }

  @override
  bool shouldRepaint(_FaderPainter old) => old.dB != dB;
}
