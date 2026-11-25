import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/tokens.dart';
import '../../../theme/typography.dart';
import '../../../widgets/tf_card.dart';
import '../mixer_store.dart';
import 'compact_mixer.dart';
import 'expanded_mixer.dart';

/// Tarjeta «Mezclador» de Grabar (RecordMixer.swift:19-61). Plegado por defecto; el estado
/// expandido es local y se avisa con [onExpandedChanged] para que el padre encoja la cámara.
class RecordMixer extends ConsumerStatefulWidget {
  const RecordMixer({super.key, this.onExpandedChanged, this.inputLevel});

  final ValueChanged<bool>? onExpandedChanged;

  /// Nivel de la entrada de guitarra 0…1; `null` = sin fuente (medidor a 0).
  final ValueListenable<double>? inputLevel;

  @override
  ConsumerState<RecordMixer> createState() => _RecordMixerState();
}

class _RecordMixerState extends ConsumerState<RecordMixer> {
  bool _expanded = false;

  void _toggle() {
    setState(() => _expanded = !_expanded);
    widget.onExpandedChanged?.call(_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String output = ref.watch(mixerStoreProvider.select((s) => s.mix?.outputName ?? ''));
    return TfCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: TfSpace.s20, vertical: TfSpace.s14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: TfSpace.s10,
          children: <Widget>[
            Row(
              spacing: TfSpace.s12,
              children: <Widget>[
                Text(l.record_mixerTitle, style: TfText.display(18).copyWith(color: TfColors.text)),
                const Spacer(),
                Flexible(
                  child: Text(
                    l.record_mixerOutput(output.isEmpty ? '—' : output),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TfText.body(TfSize.font12).copyWith(color: TfColors.muted),
                  ),
                ),
                _FoldButton(
                  label: _expanded ? l.record_mixerFold : l.record_mixerExpand,
                  semanticLabel: _expanded ? l.record_mixerFoldA11y : l.record_mixerExpandA11y,
                  onPressed: _toggle,
                ),
              ],
            ),
            if (_expanded) ExpandedMixer(inputLevel: widget.inputLevel) else CompactMixer(inputLevel: widget.inputLevel),
          ],
        ),
      ),
    );
  }
}

class _FoldButton extends StatelessWidget {
  const _FoldButton({required this.label, required this.semanticLabel, required this.onPressed});

  final String label;
  final String semanticLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      onTap: onPressed,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: Container(
            height: TfSize.foldButtonHeight,
            padding: const EdgeInsets.symmetric(horizontal: TfSpace.s12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: TfColors.field,
              borderRadius: BorderRadius.circular(TfRadius.field),
              border: Border.all(color: TfColors.fieldLine, width: TfStroke.hairline),
            ),
            child: Text(
              label,
              style: TfText.body(13, TfWeight.medium).copyWith(color: TfColors.text2),
            ),
          ),
        ),
      ),
    );
  }
}
