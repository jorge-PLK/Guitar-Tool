import 'package:flutter/widgets.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';

enum TfNoticeTone { accent, danger }

/// Aviso descartable (TabScreen.swift:169-181): caja `field` radio 10 con borde `fieldLine`, padding
/// h16 v12, separación 12, líneas body 13 `text2` separadas 4 y botón `xmark` a la derecha.
/// El icono de aviso (accent/danger) viene de la ficha; SwiftUI no lo dibuja (desvío a confirmar).
class TfNotice extends StatelessWidget {
  const TfNotice({
    super.key,
    required this.messages,
    required this.onDismiss,
    this.tone = TfNoticeTone.accent,
    this.dismissLabel,
  });

  final List<String> messages;
  final VoidCallback onDismiss;
  final TfNoticeTone tone;

  /// Etiqueta accesible del botón de cerrar.
  final String? dismissLabel;

  @override
  Widget build(BuildContext context) {
    final Color toneColor = tone == TfNoticeTone.accent ? TfColors.accent : TfColors.danger;
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(TfRadius.control),
        border: Border.all(color: TfColors.fieldLine, width: TfStroke.hairline),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: TfColors.field,
          borderRadius: BorderRadius.circular(TfRadius.control),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: TfSpace.s16, vertical: TfSpace.s12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: TfSpace.s12,
            children: <Widget>[
              TfIconView(TfIcon.exclamationmarkTriangle, size: TfSize.noticeIcon, color: toneColor),              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: TfSpace.s4,
                  children: <Widget>[
                    for (final String m in messages)
                      Text(m, style: TfText.body(13).copyWith(color: TfColors.text2)),
                  ],
                ),
              ),
              Semantics(
                button: true,
                label: dismissLabel,
                excludeSemantics: true,
                onTap: onDismiss,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onDismiss,
                    child: const TfIconView(TfIcon.xmark, size: TfSize.noticeClose, color: TfColors.text),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
