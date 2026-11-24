import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// Contenedor de scroll con barra fina superpuesta, sin pista: `fieldLine` en reposo y `muted`
/// con el ratón encima. [builder] construye el scrollable (ListView, SingleChildScrollView…) y
/// debe usar el [ScrollController] que recibe.
class TfScroll extends StatefulWidget {
  const TfScroll({
    super.key,
    required this.builder,
    this.controller,
    this.alwaysVisible = false,
  });

  final Widget Function(BuildContext context, ScrollController controller) builder;

  /// Si es null, el widget crea y libera el suyo.
  final ScrollController? controller;
  final bool alwaysVisible;

  @override
  State<TfScroll> createState() => _TfScrollState();
}

class _TfScrollState extends State<TfScroll> {
  ScrollController? _own;
  bool _hover = false;

  ScrollController get _controller =>
      widget.controller ?? (_own ??= ScrollController());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ScrollController controller = _controller;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: RawScrollbar(
        controller: controller,
        thumbVisibility: widget.alwaysVisible,
        trackVisibility: false,
        thickness: TfSpace.s6,
        radius: const Radius.circular(TfRadius.r3),
        thumbColor: _hover ? TfColors.muted : TfColors.fieldLine,
        child: widget.builder(context, controller),
      ),
    );
  }
}
