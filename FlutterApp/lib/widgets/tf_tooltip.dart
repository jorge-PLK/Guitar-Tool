import 'dart:async';

import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Etiqueta emergente (`.help` de SwiftUI): aparece tras ~1 s con el ratón encima y se va al
/// salir o al pulsar. El texto entra por [message].
class TfTooltip extends StatefulWidget {
  const TfTooltip({
    super.key,
    required this.message,
    required this.child,
    this.waitDuration = const Duration(seconds: 1),
  });

  final String message;
  final Widget child;
  final Duration waitDuration;

  @override
  State<TfTooltip> createState() => _TfTooltipState();
}

class _TfTooltipState extends State<TfTooltip> {
  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();
  Timer? _timer;

  void _arm() {
    _timer?.cancel();
    _timer = Timer(widget.waitDuration, () {
      if (mounted) _portal.show();
    });
  }

  void _disarm() {
    _timer?.cancel();
    _timer = null;
    if (_portal.isShowing) _portal.hide();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (BuildContext c) {
        return Stack(children: <Widget>[
          CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.bottomCenter,
            followerAnchor: Alignment.topCenter,
            offset: const Offset(0, TfSpace.s6),
            child: IgnorePointer(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: TfSize.tooltipMaxWidth),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: TfColors.field,
                    borderRadius: BorderRadius.circular(TfRadius.small),
                    border: Border.all(
                      color: TfColors.fieldLine,
                      width: TfStroke.hairline,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: TfSpace.s8,
                      vertical: TfSpace.s4,
                    ),
                    child: Text(
                      widget.message,
                      style: TfText.body(12).copyWith(color: TfColors.text),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ]);
      },
      child: CompositedTransformTarget(
        link: _link,
        child: Listener(
          onPointerDown: (_) => _disarm(),
          child: MouseRegion(
            onEnter: (_) => _arm(),
            onExit: (_) => _disarm(),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
