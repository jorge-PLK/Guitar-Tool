import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/record_state.dart';
import 'package:toneforge/core/frame_channel.dart';
import 'package:toneforge/core/frame_providers.dart';
import 'package:toneforge/features/record/record_store.dart';
import 'package:toneforge/features/record/widgets/record_preview_overlay.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_progress.dart';
import 'package:toneforge/widgets/tf_video_surface.dart';

/// Vista de cámara de Grabar (RV:360-458). Caja 16:9 que ocupa el espacio libre, radio 16, borde `line`.
///
/// El canal de fotogramas `camera` lo crea (`FrameChannel.create`, idempotente) y lo suelta (`dispose`) este
/// widget con estado: la textura solo existe mientras la vista previa está en pantalla. Lee todo de
/// `recordStoreProvider`; «Rotar» llama a `rotateCamera()`.
class RecordPreview extends ConsumerStatefulWidget {
  const RecordPreview({super.key});

  @override
  ConsumerState<RecordPreview> createState() => _RecordPreviewState();
}

class _RecordPreviewState extends ConsumerState<RecordPreview> {
  FrameChannel? _channel;

  @override
  void dispose() {
    _channel?.dispose();
    super.dispose();
  }

  Widget _content(BuildContext context, RecordState s) {
    final AppLocalizations l = AppLocalizations.of(context);
    final RecordCamera? cam = s.snapshot?.camera;
    if (cam == null) return const Center(child: TfSpinner.small());
    switch (cam.state) {
      case CameraState.live:
        _channel ??= ref.read(frameChannelProvider(FrameChannelId.camera));
        return TfVideoSurface(
          textureId: _channel?.create(),
          frameSize: s.cameraFrameSize,
          rotation: s.cameraRotation,
          placeholder: PreviewPlaceholder(text: l.record_previewSimulated(cam.name ?? l.record_previewSimulatedName)),
        );
      case CameraState.simulated:
        return PreviewPlaceholder(text: l.record_previewSimulated(cam.name ?? l.record_previewSimulatedName));
      case CameraState.none || CameraState.denied || CameraState.failed:
        return PreviewPlaceholder(text: l.record_previewNoVideo);
      case CameraState.idle || CameraState.unknown:
        // RV:397: `.idle` = ProgressView pequeño.
        return const Center(child: TfSpinner.small());
    }
  }

  @override
  Widget build(BuildContext context) {
    final RecordState s = ref.watch(recordStoreProvider);
    final BorderRadius radius = BorderRadius.circular(TfRadius.hero);
    // Arriba y a lo ancho; la altura es la del 16:9 (o la libre si es menor) y el sobrante queda abajo (RV:386-390).
    return Align(
      alignment: Alignment.topCenter,
      heightFactor: 1,
      child: AspectRatio(
        aspectRatio: TfSize.previewAspect,
        child: ClipRRect(
          borderRadius: radius,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: TfColors.line, width: TfStroke.hairline),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                const PreviewBackdrop(),
                _content(context, s),
                PreviewOverlay(
                  state: s,
                  onRotate: () => ref.read(recordStoreProvider.notifier).rotateCamera(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Degradado radial de fondo (RV:365-367): centro (0,5; 0,4), radio absoluto 520 pt, `fieldLine` a `previewDeep`.
class PreviewBackdrop extends StatelessWidget {
  const PreviewBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
      final double shortest = math.min(c.maxWidth, c.maxHeight);
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.2),
            radius: shortest.isFinite && shortest > 0 ? TfSize.previewGradientRadius / shortest : 1,
            colors: const <Color>[TfColors.fieldLine, TfColors.previewDeep],
          ),
        ),
      );
    });
  }
}

/// Marcador de posición (RV:406-420): icono 28 + texto, solo texto o nada según la altura libre bajo las
/// píldoras (padding 64 arriba, 8 abajo, 16 a los lados).
class PreviewPlaceholder extends StatelessWidget {
  const PreviewPlaceholder({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final TextStyle style = TfText.body().copyWith(color: TfColors.muted);
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
      const EdgeInsets pad = EdgeInsets.fromLTRB(TfSpace.s16, TfSpace.s64, TfSpace.s16, TfSpace.s8);
      final double availW = math.max(0, c.maxWidth - pad.horizontal);
      final double availH = c.maxHeight - pad.vertical;
      final TextPainter p = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: availW);
      final double textH = p.height;
      p.dispose();
      final bool showText = textH <= availH;
      final bool showIcon = TfSize.previewPlaceholderIcon + TfSpace.s8 + textH <= availH;
      return Padding(
        padding: pad,
        child: Center(
          child: !showText
              ? const SizedBox.shrink()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: TfSpace.s8,
                  children: <Widget>[
                    if (showIcon) const TfIconView(TfIcon.video, size: TfSize.previewPlaceholderIcon, color: TfColors.muted),
                    Text(text, style: style, textAlign: TextAlign.center),
                  ],
                ),
        ),
      );
    });
  }
}
