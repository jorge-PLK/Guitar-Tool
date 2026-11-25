import 'package:flutter/widgets.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';

/// Cabecera de Grabar (RecordView.swift:145-164): `artista · título · Multitoma`, «Grabar» y «Ir al montaje».
class RecordHeader extends StatelessWidget {
  const RecordHeader({super.key, required this.title, this.artist, required this.busy, required this.onGoMontage});

  final String title;
  final String? artist;

  /// `phase != idle`: deshabilita «Ir al montaje».
  final bool busy;
  final VoidCallback onGoMontage;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String line = <String>[
      if (artist != null && artist!.isNotEmpty) artist!,
      if (title.isNotEmpty) title,
      l.record_headerMulti,
    ].join(' · ');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: TfText.body(13).copyWith(color: TfColors.muted)),
              const SizedBox(height: TfSpace.s2),
              Text(l.record_title, style: TfText.display(26).copyWith(color: TfColors.text)),
            ],
          ),
        ),
        _GoMontage(label: l.record_goMontage, help: l.record_goMontageHelp, onTap: busy ? null : onGoMontage),
      ],
    );
  }
}

// TODO(ola3): falta variante del kit TfSecondaryButton con texto semibold `text2` (RV:154-160).
class _GoMontage extends StatelessWidget {
  const _GoMontage({required this.label, required this.help, required this.onTap});

  final String label;
  final String help;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(TfRadius.control);
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      tooltip: help,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Opacity(
            opacity: onTap == null ? TfOpacity.disabled : 1,
            child: Container(
              height: TfSize.controlLg,
              padding: const EdgeInsets.symmetric(horizontal: TfSpace.s18),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: TfColors.field, borderRadius: radius),
              foregroundDecoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: TfColors.fieldLine, width: TfStroke.hairline),
              ),
              child: Text(label, style: TfText.body(14, TfWeight.semibold).copyWith(color: TfColors.text2)),
            ),
          ),
        ),
      ),
    );
  }
}
