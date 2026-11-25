import 'package:flutter/widgets.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/fmt.dart';
import 'package:toneforge/theme/tokens.dart';

/// Barra de posición (BT:562-613): pista, progreso, bucle y cabezal. Solo traduce posición → tiempo.
class PositionBar extends StatelessWidget {
  const PositionBar({
    super.key,
    required this.position,
    required this.duration,
    this.loopStart,
    this.loopEnd,
    this.onSeek,
  });

  static const double height = 22;

  /// Salto de VoiceOver (`accessibilityAdjustableAction`, BackingTimeline.swift).
  static const double a11yStep = 5;

  final double position;
  final double duration;
  final double? loopStart;
  final double? loopEnd;
  final void Function(double seconds)? onSeek;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
      final double w = c.maxWidth;
      void seek(double dx) {
        if (onSeek == null || duration <= 0 || w <= 0) return;
        onSeek!((dx / w).clamp(0.0, 1.0) * duration);
      }

      void nudge(double delta) {
        if (onSeek == null || duration <= 0) return;
        onSeek!((position + delta).clamp(0.0, duration));
      }

      final AppLocalizations? l = Localizations.of<AppLocalizations>(context, AppLocalizations);
      String at(double t) => l!.backing_positionValueA11y(TfFmt.clock(t), TfFmt.clock(duration));
      final Widget bar = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (TapDownDetails d) => seek(d.localPosition.dx),
        onHorizontalDragStart: (DragStartDetails d) => seek(d.localPosition.dx),
        onHorizontalDragUpdate: (DragUpdateDetails d) => seek(d.localPosition.dx),
        child: CustomPaint(
          size: Size(w, height),
          painter: PositionBarPainter(
            position: position,
            duration: duration,
            loopStart: loopStart,
            loopEnd: loopEnd,
          ),
        ),
      );
      if (l == null) return bar;
      return Semantics(
        slider: true,
        label: l.backing_positionA11y,
        value: at(position),
        increasedValue: at((position + a11yStep).clamp(0.0, duration)),
        decreasedValue: at((position - a11yStep).clamp(0.0, duration)),
        onIncrease: () => nudge(a11yStep),
        onDecrease: () => nudge(-a11yStep),
        child: bar,
      );
    });
  }
}

class PositionBarPainter extends CustomPainter {
  const PositionBarPainter({
    required this.position,
    required this.duration,
    this.loopStart,
    this.loopEnd,
  });

  static const double _track = 10;
  static const double _knob = 14;

  final double position;
  final double duration;
  final double? loopStart;
  final double? loopEnd;

  /// `x(t) = clamp(t / duración, 0, 1) · ancho`.
  static double xOf(double t, double duration, double width) =>
      duration <= 0 ? 0 : (t / duration).clamp(0.0, 1.0) * width;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double cy = h / 2;
    double x(double t) => xOf(t, duration, w);
    RRect capsule(double width) => RRect.fromRectAndRadius(
          Rect.fromLTWH(0, cy - _track / 2, width, _track),
          const Radius.circular(TfRadius.pill),
        );

    canvas.drawRRect(capsule(w), Paint()..color = TfColors.line);
    canvas.drawRRect(capsule(x(position)), Paint()..color = TfColors.timelineBlue);

    final double? ls = loopStart;
    final double? le = loopEnd;
    if (ls != null && le != null) {
      final double lw = (x(le) - x(ls)).clamp(2.0, double.infinity);
      final RRect r = RRect.fromRectAndRadius(
        Rect.fromLTWH(x(ls), 0, lw, h),
        const Radius.circular(TfRadius.small),
      );
      canvas.drawRRect(r, Paint()..color = TfColors.accent.withValues(alpha: TfOpacity.tint18));
      canvas.drawRRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = TfStroke.hairline
          ..color = TfColors.accent,
      );
    }

    final Offset c = Offset(x(position), cy);
    canvas.drawCircle(c + TfShadow.playhead.offset, _knob / 2, TfShadow.playhead.toPaint());
    canvas.drawCircle(c, _knob / 2, Paint()..color = TfColors.text);
  }

  @override
  bool shouldRepaint(PositionBarPainter old) =>
      old.position != position ||
      old.duration != duration ||
      old.loopStart != loopStart ||
      old.loopEnd != loopEnd;
}
