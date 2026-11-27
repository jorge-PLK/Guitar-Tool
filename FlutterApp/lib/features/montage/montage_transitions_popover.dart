import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/icons.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/tf_popover.dart';
import '../../widgets/tf_tooltip.dart';

/// Botón (i) con el popover «Transiciones» (MV:420-444): datos fijos de solo lectura.
class MontageTransitionsButton extends StatefulWidget {
  const MontageTransitionsButton({super.key, required this.anticipation});

  /// `anticipationLabel` del snapshot («2 s»).
  final String anticipation;

  @override
  State<MontageTransitionsButton> createState() => _MontageTransitionsButtonState();
}

class _MontageTransitionsButtonState extends State<MontageTransitionsButton> {
  final TfPopoverController _controller = TfPopoverController();

  @override
  Widget build(BuildContext context) {
    final String title = AppLocalizations.of(context).montageTransitions;
    return TfPopover(
      controller: _controller,
      popoverBuilder: (BuildContext _) => MontageTransitionsContent(anticipation: widget.anticipation),
      child: TfTooltip(
        message: title,
        child: Semantics(
          button: true,
          label: title,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              key: const ValueKey<String>('montage-transitions-info'),
              behavior: HitTestBehavior.opaque,
              onTap: _controller.toggle,
              child: const TfIconView(TfIcon.infoCircle, size: TfSize.iconButtonIcon, color: TfColors.text2),
            ),
          ),
        ),
      ),
    );
  }
}

/// Contenido del popover: ancho 340, padding 14, título display(16), filas clave/valor.
class MontageTransitionsContent extends StatelessWidget {
  const MontageTransitionsContent({super.key, required this.anticipation});

  final String anticipation;

  // TODO(l10n): sin claves ARB para estas filas informativas (mini-spec Fase 7, «Transiciones»).
  static const List<(String, String)> _fixed = <(String, String)>[
    ('Recolocación', 'Muelle · 0,5 s'),
    ('Entrada', 'Escala 92→100 % + nitidez'),
  ];
  static const List<(String, String)> _fixedTail = <(String, String)>[
    ('Fundido de audio', '80 ms'),
    ('Fundido de entrada y salida', '1 compás'),
    ('Esquinas', 'Redondeadas + sombra'),
  ];

  Widget _row(String k, String v) {
    final TextStyle base = TfText.body(13).copyWith(decoration: TextDecoration.none);
    return Padding(
      padding: const EdgeInsets.only(top: TfSpace.s6),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(k, style: base.copyWith(color: TfColors.text2))),
          const SizedBox(width: TfSpace.s16),
          Text(v, style: TfText.body(13, TfWeight.semibold).copyWith(color: TfColors.text, decoration: TextDecoration.none)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    // TODO(l10n): «Anticipación al solo» sin clave ARB.
    final List<(String, String)> rows = <(String, String)>[
      ..._fixed,
      ('Anticipación al solo', anticipation),
      ..._fixedTail,
    ];
    return SizedBox(
      width: 340,
      child: Padding(
        padding: const EdgeInsets.all(TfSpace.s14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              l.montageTransitions,
              style: TfText.display(16).copyWith(color: TfColors.text, decoration: TextDecoration.none),
            ),
            for (final (String k, String v) in rows) _row(k, v),
          ],
        ),
      ),
    );
  }
}
