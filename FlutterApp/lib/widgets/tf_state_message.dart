import 'package:flutter/widgets.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';

/// Estado vacío o aviso (VideoSettingsView.swift:310-316): icono 18 `muted` y texto body 12 `text2`
/// centrado, separación 6, padding 8.
class TfStateMessage extends StatelessWidget {
  const TfStateMessage({super.key, required this.icon, required this.text});

  final TfIcon icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(TfSpace.s8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: TfSpace.s6,
        children: <Widget>[
          TfIconView(icon, size: TfSize.navIcon, color: TfColors.muted),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TfText.body(12).copyWith(color: TfColors.text2),
          ),
        ],
      ),
    );
  }
}
