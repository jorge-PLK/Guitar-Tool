import 'package:flutter/widgets.dart';

import '../theme/icons.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Campo de texto `.plain` dentro de contenedor propio (`searchField` / `linkField`).
/// Búsqueda ([search] = true): alto 36, h 12, icono lupa y botón de borrar (`muted`).
/// Enlace ([search] = false): alto 32, h 10, sin iconos. Fondo `field`, borde `fieldLine`,
/// radio 8. Sin anillo de foco propio. `hint` y `clearSemanticLabel` ya localizados.
class TfTextField extends StatefulWidget {
  const TfTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.hint,
    this.onChanged,
    this.onSubmitted,
    this.search = false,
    this.width,
    this.enabled = true,
    this.clearSemanticLabel,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool search;
  final double? width;
  final bool enabled;
  final String? clearSemanticLabel;

  @override
  State<TfTextField> createState() => _TfTextFieldState();
}

class _TfTextFieldState extends State<TfTextField> {
  TextEditingController? _ownController;
  FocusNode? _ownFocus;

  TextEditingController get _controller =>
      widget.controller ?? (_ownController ??= TextEditingController());
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(TfTextField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      (old.controller ?? _ownController)?.removeListener(_onText);
      _controller.addListener(_onText);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onText);
    _ownController?.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  void _onText() => setState(() {});

  void _clear() {
    _controller.clear();
    widget.onChanged?.call('');
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final TextStyle style = TfText.body().copyWith(
      color: TfColors.text,
      decoration: TextDecoration.none,
    );
    final bool empty = _controller.text.isEmpty;
    final Widget field = Stack(
      alignment: Alignment.centerLeft,
      children: <Widget>[
        if (empty && widget.hint != null)
          IgnorePointer(
            child: Text(
              widget.hint!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style.copyWith(color: TfColors.muted),
            ),
          ),
        EditableText(
          controller: _controller,
          focusNode: _focus,
          style: style,
          cursorColor: TfColors.accent,
          backgroundCursorColor: TfColors.muted,
          selectionColor: TfColors.accent.withValues(alpha: TfOpacity.tint35),
          readOnly: !widget.enabled,
          maxLines: 1,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
        ),
      ],
    );
    Widget body = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.enabled ? _focus.requestFocus : null,
      child: Container(
        width: widget.width,
        height: widget.search ? TfSize.controlMd : TfSize.linkFieldHeight,
        padding: EdgeInsets.symmetric(
          horizontal: widget.search ? TfSpace.s12 : TfSpace.s10,
        ),
        decoration: BoxDecoration(
          color: TfColors.field,
          borderRadius: BorderRadius.circular(TfRadius.field),
          border: Border.all(color: TfColors.fieldLine, width: TfStroke.hairline),
        ),
        child: Row(
          children: <Widget>[
            if (widget.search) ...<Widget>[
              const TfIconView(TfIcon.magnifyingglass, size: TfSize.fieldIcon, color: TfColors.muted),
              const SizedBox(width: TfSpace.s8),
            ],
            Expanded(child: field),
            if (widget.search && !empty && widget.enabled) ...<Widget>[
              const SizedBox(width: TfSpace.s8),
              Semantics(
                button: true,
                label: widget.clearSemanticLabel,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _clear,
                    child: const TfIconView(
                      TfIcon.xmarkCircleFill,
                      size: TfSize.fieldIcon,
                      color: TfColors.muted,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
    if (!widget.enabled) {
      body = ExcludeFocus(child: Opacity(opacity: TfOpacity.disabled, child: body));
    }
    return body;
  }
}
