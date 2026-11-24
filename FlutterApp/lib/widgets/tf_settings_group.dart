import 'package:flutter/widgets.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';

import 'tf_card.dart';

/// Grupo de ajustes (SettingsView.swift:50-67): tarjeta (`card`, radio 14, borde `line`) con padding
/// h20 v18, título display 18 medium, nota body 13 `muted`. La separación 14 va entre el encabezado y
/// cada hijo directo de `children`.
class TfSettingsGroup extends StatelessWidget {
  const TfSettingsGroup({
    super.key,
    required this.title,
    required this.note,
    required this.children,
  });

  final String title;
  final String note;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: TfCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: TfSpace.s20,
            vertical: TfSpace.s18,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: TfSpace.s14,
            children: <Widget>[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: TfSpace.s6,
                children: <Widget>[
                  Text(
                    title,
                    style: TfText.display(
                      18,
                      TfWeight.medium,
                    ).copyWith(color: TfColors.text),
                  ),
                  Text(
                    note,
                    style: TfText.body(13).copyWith(color: TfColors.muted),
                  ),
                ],
              ),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// Fila de información (SettingsView.swift:69-81): h12 v10, radio 10, fondo `field`, separación 12;
/// etiqueta Inter 14 regular `text`, hueco elástico y valor a la derecha.
class TfInfoRow extends StatelessWidget {
  const TfInfoRow({super.key, required this.label, required this.trailing});

  final String label;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TfColors.field,
        borderRadius: BorderRadius.circular(TfRadius.control),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TfSpace.s12,
          vertical: TfSpace.s10,
        ),
        child: Row(
          spacing: TfSpace.s12,
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: TfText.body().copyWith(color: TfColors.text),
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}
