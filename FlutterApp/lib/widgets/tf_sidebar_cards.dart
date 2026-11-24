import 'package:flutter/widgets.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_marquee.dart';

/// Tema seleccionado de la barra lateral (RootView.swift:76-90). Padding 12 y 8 de margen superior,
/// título/artista separados 2, radio 10; activa: fondo `accentBg` y borde `accent`.
class TfSelectedTrackCard extends StatelessWidget {
  const TfSelectedTrackCard({
    super.key,
    required this.title,
    required this.artist,
    required this.active,
    required this.onTap,
    this.semanticLabel,
  });

  final String title;
  final String artist;
  final bool active;
  final VoidCallback onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: TfSpace.s8),
      child: Semantics(
        button: true,
        label: semanticLabel ?? title,
        excludeSemantics: true,
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(TfRadius.control),
                border: Border.all(
                  color: active ? TfColors.accent : TfColors.accent.withValues(alpha: 0),
                  width: TfStroke.hairline,
                ),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: active ? TfColors.accentBg : TfColors.field,
                  borderRadius: BorderRadius.circular(TfRadius.control),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(TfSpace.s12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: TfSpace.s2,
                    children: <Widget>[
                      TfMarquee(
                        text: title,
                        style: TfText.body(14, TfWeight.semibold).copyWith(color: TfColors.text),
                      ),
                      TfMarquee(
                        text: artist,
                        style: TfText.body(12).copyWith(color: TfColors.muted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tarjeta de dispositivo de audio (RootView.swift:92-103): punto 8 (`deviceOk` o `muted` si no está
/// conectado) + título semibold 14, y subtítulo 12 `muted`.
class TfDeviceCard extends StatelessWidget {
  const TfDeviceCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.connected,
  });

  final String title;
  final String subtitle;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: TfSpace.s8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: TfColors.field,
          borderRadius: BorderRadius.circular(TfRadius.control),
        ),
        child: Padding(
          padding: const EdgeInsets.all(TfSpace.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: TfSpace.s6,
            children: <Widget>[
              Row(
                spacing: TfSpace.s8,
                children: <Widget>[
                  Container(
                    width: TfSize.statusDot,
                    height: TfSize.statusDot,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: connected ? TfColors.deviceOk : TfColors.muted,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TfText.body(14, TfWeight.semibold).copyWith(color: TfColors.text),
                    ),
                  ),
                ],
              ),
              Text(subtitle, style: TfText.body(12).copyWith(color: TfColors.muted)),
            ],
          ),
        ),
      ),
    );
  }
}
