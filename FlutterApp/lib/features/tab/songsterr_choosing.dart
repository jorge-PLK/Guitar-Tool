import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/tab.dart';
import 'package:toneforge/features/tab/songsterr_issue_box.dart';
import 'package:toneforge/features/tab/songsterr_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_progress.dart';
import 'package:toneforge/widgets/tf_scroll.dart';
import 'package:toneforge/widgets/tf_text_field.dart';

/// Paso `.choosing` de la hoja de Songsterr (TSS:63-90).
class SongsterrChoosing extends ConsumerStatefulWidget {
  const SongsterrChoosing({
    super.key,
    required this.sheet,
    required this.previewOpen,
    required this.onOpenPreview,
  });

  final SongsterrSheetState sheet;
  final bool previewOpen;
  final VoidCallback onOpenPreview;

  @override
  ConsumerState<SongsterrChoosing> createState() => _SongsterrChoosingState();
}

class _SongsterrChoosingState extends ConsumerState<SongsterrChoosing> {
  final TextEditingController _link = TextEditingController();

  SongsterrStore get _store => ref.read(songsterrStoreProvider.notifier);

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  bool get _canLink => _link.text.trim().isNotEmpty && !widget.sheet.busy;

  void _submitLink() {
    if (_canLink) _store.link(_link.text.trim());
  }

  void _pick(int songId) {
    _store.select(songId);
    widget.onOpenPreview();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final SongsterrSheetState s = widget.sheet;
    final String? query = s.query;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: TfSpace.s14,
      children: <Widget>[
        if (query != null)
          Text(l.tab_sheetSearch(query), style: const TextStyle(color: TfColors.muted)),
        Expanded(child: _content(l, s)),
        _linkRow(l, s),
        _buttons(l, s),
      ],
    );
  }

  Widget _content(AppLocalizations l, SongsterrSheetState s) {
    final TabSongsterrSearchPhase? phase = s.search?.phase;
    if (phase == null ||
        phase == TabSongsterrSearchPhase.idle ||
        phase == TabSongsterrSearchPhase.searching) {
      return Center(child: _spinnerRow(l.tab_sheetSearching));
    }
    if (phase == TabSongsterrSearchPhase.failed && s.search?.issue != null) {
      return Align(
        alignment: Alignment.topCenter,
        child: SongsterrIssueBox(issue: s.search!.issue!, onRetry: _store.retry),
      );
    }
    return _results(l, s);
  }

  Widget _spinnerRow(String text) => Row(
        mainAxisSize: MainAxisSize.min,
        spacing: TfSpace.s8,
        children: <Widget>[
          const TfSpinner.small(),
          Text(text, style: const TextStyle(color: TfColors.muted)),
        ],
      );

  Widget _results(AppLocalizations l, SongsterrSheetState s) {
    final SongsterrSongInfo? song = s.selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: TfSpace.s10,
      children: <Widget>[
        if (s.loadingSongId != null)
          _spinnerRow(l.tab_sheetReadingTracks)
        else if (song != null)
          _SongCard(song: song),
        if (s.detailIssue != null)
          SongsterrIssueBox(issue: s.detailIssue!, onRetry: _store.retry),
        Text(l.tab_sheetOtherResults, style: const TextStyle(color: TfColors.muted)),
        Expanded(
          child: TfScroll(
            builder: (BuildContext context, ScrollController c) => ListView.separated(
              controller: c,
              padding: EdgeInsets.zero,
              itemCount: s.results.length,
              separatorBuilder: (_, _) => const SizedBox(height: TfSpace.s4),
              itemBuilder: (_, int i) => _ResultRow(
                result: s.results[i],
                onTap: () => _pick(s.results[i].songId),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _linkRow(AppLocalizations l, SongsterrSheetState s) {
    final SongsterrIssueInfo? issue = s.linkIssue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: TfSpace.s6,
      children: <Widget>[
        ListenableBuilder(
          listenable: _link,
          builder: (BuildContext context, _) => Row(
            spacing: TfSpace.s8,
            children: <Widget>[
              Expanded(
                child: TfTextField(
                  controller: _link,
                  hint: l.tab_sheetLinkHint,
                  onSubmitted: (_) => _submitLink(),
                ),
              ),
              TfSecondaryButton(
                label: l.tab_sheetUseLink,
                height: TfSpace.s32,
                onPressed: _canLink ? _submitLink : null,
              ),
            ],
          ),
        ),
        if (issue != null)
          Text(songsterrIssueText(l, issue), style: const TextStyle(color: TfColors.danger)),
      ],
    );
  }

  Widget _buttons(AppLocalizations l, SongsterrSheetState s) => Row(
        spacing: TfSpace.s12,
        children: <Widget>[
          TfSecondaryButton(
            label: l.tab_sheetCancel,
            height: TfSpace.s36,
            onPressed: _store.close,
          ),
          const Spacer(),
          if (!widget.previewOpen)
            TfSecondaryButton(
              label: l.tab_sheetPreview,
              height: TfSpace.s36,
              onPressed: s.selected == null ? null : widget.onOpenPreview,
            ),
          TfSecondaryButton(
            label: l.tab_sheetAutomatic,
            height: TfSpace.s36,
            onPressed: _store.automatic,
          ),
          TfPrimaryButton(label: l.tab_sheetUseThis, onPressed: s.canUse ? _store.use : null),
        ],
      );
}

/// Ficha de la versión marcada: título y una fila por pista.
class _SongCard extends StatelessWidget {
  const _SongCard({required this.song});

  final SongsterrSongInfo song;

  @override
  Widget build(BuildContext context) {
    const TextStyle muted = TextStyle(color: TfColors.muted);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(TfSpace.s12),
      decoration: BoxDecoration(
        color: TfColors.field,
        borderRadius: BorderRadius.circular(TfRadius.control),
        border: Border.all(color: TfColors.fieldLine, width: TfStroke.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: TfSpace.s6,
        children: <Widget>[
          Text(
            '${song.artist} · ${song.title}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TfText.body(14, TfWeight.semibold).copyWith(color: TfColors.text),
          ),
          for (final SongsterrTrackInfo t in song.tracks)
            Row(
              spacing: TfSpace.s10,
              children: <Widget>[
                SizedBox(
                  width: 190,
                  child: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                SizedBox(
                  width: 170,
                  child: Text(t.instrument,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                ),
                Expanded(
                  child: Text(
                    t.tuningText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: muted.copyWith(
                      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Fila marcable de «Otros resultados».
class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.result, required this.onTap});

  final SongsterrResultInfo result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool on = result.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: TfSpace.s10, vertical: TfSpace.s6),
          decoration: BoxDecoration(
            color: on ? TfColors.accentBg : null,
            borderRadius: BorderRadius.circular(TfRadius.field),
          ),
          child: Row(
            spacing: TfSpace.s8,
            children: <Widget>[
              TfIconView(
                on ? TfIcon.largecircleFillCircle : TfIcon.circle,
                size: TfSize.font12,
                color: on ? TfColors.accent : TfColors.muted,
              ),
              Expanded(
                child: Text(
                  '${result.artist} · ${result.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: on ? TfColors.text : TfColors.text2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
