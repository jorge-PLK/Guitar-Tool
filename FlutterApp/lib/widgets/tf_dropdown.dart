import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/icons.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Opción del desplegable: valor y texto ya localizado.
class TfDropdownItem<T> {
  const TfDropdownItem({required this.value, required this.label});

  final T value;
  final String label;
}

/// Selector `.pickerStyle(.menu)`: botón con la etiqueta y chevrones arriba/abajo, y menú
/// emergente propio (fondo `card`, borde `line`, radio 10). Sin `width` mide como la opción
/// más ancha; con `width` fijo la etiqueta se recorta con «…». Teclado: Espacio/Intro/flechas
/// abren; con el menú abierto flechas mueven, Intro elige, Esc cierra. `onChanged == null` lo deshabilita.
class TfDropdown<T> extends StatefulWidget {
  const TfDropdown({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.width,
    this.placeholder = '',
  });

  final List<TfDropdownItem<T>> items;
  final T? value;
  final ValueChanged<T>? onChanged;
  final double? width;

  /// Texto cuando `value` no está entre las opciones.
  final String placeholder;

  @override
  State<TfDropdown<T>> createState() => _TfDropdownState<T>();
}

class _TfDropdownState<T> extends State<TfDropdown<T>> {
  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();
  final FocusNode _focus = FocusNode();
  bool _open = false;
  int _highlight = 0;
  double _menuWidth = 0;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _close();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  int get _selected => widget.items.indexWhere((TfDropdownItem<T> i) => i.value == widget.value);

  TextStyle get _label => TfText.body(13).copyWith(
        color: TfColors.text,
        decoration: TextDecoration.none,
      );

  void _show() {
    if (_open || widget.items.isEmpty) return;
    final double buttonWidth = (context.size ?? Size.zero).width;
    double widest = 0;
    for (final TfDropdownItem<T> i in widget.items) {
      final TextPainter p = TextPainter(
        text: TextSpan(text: i.label, style: _label),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      if (p.width > widest) widest = p.width;
      p.dispose();
    }
    const double chrome = 2 * TfSpace.s4 + 2 * TfStroke.hairline + 2 * TfSpace.s8 +
        TfSize.checkboxMark + TfSpace.s6;
    _menuWidth = widest + chrome > buttonWidth ? widest + chrome : buttonWidth;
    _highlight = _selected < 0 ? 0 : _selected;
    _open = true;
    _portal.show();
    setState(() {});
  }

  void _close() {
    if (!_open) return;
    _open = false;
    if (_portal.isShowing) _portal.hide();
    if (mounted) setState(() {});
  }

  void _choose(int index) {
    final T v = widget.items[index].value;
    _close();
    widget.onChanged?.call(v);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final LogicalKeyboardKey k = event.logicalKey;
    if (!_open) {
      if (k == LogicalKeyboardKey.space ||
          k == LogicalKeyboardKey.enter ||
          k == LogicalKeyboardKey.arrowDown ||
          k == LogicalKeyboardKey.arrowUp) {
        _show();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final int n = widget.items.length;
    if (k == LogicalKeyboardKey.arrowDown) {
      setState(() => _highlight = (_highlight + 1).clamp(0, n - 1));
    } else if (k == LogicalKeyboardKey.arrowUp) {
      setState(() => _highlight = (_highlight - 1).clamp(0, n - 1));
    } else if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      _choose(_highlight);
    } else if (k == LogicalKeyboardKey.escape) {
      _close();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Widget _menu(BuildContext context) {
    final int selected = _selected;
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _close),
        ),
        Align(
          alignment: Alignment.topLeft,
          child: CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topLeft,
            offset: const Offset(0, TfSpace.s4),
            child: Container(
              width: _menuWidth,
              constraints: const BoxConstraints(maxHeight: TfSize.dropdownMenuMaxHeight),
              padding: const EdgeInsets.all(TfSpace.s4),
              decoration: BoxDecoration(
                color: TfColors.card,
                borderRadius: BorderRadius.circular(TfRadius.control),
                border: Border.all(color: TfColors.line, width: TfStroke.hairline),
                boxShadow: const <BoxShadow>[TfShadow.countdown],
              ),
              child: SingleChildScrollView(
                child: Column(
                  children: <Widget>[
                    for (int i = 0; i < widget.items.length; i++)
                      _menuItem(i, i == selected),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _menuItem(int i, bool selected) {
    final bool hot = i == _highlight;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _highlight = i),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _choose(i),
        child: Container(
          height: TfSize.dropdownMenuItem,
          padding: const EdgeInsets.symmetric(horizontal: TfSpace.s8),
          decoration: BoxDecoration(
            color: hot ? TfColors.accent : null,
            borderRadius: BorderRadius.circular(TfRadius.small),
          ),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: TfSize.checkboxMark,
                child: selected
                    ? TfIconView(
                        TfIcon.checkmark,
                        size: TfSize.checkboxMark,
                        color: hot ? TfColors.accentInk : TfColors.accent,
                      )
                    : null,
              ),
              const SizedBox(width: TfSpace.s6),
              Expanded(
                child: Text(
                  widget.items[i].label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _label.copyWith(color: hot ? TfColors.accentInk : TfColors.text),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onChanged != null;
    final int sel = _selected;
    final Widget current = Text(
      sel < 0 ? widget.placeholder : widget.items[sel].label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: _label.copyWith(color: sel < 0 ? TfColors.muted : TfColors.text),
    );
    final Widget labelArea = widget.width != null
        ? Expanded(child: current)
        : Stack(
            alignment: Alignment.centerLeft,
            children: <Widget>[
              for (final TfDropdownItem<T> i in widget.items)
                Visibility(
                  visible: false,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: Text(i.label, maxLines: 1, style: _label),
                ),
              current,
            ],
          );
    Widget button = Container(
      width: widget.width,
      height: TfSize.dropdownHeight,
      padding: const EdgeInsets.symmetric(horizontal: TfSize.dropdownPadH),
      decoration: BoxDecoration(
        color: TfColors.nativeControl,
        borderRadius: BorderRadius.circular(TfRadius.native),
      ),
      child: Row(
        mainAxisSize: widget.width != null ? MainAxisSize.max : MainAxisSize.min,
        children: <Widget>[
          labelArea,
          const SizedBox(width: TfSize.dropdownGap),
          const TfIconView(
            TfIcon.chevronUpChevronDown,
            size: TfSize.dropdownChevron,
            color: TfColors.text,
          ),
        ],
      ),
    );
    if (!enabled) {
      return Opacity(opacity: TfOpacity.disabled, child: button);
    }
    button = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _focus.requestFocus();
          _open ? _close() : _show();
        },
        child: button,
      ),
    );
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _menu,
      child: CompositedTransformTarget(
        link: _link,
        child: Focus(focusNode: _focus, onKeyEvent: _onKey, child: button),
      ),
    );
  }
}
