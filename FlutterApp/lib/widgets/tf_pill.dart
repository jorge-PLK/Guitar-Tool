import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Pastilla de pista (`TabScreen.swift:213-239`): cápsula de alto 34, padding h 14.
/// Activa: texto `accent`, fondo `accentBg`, borde `accent`. Inactiva: `text2`/`field`/`fieldLine`.
/// Pendiente: sin fondo, texto `muted`, borde `fieldLine` discontinuo (`dash [3]`), sin gesto.
class TfPill extends StatelessWidget {
  const TfPill({
    super.key,
    required this.label,
    this.active = false,
    this.pending = false,
    this.onPressed,
    this.iconBuilder,
    this.trailing,
    this.semanticLabel,
  });

  final String label;
  final bool active;
  final bool pending;
  final VoidCallback? onPressed;

  /// Icono (12) dado el color del texto de la pastilla.
  final Widget Function(Color color)? iconBuilder;

  /// Adorno tras el texto (p. ej. altavoz de «escuchando»).
  final Widget? trailing;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final Color fg = pending ? TfColors.muted : (active ? TfColors.accent : TfColors.text2);
    final TextStyle style = pending
        ? TfText.body(TfSize.font13)
        : TfText.body(TfSize.font13, active ? TfWeight.semibold : TfWeight.medium);
    final Widget content = _PillBody(
      height: TfSize.pillHeight,
      padding: TfSpace.s14,
      radius: TfRadius.pill,
      fill: pending ? null : (active ? TfColors.accentBg : TfColors.field),
      border: pending ? TfColors.fieldLine : (active ? TfColors.accent : TfColors.fieldLine),
      dashed: pending,
      label: label,
      style: style.copyWith(color: fg),
      icon: iconBuilder?.call(fg),
      trailing: trailing,
    );
    return Semantics(
      button: !pending,
      selected: active,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      onTap: pending ? null : onPressed,
      child: pending
          ? content
          : MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onPressed, child: content),
            ),
    );
  }
}

/// Botón compacto de cabecera (`markButton`, BackingTimeline.swift:122-130): alto 28, radio 8, padding h 10.
/// Activo: texto `accent`, fondo `accentBg`, borde `accent @0.6`. Inactivo: `text2`/`field`/`fieldLine`.
class TfCompactPill extends StatelessWidget {
  const TfCompactPill({
    super.key,
    required this.label,
    this.active = false,
    this.onPressed,
    this.iconBuilder,
    this.semanticLabel,
  });

  final String label;
  final bool active;
  final VoidCallback? onPressed;
  final Widget Function(Color color)? iconBuilder;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final Color fg = active ? TfColors.accent : TfColors.text2;
    return Semantics(
      button: true,
      selected: active,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      onTap: onPressed,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: _PillBody(
            height: TfSize.controlSm,
            padding: TfSpace.s10,
            radius: TfRadius.field,
            fill: active ? TfColors.accentBg : TfColors.field,
            border: active ? TfColors.accent.withValues(alpha: TfOpacity.borderAccent) : TfColors.fieldLine,
            dashed: false,
            label: label,
            style: TfText.body(TfSize.font12, TfWeight.medium).copyWith(color: fg),
            icon: iconBuilder?.call(fg),
          ),
        ),
      ),
    );
  }
}

class _PillBody extends StatelessWidget {
  const _PillBody({
    required this.height,
    required this.padding,
    required this.radius,
    required this.fill,
    required this.border,
    required this.dashed,
    required this.label,
    required this.style,
    this.icon,
    this.trailing,
  });

  final double height;
  final double padding;
  final double radius;
  final Color? fill;
  final Color border;
  final bool dashed;
  final String label;
  final TextStyle style;
  final Widget? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PillPainter(radius: radius, fill: fill, border: border, dashed: dashed),
      child: SizedBox(
        height: height,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: padding),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: TfSpace.s6,
            children: <Widget>[
              ?icon,
              Text(label, style: style, maxLines: 1, softWrap: false),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _PillPainter extends CustomPainter {
  _PillPainter({required this.radius, required this.fill, required this.border, required this.dashed});

  final double radius;
  final Color? fill;
  final Color border;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final double r = radius.clamp(0.0, size.height / 2);
    // El trazo de SwiftUI se centra en el borde; se dibuja a media línea hacia dentro como BoxDecoration.
    final RRect rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(r));
    if (fill != null) canvas.drawRRect(rrect, Paint()..color = fill!);
    final RRect edge = rrect.deflate(TfStroke.hairline / 2);
    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = TfStroke.hairline
      ..color = border;
    if (!dashed) {
      canvas.drawRRect(edge, stroke);
      return;
    }
    final Path path = Path()..addRRect(edge);
    for (final ui.PathMetric m in path.computeMetrics()) {
      double d = 0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + TfStroke.dash), stroke);
        d += TfStroke.dash * 2;
      }
    }
  }

  @override
  bool shouldRepaint(_PillPainter old) =>
      old.radius != radius || old.fill != fill || old.border != border || old.dashed != dashed;
}
