import 'package:flutter/widgets.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_slider.dart';
import 'package:toneforge/widgets/tf_video_surface.dart';

/// Columna «Vista previa» de Montaje (MV:323-376). Sin estado propio: todo llega por parámetro.
/// El throttling del seek (120 ms) es del store; aquí [onSeek] se llama en cada movimiento del
/// deslizador y [onSeekEnd] al soltar. Sin [ready] (`preparing`): vídeo vacío, play y slider deshabilitados.
class MontagePreviewColumn extends StatelessWidget {
  const MontagePreviewColumn({
    super.key,
    required this.textureId,
    required this.frameSize,
    required this.portrait,
    required this.canvasLabel,
    required this.sectionLabel,
    required this.position,
    required this.duration,
    required this.playing,
    required this.ready,
    required this.onTogglePlay,
    required this.onSeek,
    this.onSeekEnd,
    this.title = 'Vista previa', // TODO(l10n): montagePreviewTitle
  });

  final int? textureId;
  final Size? frameSize;
  final bool portrait;
  final String canvasLabel;
  final String? sectionLabel;
  final Duration position;
  final Duration duration;
  final bool playing;
  final bool ready;
  final VoidCallback onTogglePlay;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<Duration>? onSeekEnd;

  /// Título de la cabecera («Vista previa»); pendiente de clave ARB.
  final String title;

  static String _mmss(Duration d) {
    final int t = d.inSeconds < 0 ? 0 : d.inSeconds;
    return '${(t ~/ 60).toString().padLeft(2, '0')}:${(t % 60).toString().padLeft(2, '0')}';
  }

  Duration _ms(double v) => Duration(milliseconds: v.round());

  @override
  Widget build(BuildContext context) {
    final TextStyle head = TfText.body(TfSize.font13, TfWeight.semibold).copyWith(color: TfColors.text);
    final TextStyle sub = TfText.body(TfSize.font13).copyWith(color: TfColors.muted);
    final TextStyle clock = TfText.body(TfSize.font13, TfWeight.regular, true).copyWith(color: TfColors.muted);
    final double maxMs = duration.inMilliseconds.toDouble();
    final double posMs = position.inMilliseconds.toDouble().clamp(0, maxMs).toDouble();
    final String right = sectionLabel == null
        ? _mmss(position)
        : '${_mmss(position)} · $sectionLabel';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: TfSpace.s20, vertical: TfSpace.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TfSpace.s12,
        children: <Widget>[
          Row(
            spacing: TfSpace.s8,
            children: <Widget>[
              Flexible(child: Text('$title · $canvasLabel', style: head, maxLines: 1, overflow: TextOverflow.ellipsis)),
              const Spacer(),
              Flexible(child: Text(right, style: sub, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: portrait ? 9 / 16 : 16 / 9,
                child: DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(TfRadius.card),
                    border: Border.all(color: TfColors.fieldLine, width: TfStroke.hairline),
                  ),
                  child: ColoredBox(
                    color: TfColors.videoBg,
                    child: TfVideoSurface(
                      textureId: ready ? textureId : null,
                      frameSize: frameSize,
                      radius: TfRadius.card,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Row(
            spacing: TfSpace.s12,
            children: <Widget>[
              _PlayButton(playing: playing, enabled: ready, onTap: onTogglePlay),
              Expanded(
                child: TfSlider(
                  value: posMs,
                  min: 0,
                  max: maxMs <= 0 ? 1 : maxMs,
                  onChanged: ready ? (double v) => onSeek(_ms(v)) : null,
                  onChangeEnd: ready && onSeekEnd != null ? (double v) => onSeekEnd!(_ms(v)) : null,
                ),
              ),
              Text('${_mmss(position)} / ${_mmss(duration)}', style: clock),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, required this.enabled, required this.onTap});

  final bool playing;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Widget button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Container(
        key: const ValueKey<String>('montage-play'),
        width: TfSize.controlLg,
        height: TfSize.controlLg,
        decoration: const BoxDecoration(color: TfColors.accent, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: TfIconView(
          playing ? TfIcon.pauseFill : TfIcon.playFill,
          size: TfSize.coverIcon,
          color: TfColors.accentInk,
        ),
      ),
    );
    if (!enabled) button = Opacity(opacity: TfOpacity.disabled, child: button);
    return button;
  }
}
