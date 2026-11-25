import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:toneforge/contract/link_resolve.dart';
import 'package:toneforge/features/library/library_metrics.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/fmt.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_chip.dart';

/// Diferencia con signo y un decimal («+1,2 s» en es, «+1.2 s» en en): `LinkImportSheet.signed` (LS:730).
String signedSeconds(double seconds, String locale) =>
    '${NumberFormat('+0.0;-0.0', locale).format(seconds)} s';

/// «canal · m:ss» de un candidato (los que falten se omiten).
String candidateSubtitle(LinkCandidateInfo c) => [
  if (c.artist != null && c.artist!.isNotEmpty) c.artist!,
  if (c.duration != null) TfFmt.duration(c.duration!),
].join(' · ');

/// Enlace ↗ «Abrir en el navegador» (LS:725).
class OpenLinkButton extends StatelessWidget {
  const OpenLinkButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: AppLocalizations.of(context).library_importOpenBrowser,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: const TfIconView(TfIcon.arrowUpRightSquare, size: TfSize.font14, color: TfColors.accent),
      ),
    ),
  );
}

/// Fila de un candidato de YouTube (LS:694-723). Si [candidate] ya está en la biblioteca: opacidad 0,7,
/// chip + «Abrir» y no seleccionable.
class CandidateRow extends StatelessWidget {
  const CandidateRow({
    super.key,
    required this.candidate,
    required this.selected,
    required this.onSelect,
    required this.onOpenLink,
    required this.onOpenProject,
  });

  final LinkCandidateInfo candidate;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onOpenLink;
  final void Function(String projectId) onOpenProject;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final lib = candidate.inLibrary;
    final on = selected && lib == null;
    final diff = candidate.difference;
    final row = Container(
      padding: const EdgeInsets.symmetric(horizontal: TfSpace.s12, vertical: TfSpace.s10),
      decoration: BoxDecoration(
        color: on ? TfColors.accentBg : TfColors.field,
        borderRadius: BorderRadius.circular(TfRadius.control),
        border: Border.all(color: on ? TfColors.accent : TfColors.fieldLine, width: TfStroke.hairline),
      ),
      child: Row(
        spacing: TfSpace.s12,
        children: [
          Opacity(
            opacity: lib == null ? 1 : TfOpacity.dim,
            child: TfIconView(
              on ? TfIcon.largecircleFillCircle : TfIcon.circle,
              size: TfSize.font14,
              color: on ? TfColors.accent : TfColors.muted,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: TfSpace.s2,
              children: [
                Text(
                  candidate.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TfText.body(14, TfWeight.semibold).copyWith(color: TfColors.text),
                ),
                Text(
                  candidateSubtitle(candidate),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TfText.body(12).copyWith(color: TfColors.muted),
                ),
              ],
            ),
          ),
          if (diff != null)
            Text(
              signedSeconds(diff, locale),
              style: TfText.body(12, TfWeight.medium).copyWith(color: TfColors.text2),
            ),
          if (candidate.isClose) TfChip(l.library_importChipClose, kind: TfChipKind.ok),
          if (candidate.isLive) TfChip(l.library_importChipLive, kind: TfChipKind.neutral),
          if (lib != null) ...[
            TfChip(l.library_importChipInLibrary, kind: TfChipKind.neutral),
            TfSecondaryButton(
              label: l.library_importOpen,
              height: LibraryMetrics.importOpenHeight,
              onPressed: () => onOpenProject(lib.id),
            ),
          ] else
            OpenLinkButton(onTap: onOpenLink),
        ],
      ),
    );
    return Opacity(
      opacity: lib == null ? 1 : TfOpacity.pressedSecondary,
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: lib == null ? onSelect : null, child: row),
    );
  }
}
