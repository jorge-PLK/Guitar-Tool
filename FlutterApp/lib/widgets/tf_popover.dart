import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// Abre y cierra un [TfPopover] desde fuera.
class TfPopoverController {
  final OverlayPortalController _portal = OverlayPortalController();

  bool get isShowing => _portal.isShowing;
  void show() => _portal.show();
  void hide() => _portal.hide();
  void toggle() => _portal.toggle();
}

/// Superficie de popover y menú: fondo `card`, borde `line`, radio 10, sin flecha.
class TfPopoverSurface extends StatelessWidget {
  const TfPopoverSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TfColors.card,
        borderRadius: BorderRadius.circular(TfRadius.control),
        border: Border.all(color: TfColors.line, width: TfStroke.hairline),
      ),
      child: child,
    );
  }
}

/// Popover anclado a [child] con `OverlayPortal` (docs/flutter/tokens-componentes.md §3.1).
/// Se cierra con Esc o con un clic fuera (el clic fuera no llega a lo de debajo).
/// Se coloca como TfDropdown: debajo del ancla si cabe, si no encima, y si no en el lado con
/// más sitio con scroll; horizontalmente no se sale de la ventana. Cerrado no deja nada montado.
class TfPopover extends StatefulWidget {
  const TfPopover({
    super.key,
    required this.controller,
    required this.child,
    required this.popoverBuilder,
    this.anchorAlignment = Alignment.bottomLeft,
    this.popoverAlignment = Alignment.topLeft,
    this.offset = const Offset(0, TfSpace.s4),
    this.pointAnchor,
    this.onClosed,
  });

  final TfPopoverController controller;

  /// El ancla (normalmente un botón).
  final Widget child;
  final WidgetBuilder popoverBuilder;
  final Alignment anchorAlignment;
  final Alignment popoverAlignment;
  final Offset offset;

  /// Si se da, el ancla es este punto (relativo a la esquina superior izquierda de [child]).
  final Offset? pointAnchor;

  /// Se llama al cerrar por Esc o clic fuera.
  final VoidCallback? onClosed;

  @override
  State<TfPopover> createState() => _TfPopoverState();
}

class _TfPopoverState extends State<TfPopover> {
  void _close() {
    widget.controller.hide();
    widget.onClosed?.call();
  }

  Rect _target() {
    final RenderObject? box = context.findRenderObject();
    final RenderObject? overlay = Overlay.maybeOf(context)?.context.findRenderObject();
    if (box is! RenderBox || overlay is! RenderBox || !box.hasSize) return Rect.zero;
    final Rect r = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
    final Offset? p = widget.pointAnchor;
    return p == null ? r : (r.topLeft + p) & Size.zero;
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: widget.controller._portal,
      overlayChildBuilder: (BuildContext overlayContext) {
        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _close,
                onSecondaryTap: _close,
              ),
            ),
            Positioned.fill(
              child: CustomSingleChildLayout(
                delegate: _PopoverLayout(
                  target: _target(),
                  anchor: widget.anchorAlignment,
                  follower: widget.popoverAlignment,
                  offset: widget.offset,
                ),
                child: Focus(
                  autofocus: true,
                  onKeyEvent: (FocusNode node, KeyEvent event) {
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.escape) {
                      _close();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TfPopoverSurface(
                    child: SingleChildScrollView(
                      child: widget.popoverBuilder(overlayContext),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      child: widget.child,
    );
  }
}

/// Coloca el panel respecto a [target] (coordenadas del overlay). El hijo se mide con todo el
/// sitio del lado mayor; luego va debajo si cabe, si no encima, y si no en el lado con más sitio.
class _PopoverLayout extends SingleChildLayoutDelegate {
  const _PopoverLayout({
    required this.target,
    required this.anchor,
    required this.follower,
    required this.offset,
  });

  final Rect target;
  final Alignment anchor;
  final Alignment follower;
  final Offset offset;

  static double _frac(double a) => (a + 1) / 2;

  double _roomBelow(Size size) =>
      size.height - TfSpace.s8 - (target.top + _frac(anchor.y) * target.height + offset.dy);

  double _roomAbove() =>
      target.top + _frac(-anchor.y) * target.height - offset.dy - TfSpace.s8;

  bool _opensDown(Size size, double h) {
    final double below = _roomBelow(size);
    if (h <= below) return true;
    final double above = _roomAbove();
    if (h <= above) return false;
    return below >= above;
  }

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final Size size = constraints.biggest;
    final double room = _roomBelow(size) > _roomAbove() ? _roomBelow(size) : _roomAbove();
    return BoxConstraints(maxWidth: size.width, maxHeight: room < 0 ? 0 : room);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    double x = target.left +
        _frac(anchor.x) * target.width +
        offset.dx -
        _frac(follower.x) * childSize.width;
    final double maxX = size.width - childSize.width;
    x = x > maxX ? maxX : x;
    if (x < 0) x = 0;
    final double y = _opensDown(size, childSize.height)
        ? target.top +
            _frac(anchor.y) * target.height +
            offset.dy -
            _frac(follower.y) * childSize.height
        : target.top +
            _frac(-anchor.y) * target.height -
            offset.dy -
            _frac(-follower.y) * childSize.height;
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_PopoverLayout old) =>
      old.target != target ||
      old.anchor != anchor ||
      old.follower != follower ||
      old.offset != offset;
}
