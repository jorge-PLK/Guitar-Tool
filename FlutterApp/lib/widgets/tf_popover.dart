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
class TfPopover extends StatefulWidget {
  const TfPopover({
    super.key,
    required this.controller,
    required this.child,
    required this.popoverBuilder,
    this.anchorAlignment = Alignment.bottomLeft,
    this.popoverAlignment = Alignment.topLeft,
    this.offset = const Offset(0, TfSpace.s4),
    this.onClosed,
  });

  final TfPopoverController controller;

  /// El ancla (normalmente un botón).
  final Widget child;
  final WidgetBuilder popoverBuilder;
  final Alignment anchorAlignment;
  final Alignment popoverAlignment;
  final Offset offset;

  /// Se llama al cerrar por Esc o clic fuera.
  final VoidCallback? onClosed;

  @override
  State<TfPopover> createState() => _TfPopoverState();
}

class _TfPopoverState extends State<TfPopover> {
  final LayerLink _link = LayerLink();

  void _close() {
    widget.controller.hide();
    widget.onClosed?.call();
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
            CompositedTransformFollower(
              link: _link,
              targetAnchor: widget.anchorAlignment,
              followerAnchor: widget.popoverAlignment,
              offset: widget.offset,
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
                  child: widget.popoverBuilder(overlayContext),
                ),
              ),
            ),
          ],
        );
      },
      child: CompositedTransformTarget(link: _link, child: widget.child),
    );
  }
}
