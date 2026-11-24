import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/icons.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Base táctil de los botones del kit: pulsado, hover (opcional) y activación con Intro/Espacio.
/// Sin anillo de foco visible (SwiftUI `.plain`). `onPressed == null` = deshabilitado.
class _TfPress extends StatefulWidget {
  const _TfPress({
    required this.onPressed,
    required this.builder,
    this.semanticLabel,
    this.hover = false,
  });

  final VoidCallback? onPressed;
  final Widget Function(BuildContext context, bool pressed, bool hovered) builder;
  final String? semanticLabel;
  final bool hover;

  @override
  State<_TfPress> createState() => _TfPressState();
}

class _TfPressState extends State<_TfPress> {
  bool _pressed = false;
  bool _hover = false;

  static const Map<ShortcutActivator, Intent> _keys = <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
  };

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: SystemMouseCursors.basic,
        shortcuts: _keys,
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            widget.onPressed?.call();
            return null;
          }),
        },
        onShowHoverHighlight: widget.hover
            ? (bool v) {
                if (_hover != v) setState(() => _hover = v);
              }
            : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => _setPressed(true) : null,
          onTapUp: enabled ? (_) => _setPressed(false) : null,
          onTapCancel: enabled ? () => _setPressed(false) : null,
          onTap: widget.onPressed,
          child: widget.builder(context, enabled && _pressed, enabled && _hover),
        ),
      ),
    );
  }
}

TextStyle _label(double size, TfWeight weight, Color color) =>
    TfText.body(size, weight).copyWith(color: color, decoration: TextDecoration.none);

Widget _labelRow(String text, TextStyle style) => Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Flexible(child: Text(text, style: style, maxLines: 1, softWrap: false, overflow: TextOverflow.clip)),
      ],
    );

/// Botón primario: `PrimaryButton` (Theme.swift:60). La variante [TfPrimaryButton.apply] es
/// `ApplyButton` (GuitarOptionsViews.swift:44): alto 28, body 13 semibold, padding h 16.
class TfPrimaryButton extends StatelessWidget {
  const TfPrimaryButton({super.key, required this.label, required this.onPressed})
      : height = TfSize.controlLg,
        fontSize = TfSize.font14,
        hPadding = TfSpace.s20;

  const TfPrimaryButton.apply({super.key, required this.label, required this.onPressed})
      : height = TfSize.controlSm,
        fontSize = TfSize.font13,
        hPadding = TfSpace.s16;

  final String label;
  final VoidCallback? onPressed;
  final double height;
  final double fontSize;
  final double hPadding;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    return _TfPress(
      onPressed: onPressed,
      semanticLabel: label,
      builder: (BuildContext context, bool pressed, bool hovered) {
        final Color bg = enabled
            ? TfColors.accent.withValues(alpha: pressed ? TfOpacity.pressedPrimary : 1)
            : TfColors.neutralBg;
        return Container(
          height: height,
          padding: EdgeInsets.symmetric(horizontal: hPadding),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(TfRadius.control)),
          foregroundDecoration: enabled
              ? null
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(TfRadius.control),
                  border: Border.all(color: TfColors.fieldLine, width: TfStroke.hairline),
                ),
          child: _labelRow(
            label,
            _label(fontSize, TfWeight.semibold, enabled ? TfColors.accentInk : TfColors.muted),
          ),
        );
      },
    );
  }
}

/// Botón secundario: `SecondaryButton` (Theme.swift:72). Alturas usadas: 44, 36, 28.
class TfSecondaryButton extends StatelessWidget {
  const TfSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.height = TfSize.controlLg,
  });

  final String label;
  final VoidCallback? onPressed;
  final double height;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    return _TfPress(
      onPressed: onPressed,
      semanticLabel: label,
      builder: (BuildContext context, bool pressed, bool hovered) => _secondaryBox(
        enabled: enabled,
        pressed: pressed,
        height: height,
        child: _labelRow(label, _label(TfSize.font14, TfWeight.medium, enabled ? TfColors.text : TfColors.muted)),
      ),
    );
  }
}

Widget _secondaryBox({
  required bool enabled,
  required bool pressed,
  required double height,
  required Widget child,
  double? width,
}) =>
    Opacity(
      opacity: enabled ? 1 : TfOpacity.disabled,
      child: Container(
        height: height,
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: TfSpace.s16),
        decoration: BoxDecoration(
          color: TfColors.field.withValues(alpha: pressed ? TfOpacity.pressedSecondary : 1),
          borderRadius: BorderRadius.circular(TfRadius.control),
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(TfRadius.control),
          border: Border.all(color: TfColors.fieldLine, width: TfStroke.hairline),
        ),
        child: child,
      ),
    );

/// Variantes de [TfIconButton] (tokens-componentes.md §3.1).
enum TfIconButtonKind {
  /// `TrashRowButton`: 36x36, radio 10, icono 14 `muted`, hover `danger`.
  row,

  /// `SecondaryButton(height: 36)` con icono: ancho = icono + 2x16, icono `text`, sin hover.
  secondary,

  /// `nudge`: 30x24, radio 6, icono 11 `text`.
  nudge,
}

class TfIconButton extends StatelessWidget {
  const TfIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.kind = TfIconButtonKind.row,
    this.semanticLabel,
  });

  final TfIcon icon;
  final VoidCallback? onPressed;
  final TfIconButtonKind kind;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    return _TfPress(
      onPressed: onPressed,
      semanticLabel: semanticLabel,
      hover: kind == TfIconButtonKind.row,
      builder: (BuildContext context, bool pressed, bool hovered) {
        switch (kind) {
          case TfIconButtonKind.secondary:
            return _secondaryBox(
              enabled: enabled,
              pressed: pressed,
              height: TfSize.controlMd,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  TfIconView(icon, size: TfSize.iconButtonIcon, color: enabled ? TfColors.text : TfColors.muted),
                ],
              ),
            );
          case TfIconButtonKind.row:
            return _plainBox(
              enabled: enabled,
              width: TfSize.controlMd,
              height: TfSize.controlMd,
              radius: TfRadius.control,
              icon: icon,
              iconSize: TfSize.iconButtonIcon,
              color: hovered ? TfColors.danger : TfColors.muted,
            );
          case TfIconButtonKind.nudge:
            return _plainBox(
              enabled: enabled,
              width: TfSize.nudgeWidth,
              height: TfSize.nudgeHeight,
              radius: TfRadius.small,
              icon: icon,
              iconSize: TfSize.nudgeIcon,
              color: TfColors.text,
            );
        }
      },
    );
  }

  Widget _plainBox({
    required bool enabled,
    required double width,
    required double height,
    required double radius,
    required TfIcon icon,
    required double iconSize,
    required Color color,
  }) =>
      Opacity(
        opacity: enabled ? 1 : TfOpacity.disabled,
        child: Container(
          width: width,
          height: height,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: TfColors.field, borderRadius: BorderRadius.circular(radius)),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: TfColors.fieldLine, width: TfStroke.hairline),
          ),
          child: TfIconView(icon, size: iconSize, color: color),
        ),
      );
}
