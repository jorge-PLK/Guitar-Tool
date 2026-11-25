import 'package:flutter/widgets.dart';
import 'package:toneforge/contract/record_state.dart';
import 'package:toneforge/features/record/record_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_tooltip.dart';

TextStyle _pillStyle([TfWeight w = TfWeight.regular]) =>
    TfText.body(TfSize.font14, w).copyWith(color: TfColors.white);

double _textWidth(BuildContext context, String text, TextStyle style) {
  final TextPainter p = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final double w = p.width;
  p.dispose();
  return w;
}

/// Capa de píldoras y cuenta atrás de la vista de cámara (RV:369-384). `Padding(16)`: arriba la fila de
/// píldoras y, abajo y centrado, el número de la cuenta atrás.
class PreviewOverlay extends StatelessWidget {
  const PreviewOverlay({super.key, required this.state, required this.onRotate});

  final RecordState state;
  final VoidCallback onRotate;

  @override
  Widget build(BuildContext context) {
    final int? beat = state.countBeat;
    return Padding(
      padding: const EdgeInsets.all(TfSpace.s16),
      child: Column(
        children: <Widget>[
          SizedBox(width: double.infinity, child: PreviewPillRow(state: state, onRotate: onRotate)),
          const Spacer(),
          if (beat != null) CountdownNumber(beat),
        ],
      ),
    );
  }
}

/// `ViewThatFits(in: .horizontal)` de RV:372-378: una fila si cabe; si no, REC y debajo, a la derecha, la cámara.
class PreviewPillRow extends StatelessWidget {
  const PreviewPillRow({super.key, required this.state, required this.onRotate});

  final RecordState state;
  final VoidCallback onRotate;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final RecordSnapshot? snap = state.snapshot;
    if (snap == null) return const SizedBox.shrink();
    final bool recording = state.phase != RecordPhase.idle && state.phase != RecordPhase.adjusting;
    final String part = state.activePart?.name ?? '';
    final String recLabel =
        '${recording ? l.record_recPrefix : ''}${l.record_takePill(snap.nextTakeNumber, part)}';
    final String? format = snap.camera.label;
    final int degrees = state.cameraRotation;
    final String rotateLabel = degrees == 0 ? l.record_rotate : l.record_rotateDegrees(degrees);

    final Widget rec = RecPill(recording: recording, label: recLabel);
    final List<Widget> cam = <Widget>[
      if (format != null) FormatPill(format),
      if (format != null)
        RotatePill(
          label: rotateLabel,
          degrees: degrees,
          enabled: state.phase == RecordPhase.idle,
          onTap: onRotate,
        ),
    ];
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
      final double recW = 2 * TfSpace.s12 + TfSize.recDot + TfSpace.s8 + _textWidth(context, recLabel, _pillStyle(TfWeight.semibold));
      double camW = 0;
      if (format != null) {
        camW = (2 * TfSpace.s12 + _textWidth(context, format, _pillStyle())) +
            TfSpace.s8 +
            (2 * TfSpace.s12 + TfSize.iconButtonIcon + TfSpace.s6 + _textWidth(context, rotateLabel, _pillStyle()));
      }
      final bool oneRow = recW + (cam.isEmpty ? 0 : TfSpace.s8 + camW) <= c.maxWidth;
      if (oneRow) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            rec,
            const Spacer(),
            Row(mainAxisSize: MainAxisSize.min, spacing: TfSpace.s8, children: cam),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: TfSpace.s8,
        children: <Widget>[
          rec,
          Align(
            alignment: Alignment.centerRight,
            child: Row(mainAxisSize: MainAxisSize.min, spacing: TfSpace.s8, children: cam),
          ),
        ],
      );
    });
  }
}

/// Cápsula base de las píldoras (RV:453-457): `bg` @0,75, padding 12/6, una línea con «…».
class _Pill extends StatelessWidget {
  const _Pill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: TfColors.bg.withValues(alpha: TfOpacity.scrim75),
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: TfSpace.s12, vertical: TfSpace.s6),
        child: DefaultTextStyle(
          style: _pillStyle(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          child: child,
        ),
      ),
    );
  }
}

/// Píldora REC (RV:429-436): punto rojo `recordLive` si `recording`, si no `muted`.
class RecPill extends StatelessWidget {
  const RecPill({super.key, required this.recording, required this.label});

  final bool recording;
  final String label;

  @override
  Widget build(BuildContext context) {
    return _Pill(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: TfSpace.s8,
        children: <Widget>[
          DecoratedBox(
            key: const ValueKey<String>('rec-dot'),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: recording ? TfColors.recordLive : TfColors.muted,
            ),
            child: const SizedBox.square(dimension: TfSize.recDot),
          ),
          Flexible(child: Text(label, style: _pillStyle(TfWeight.semibold))),
        ],
      ),
    );
  }
}

/// Píldora de formato `<resolución> · <fps>` (RV:422-427), texto `text2`.
class FormatPill extends StatelessWidget {
  const FormatPill(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) =>
      _Pill(child: Text(label, style: _pillStyle().copyWith(color: TfColors.text2)));
}

/// Píldora «Rotar» (RV:438-451): `text2` con 0°, `accent` con giro. Atenuada al deshabilitarse.
class RotatePill extends StatelessWidget {
  const RotatePill({
    super.key,
    required this.label,
    required this.degrees,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final int degrees;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final Color fg = degrees == 0 ? TfColors.text2 : TfColors.accent;
    return TfTooltip(
      message: l.record_rotateHelp,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: l.record_rotateA11y(degrees),
        excludeSemantics: true,
        onTap: enabled ? onTap : null,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? onTap : null,
            // `.disabled(phase != .idle)` (RV:448): el botón plano de macOS atenúa su etiqueta.
            child: Opacity(
              opacity: enabled ? 1 : TfOpacity.dim,
              child: _Pill(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: TfSpace.s6,
                  children: <Widget>[
                    TfIconView(TfIcon.rotateRight, size: TfSize.iconButtonIcon, color: fg),
                    Text(label, style: _pillStyle().copyWith(color: fg)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Número de la cuenta atrás (RV:380-382): display 64 blanco con sombra.
class CountdownNumber extends StatelessWidget {
  const CountdownNumber(this.beat, {super.key});

  final int beat;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$beat',
      style: TfText.display(TfSpace.s64).copyWith(
        color: TfColors.white,
        shadows: <Shadow>[
          Shadow(
            color: TfShadow.countdown.color,
            blurRadius: TfShadow.countdown.blurRadius,
            offset: TfShadow.countdown.offset,
          ),
        ],
      ),
    );
  }
}
