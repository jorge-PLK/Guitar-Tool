import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

enum TfMixerChannelVariant { normal, master }

/// Canal del mezclador (`MixerChannel`/`MasterChannel`, BackingMixer.swift:143-255): contenedor con ranuras.
/// 96 de ancho, alto variable (276 normal, mín. 166). El kit no lleva textos: todo entra por ranuras.
///
/// Orden: [title] (alto 22) · [faderBuilder] + [levelBuilder] (reciben el alto del fader) ·
/// [value] (pie del fader, p. ej. «−6,0 dB») · [toggles] (fila M/S; sin ella se reserva el hueco, como el master).
class TfMixerChannel extends StatelessWidget {
  const TfMixerChannel({
    super.key,
    required this.title,
    required this.faderBuilder,
    this.levelBuilder,
    this.value,
    this.toggles,
    this.variant = TfMixerChannelVariant.normal,
    this.dimmed = false,
    this.height = TfSize.mixerChannelHeight,
  });

  final Widget title;
  final Widget Function(double faderHeight) faderBuilder;
  final Widget Function(double faderHeight)? levelBuilder;
  final Widget? value;
  final Widget? toggles;
  final TfMixerChannelVariant variant;

  /// Mute o solo ajeno: todo el canal a `TfOpacity.muted`.
  final bool dimmed;
  final double height;

  /// Alto del fader para un alto de canal: `max(150 − (276 − alto), 40)`.
  static double faderHeightFor(double channelHeight) {
    final double h = TfSize.faderBaseHeight - (TfSize.mixerChannelHeight - channelHeight);
    return h < TfSize.faderMinHeight ? TfSize.faderMinHeight : h;
  }

  @override
  Widget build(BuildContext context) {
    final bool master = variant == TfMixerChannelVariant.master;
    final double h = height < TfSize.mixerChannelMinHeight ? TfSize.mixerChannelMinHeight : height;
    final double fh = faderHeightFor(h);
    const Radius r = Radius.circular(TfRadius.tile);
    final Widget channel = DecoratedBox(
      decoration: BoxDecoration(
        color: master ? TfColors.accentBg.withValues(alpha: TfOpacity.half) : TfColors.field,
        borderRadius: const BorderRadius.all(r),
        border: Border.all(
          color: master ? TfColors.accent.withValues(alpha: TfOpacity.borderAccent) : TfColors.fieldLine,
          width: TfStroke.hairline,
        ),
      ),
      child: SizedBox(
        width: TfSize.mixerChannelWidth,
        height: h,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: TfSpace.s12),
          child: Column(
            spacing: TfSpace.s6,
            children: <Widget>[
              SizedBox(
                height: TfSize.mixerTitleHeight,
                child: Center(child: title),
              ),
              Padding(
                padding: const EdgeInsets.only(top: TfSpace.s4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: TfSpace.s10,
                  children: <Widget>[
                    faderBuilder(fh),
                    if (levelBuilder != null) levelBuilder!(fh),
                  ],
                ),
              ),
              ?value,
              Padding(
                padding: const EdgeInsets.only(top: TfSpace.s4),
                child: SizedBox(
                  height: TfSize.controlMd,
                  child: Center(child: toggles),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return dimmed ? Opacity(opacity: TfOpacity.muted, child: channel) : channel;
  }
}
