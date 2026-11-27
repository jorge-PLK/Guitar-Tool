import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/video.dart';
import 'package:toneforge/core/frame_channel.dart';
import 'package:toneforge/core/frame_providers.dart';
import 'package:toneforge/features/settings/video_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_progress.dart';
import 'package:toneforge/widgets/tf_state_message.dart';
import 'package:toneforge/widgets/tf_video_surface.dart';

/// Vista previa de la cámara de Ajustes (VS:286-321): 16:9, fondo negro, radio 10, borde `fieldLine`.
///
/// Pinta la textura del canal `camera` (la toma y la suelta este widget con `acquire`/`release`; el conteo
/// evita que la baja de una pantalla mate la textura de la siguiente) con el tamaño y la
/// rotación del store. Sin canal (`--mock`) o simulada: barras de color.
class CameraPreviewBox extends ConsumerStatefulWidget {
  const CameraPreviewBox({super.key});

  @override
  ConsumerState<CameraPreviewBox> createState() => _CameraPreviewBoxState();
}

class _CameraPreviewBoxState extends ConsumerState<CameraPreviewBox> {
  FrameChannel? _channel;
  bool _held = false;

  @override
  void dispose() {
    if (_held) _channel?.release();
    super.dispose();
  }

  Widget _content(BuildContext context, VideoStoreState s) {
    final AppLocalizations l = AppLocalizations.of(context);
    final CameraPreviewResult? p = s.preview;
    if (p == null) return const Center(child: TfSpinner.small());
    switch (p.state) {
      case PreviewState.live:
        if (!_held) {
          _channel = ref.read(frameChannelProvider(FrameChannelId.camera));
          _channel?.acquire();
          _held = true;
        }
        return TfVideoSurface(
          textureId: _channel?.textureId,
          frameSize: s.frameSize,
          rotation: p.rotation,
          placeholder: const ColorBars(),
        );
      case PreviewState.simulated:
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            const ColorBars(),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(TfSpace.s6),
                child: _Legend(text: l.settings_video_simulated),
              ),
            ),
          ],
        );
      case PreviewState.noCamera:
        return TfStateMessage(icon: TfIcon.cameraFill, iconFilled: true, text: l.settings_video_none);
      case PreviewState.denied:
        return _Denied(onOpen: () => ref.read(videoStoreProvider.notifier).openCameraPrivacy());
      case PreviewState.failed:
        return TfStateMessage(
          icon: TfIcon.exclamationmarkTriangle,
          text: l.settings_video_openFailed(p.message ?? ''),
        );
      case PreviewState.idle || PreviewState.unknown:
        return const Center(child: TfSpinner.small());
    }
  }

  @override
  Widget build(BuildContext context) {
    final VideoStoreState s = ref.watch(videoStoreProvider);
    final BorderRadius radius = BorderRadius.circular(TfRadius.control);
    return SizedBox(
      width: TfSize.settingsPreviewWidth,
      child: AspectRatio(
        aspectRatio: TfSize.previewAspect,
        child: ClipRRect(
          borderRadius: radius,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: TfColors.fieldLine, width: TfStroke.hairline),
            ),
            child: ColoredBox(color: TfColors.black, child: _content(context, s)),
          ),
        ),
      ),
    );
  }
}

/// Ocho franjas (VS:386-394) con opacidad 0,85. `CustomPainter`.
class ColorBars extends StatelessWidget {
  const ColorBars({super.key});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _BarsPainter(), size: Size.infinite);
}

class _BarsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const List<Color> colors = TfColors.colorBars;
    final double w = size.width / colors.length;
    for (int i = 0; i < colors.length; i++) {
      canvas.drawRect(
        Rect.fromLTWH(i * w, 0, w + 0.5, size.height),
        Paint()..color = colors[i].withValues(alpha: TfOpacity.bars),
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => false;
}

class _Legend extends StatelessWidget {
  const _Legend({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TfColors.black.withValues(alpha: TfOpacity.disabled),
        borderRadius: BorderRadius.circular(TfRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: TfSpace.s8, vertical: TfSpace.s3),
        child: Text(
          text,
          style: TfText.body(TfSize.font11, TfWeight.semibold).copyWith(color: TfColors.white),
        ),
      ),
    );
  }
}

class _Denied extends StatelessWidget {
  const _Denied({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String label = defaultTargetPlatform == TargetPlatform.windows
        ? l.settings_video_openSystem_win
        : l.settings_video_openSystem_mac;
    return Padding(
      padding: const EdgeInsets.all(TfSpace.s8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: TfSpace.s6,
        children: <Widget>[
          const TfIconView(TfIcon.lockFill, size: TfSize.navIcon, color: TfColors.muted, filled: true),
          Text(
            l.settings_video_denied,
            textAlign: TextAlign.center,
            style: TfText.body(TfSize.font12).copyWith(color: TfColors.text2),
          ),
          TfSecondaryButton(label: label, height: TfSize.controlSm, onPressed: onOpen),
        ],
      ),
    );
  }
}
