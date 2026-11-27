import 'package:flutter/widgets.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/fmt.dart';
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
    this.rangeStart = Duration.zero,
  });

  /// Mínimo del deslizador (SwiftUI `span.start...span.end`).
  final Duration rangeStart;

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

  static String _t(Duration d) => TfFmt.duration(d.inMilliseconds / 1000);

  Duration _ms(double v) => Duration(milliseconds: v.round());

  @override
  Widget build(BuildContext context) {
    final TextStyle sub = TfText.body(TfSize.font13).copyWith(color: TfColors.muted);
    final TextStyle clock = TfText.body(TfSize.font13, TfWeight.regular, true).copyWith(color: TfColors.text);
    final TextStyle clockMuted = clock.copyWith(color: TfColors.muted);
    final double maxMs = duration.inMilliseconds.toDouble();
    final double minMs = rangeStart.inMilliseconds.toDouble();
    final double sliderMax = maxMs <= minMs ? minMs + 1 : maxMs;
    final double posMs = position.inMilliseconds.toDouble().clamp(minMs, sliderMax).toDouble();
    final String title = AppLocalizations.of(context).montagePreviewTitle(canvasLabel);
    final String right = sectionLabel == null ? _t(position) : '${_t(position)} · $sectionLabel';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: TfSpace.s20, vertical: TfSpace.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TfSpace.s12,
        children: <Widget>[
          _Header(title: title, time: right, style: sub),
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
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(TfRadius.card - TfStroke.hairline),
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
          ),
          Row(
            spacing: TfSpace.s12,
            children: <Widget>[
              _PlayButton(playing: playing, enabled: ready, onTap: onTogglePlay),
              Expanded(
                child: TfSlider(
                  value: posMs,
                  min: minMs,
                  max: sliderMax,
                  onChanged: ready ? (double v) => onSeek(_ms(v)) : null,
                  onChangeEnd: ready && onSeekEnd != null ? (double v) => onSeekEnd!(_ms(v)) : null,
                ),
              ),
              Text.rich(
                TextSpan(children: <InlineSpan>[
                  TextSpan(text: _t(position), style: clock),
                  TextSpan(text: ' / ${_t(duration)}', style: clockMuted),
                ]),
                maxLines: 1,
                softWrap: false,
              ),
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

/// Una línea si cabe; si no, dos líneas (título arriba, tiempo debajo), como `ViewThatFits` de MV:330.
class _Header extends StatelessWidget {
  const _Header({required this.title, required this.time, required this.style});

  final String title;
  final String time;
  final TextStyle style;

  double _w(BuildContext context, String t) {
    final TextPainter p = TextPainter(
      text: TextSpan(text: t, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final double w = p.width;
    p.dispose();
    return w;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
      final bool oneLine = _w(context, title) + TfSpace.s12 + _w(context, time) <= c.maxWidth;
      if (oneLine) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(title, style: style, maxLines: 1, softWrap: false),
            Text(time, style: style, maxLines: 1, softWrap: false),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: TfSpace.s2,
        children: <Widget>[
          Text(title, style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(time, style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      );
    });
  }
}
