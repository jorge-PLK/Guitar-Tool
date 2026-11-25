import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/link_resolve.dart';
import 'package:toneforge/features/library/library_metrics.dart';
import 'package:toneforge/features/library/link_import_store.dart';
import 'package:toneforge/features/library/sheets/candidate_row.dart';
import 'package:toneforge/features/library/sheets/import_banner.dart';
import 'package:toneforge/features/library/source_messages.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/selected_project.dart';
import 'package:toneforge/theme/fmt.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_scroll.dart';
import 'package:toneforge/widgets/tf_text_field.dart';

/// Pantalla «candidatos» (cabecera, banda de posible repetido, confirmación o lista, pie): LS:597-728.
/// [onClose] cierra la hoja (Cancelar y «Abrir» un tema existente).
class ImportCandidatesView extends ConsumerStatefulWidget {
  const ImportCandidatesView({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  ConsumerState<ImportCandidatesView> createState() => _ImportCandidatesViewState();
}

class _ImportCandidatesViewState extends ConsumerState<ImportCandidatesView> {
  late final TextEditingController _title = TextEditingController(text: ref.read(linkImportStoreProvider).title);
  late final TextEditingController _artist = TextEditingController(text: ref.read(linkImportStoreProvider).artist);
  final TextEditingController _manual = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _manual.dispose();
    super.dispose();
  }

  void _sync(TextEditingController c, String v) {
    if (c.text != v) c.value = TextEditingValue(text: v, selection: TextSelection.collapsed(offset: v.length));
  }

  void _openProject(String id) {
    ref.read(selectedProjectProvider.notifier).select(id);
    widget.onClose();
  }

  void _addManual() {
    final t = _manual.text.trim();
    if (t.isEmpty) return;
    ref.read(linkImportStoreProvider.notifier).addManual(t);
  }

  Widget _labeled(String label, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: TfSpace.s4,
    children: [
      Text(label, style: TfText.body(TfSize.font12).copyWith(color: TfColors.muted)),
      child,
    ],
  );

  Widget _caption(String t) => Text(
    t,
    style: TfText.body(TfSize.font12, TfWeight.medium).copyWith(color: TfColors.muted, letterSpacing: TfSize.trackingTableHeader),
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(linkImportStoreProvider);
    final store = ref.read(linkImportStoreProvider.notifier);
    final r = s.resolved;
    if (r == null) return const SizedBox.shrink();
    _sync(_title, s.title);
    _sync(_artist, s.artist);
    final possible = s.possibleDuplicate;
    final err = s.error;
    final conf = s.confirmation;
    final children = <Widget>[
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: TfSpace.s16,
        children: [
          _Cover(url: r.thumbnail),
          Expanded(
            child: Column(
              spacing: TfSpace.s10,
              children: [
                _labeled(
                  l.library_fieldTitle,
                  SizedBox(
                    height: LibraryMetrics.linkFieldHeight,
                    child: TfTextField(controller: _title, onChanged: store.setTitle),
                  ),
                ),
                _labeled(
                  l.library_fieldArtist,
                  SizedBox(
                    height: LibraryMetrics.linkFieldHeight,
                    child: TfTextField(controller: _artist, onChanged: store.setArtist),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      if (possible != null) _band(l, possible),
      if (err != null && err.returnsToCandidates) ImportBanner(text: sourceErrorTexts(l, err).detail),
      if (conf != null) _confirmation(l, conf, store) else _list(l, s, r, store),
      for (final n in s.notices) ImportBanner(text: n, tone: ImportBannerTone.warning),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        spacing: TfSpace.s8,
        children: [
          TfSecondaryButton(label: l.library_importCancel, onPressed: widget.onClose),
          TfPrimaryButton(label: l.library_importGo, onPressed: s.canImport ? store.importSelected : null),
        ],
      ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: TfSpace.s14,
      children: children,
    );
  }

  Widget _band(AppLocalizations l, LinkTrackInfo p) {
    final name = [p.title, if (p.artist != null && p.artist!.isNotEmpty) p.artist!].join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: TfSpace.s12, vertical: TfSpace.s8),
      decoration: BoxDecoration(color: TfColors.neutralBg, borderRadius: BorderRadius.circular(TfRadius.field)),
      child: Row(
        spacing: TfSpace.s10,
        children: [
          const TfIconView(TfIcon.infoCircle, size: TfSize.font14, color: TfColors.muted),
          Expanded(
            child: Text(
              l.library_importPossible(name),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TfText.body(TfSize.font13).copyWith(color: TfColors.text2),
            ),
          ),
          TfSecondaryButton(
            label: l.library_importOpen,
            height: LibraryMetrics.importOpenHeight,
            onPressed: () => _openProject(p.id),
          ),
        ],
      ),
    );
  }

  Widget _confirmation(AppLocalizations l, LinkCandidateInfo c, LinkImportStore store) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: TfSpace.s8,
    children: [
      _caption(l.library_importVideoLabel),
      Container(
        padding: const EdgeInsets.all(TfSpace.s12),
        decoration: BoxDecoration(color: TfColors.field, borderRadius: BorderRadius.circular(TfRadius.control)),
        child: Row(
          spacing: TfSpace.s12,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: TfSpace.s2,
                children: [
                  Text(
                    c.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TfText.body(TfSize.font14, TfWeight.semibold).copyWith(color: TfColors.text),
                  ),
                  Text(candidateSubtitle(c), style: TfText.body(TfSize.font13).copyWith(color: TfColors.muted)),
                ],
              ),
            ),
            OpenLinkButton(onTap: () => store.openSpotify(c.url)),
          ],
        ),
      ),
    ],
  );

  Widget _list(AppLocalizations l, LinkImportState s, LinkResolveResult r, LinkImportStore store) {
    final err = s.manualError;
    final dur = r.duration;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: TfSpace.s8,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _caption(l.library_importCandidatesLabel),
            if (dur != null)
              Text(
                l.library_importSpotifyDuration(TfFmt.duration(dur)),
                style: TfText.body(TfSize.font12).copyWith(color: TfColors.muted),
              ),
          ],
        ),
        if (r.noCloseCandidate)
          ImportBanner(
            text: r.candidates.isEmpty ? l.library_importNoResults : l.library_importNoClose(_closeSeconds),
            tone: ImportBannerTone.warning,
          ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: LibraryMetrics.candidateListMaxHeight),
          child: TfScroll(
            builder: (ctx, c) => SingleChildScrollView(
              controller: c,
              child: Column(
                spacing: TfSpace.s6,
                children: [
                  for (final cand in r.candidates)
                    CandidateRow(
                      key: ValueKey(cand.id),
                      candidate: cand,
                      selected: s.selectedId == cand.id,
                      onSelect: () => store.selectCandidate(cand.id),
                      onOpenLink: () => store.openSpotify(cand.url),
                      onOpenProject: _openProject,
                    ),
                ],
              ),
            ),
          ),
        ),
        _labeled(
          l.library_importManualLabel,
          Row(
            spacing: TfSpace.s8,
            children: [
              Expanded(
                child: SizedBox(
                  height: LibraryMetrics.linkFieldHeight,
                  child: TfTextField(
                    controller: _manual,
                    hint: l.library_importManualHint,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _addManual(),
                  ),
                ),
              ),
              ListenableBuilder(
                listenable: _manual,
                builder: (_, _) => TfSecondaryButton(
                  label: l.library_importManualAdd,
                  onPressed: _manual.text.trim().isEmpty || s.busy ? null : _addManual,
                ),
              ),
            ],
          ),
        ),
        if (err != null)
          Text(
            sourceErrorTexts(l, LinkImportError(code: err.code, message: err.message)).title,
            style: TfText.body(TfSize.font12).copyWith(color: TfColors.danger),
          ),
      ],
    );
  }

  /// Umbral de «cercano» del ranking de candidatos (`CandidateRanker.closeThreshold`).
  /// (SourceKit/CandidateRanker.swift:17: 3 s.)
  static const int _closeSeconds = 3;
}

/// Portada 104×104 radio 10 con borde `fieldLine`; sin imagen: `field` + nota musical (LS:636-646).
class _Cover extends StatelessWidget {
  const _Cover({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    const placeholder = ColoredBox(
      color: TfColors.field,
      child: Center(child: TfIconView(TfIcon.musicNote, size: TfSize.font14, color: TfColors.muted)),
    );
    final u = url;
    return Container(
      width: LibraryMetrics.importCoverSize,
      height: LibraryMetrics.importCoverSize,
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(LibraryMetrics.importCoverRadius),
        border: Border.all(color: TfColors.fieldLine, width: TfStroke.hairline),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(LibraryMetrics.importCoverRadius),
        child: u == null
            ? placeholder
            : Image.network(u, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder),
      ),
    );
  }
}
