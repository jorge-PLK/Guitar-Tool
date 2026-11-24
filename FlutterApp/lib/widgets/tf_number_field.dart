import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Campo numérico con borde redondeado de macOS. Valida número (acepta `.` y `,`),
/// confirma con Intro o al perder el foco y revierte si el texto no es un número.
/// Fuera de [min, max] se ajusta al límite. Foco: halo del acento. `onChanged == null` lo deshabilita.
class TfNumberField extends StatefulWidget {
  const TfNumberField({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = double.negativeInfinity,
    this.max = double.infinity,
    this.decimals = 0,
    this.decimalSeparator = '.',
    this.width = TfSize.numberFieldWidth,
    this.focusNode,
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final double min;
  final double max;

  /// Decimales mostrados (0 = entero).
  final int decimals;
  final String decimalSeparator;
  final double width;
  final FocusNode? focusNode;

  @override
  State<TfNumberField> createState() => _TfNumberFieldState();
}

class _TfNumberFieldState extends State<TfNumberField> {
  late final TextEditingController _controller;
  FocusNode? _ownFocus;
  bool _focused = false;

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.value));
    _focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(TfNumberField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && old.value != widget.value) {
      _controller.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _ownFocus?.dispose();
    _controller.dispose();
    super.dispose();
  }

  String _format(double v) =>
      v.toStringAsFixed(widget.decimals).replaceFirst('.', widget.decimalSeparator);

  void _onFocus() {
    final bool has = _focus.hasFocus;
    if (has == _focused) return;
    setState(() => _focused = has);
    if (has) {
      _controller.selection = TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
    } else {
      _commit();
    }
  }

  void _commit() {
    final double? parsed = double.tryParse(_controller.text.trim().replaceAll(',', '.'));
    if (parsed == null || !parsed.isFinite) {
      _controller.text = _format(widget.value);
      return;
    }
    final double v = parsed.clamp(widget.min, widget.max).toDouble();
    _controller.text = _format(v);
    if (v != widget.value) widget.onChanged?.call(v);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
      _controller.text = _format(widget.value);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onChanged != null;
    final TextStyle style = TfText.body(14, TfWeight.medium).copyWith(
      color: TfColors.text,
      decoration: TextDecoration.none,
    );
    final Widget body = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? _focus.requestFocus : null,
      child: Container(
        width: widget.width,
        height: TfSize.numberFieldHeight,
        padding: const EdgeInsets.symmetric(horizontal: TfSpace.s6),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: TfColors.nativeFieldBg,
          borderRadius: BorderRadius.circular(TfRadius.xs),
          border: Border.all(
            color: _focused ? TfColors.accent : TfColors.nativeFieldLine,
            width: TfStroke.hairline,
          ),
          boxShadow: _focused
              ? <BoxShadow>[
                  BoxShadow(
                    color: TfColors.accent.withValues(alpha: TfOpacity.half),
                    spreadRadius: TfSize.focusHalo,
                  ),
                ]
              : null,
        ),
        child: EditableText(
          controller: _controller,
          focusNode: _focus,
          style: style,
          cursorColor: TfColors.accent,
          backgroundCursorColor: TfColors.muted,
          selectionColor: TfColors.accent.withValues(alpha: TfOpacity.tint35),
          readOnly: !enabled,
          maxLines: 1,
          textAlign: TextAlign.right,
          keyboardType: TextInputType.numberWithOptions(
            signed: widget.min < 0,
            decimal: widget.decimals > 0,
          ),
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
          ],
          onEditingComplete: _commit,
        ),
      ),
    );
    if (!enabled) {
      return ExcludeFocus(child: Opacity(opacity: TfOpacity.disabled, child: body));
    }
    return Focus(onKeyEvent: _onKey, canRequestFocus: false, skipTraversal: true, child: body);
  }
}
