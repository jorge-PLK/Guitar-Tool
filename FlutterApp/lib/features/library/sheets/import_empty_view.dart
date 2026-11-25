import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/features/library/import_store.dart';
import 'package:toneforge/features/library/library_metrics.dart';
import 'package:toneforge/features/library/link_import_store.dart';
import 'package:toneforge/features/library/sheets/import_banner.dart';
import 'package:toneforge/features/library/sheets/spotify_track_row.dart';
import 'package:toneforge/features/library/source_messages.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_progress.dart';
import 'package:toneforge/widgets/tf_text_field.dart';

/// Pantalla vacía de la hoja: campo de enlace, ayuda / error / resultados de Spotify y pie
/// (LinkImportSheet.swift:479-523). [onClose] cierra la hoja.
class ImportEmptyView extends ConsumerStatefulWidget {
  const ImportEmptyView({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  ConsumerState<ImportEmptyView> createState() => _ImportEmptyViewState();
}

class _ImportEmptyViewState extends ConsumerState<ImportEmptyView> {
  late final TextEditingController _ctrl = TextEditingController(text: ref.read(linkImportStoreProvider).text);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(linkImportStoreProvider);
    final store = ref.read(linkImportStoreProvider.notifier);
    if (_ctrl.text != s.text) {
      _ctrl.value = TextEditingValue(text: s.text, selection: TextSelection.collapsed(offset: s.text.length));
    }
    final importing = ref.watch(importStoreProvider.select((x) => x.importing));
    Widget help() => Text(l.library_importSupported, style: TfText.body(12).copyWith(color: TfColors.muted));
    final err = s.spotifyError;
    final tracks = s.spotifyTracks;
    final Widget area;
    if (err != null) {
      final msg = sourceErrorTexts(l, LinkImportError(code: err.code, message: err.message)).title;
      area = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: TfSpace.s14,
        children: [ImportBanner(text: msg), help()],
      );
    } else if (tracks == null) {
      area = help();
    } else if (tracks.isEmpty) {
      area = Text(
        l.library_importSpotifyNone(s.spotifyQuery ?? ''),
        style: TfText.body(13).copyWith(color: TfColors.muted),
      );
    } else {
      area = DecoratedBox(
        decoration: BoxDecoration(color: TfColors.field, borderRadius: BorderRadius.circular(TfRadius.field)),
        child: Column(
          children: [
            for (var i = 0; i < tracks.length; i++) ...[
              if (i > 0) Container(height: TfStroke.hairline, color: TfColors.line),
              SpotifyTrackRow(track: tracks[i]),
            ],
          ],
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: TfSpace.s14,
      children: [
        Stack(
          alignment: Alignment.centerRight,
          children: [
            SizedBox(
              height: LibraryMetrics.linkFieldHeight,
              child: TfTextField(
                controller: _ctrl,
                hint: l.library_importLinkHint,
                onChanged: store.setText,
                onSubmitted: (_) => store.submit(),
              ),
            ),
            if (s.searching)
              const Padding(padding: EdgeInsets.only(right: TfSpace.s12), child: TfSpinner.small()),
          ],
        ),
        area,
        Row(
          spacing: TfSpace.s12,
          children: [
            TfSecondaryButton(
              label: l.library_importFile,
              onPressed: importing || s.busy
                  ? null
                  : () {
                      ref.read(importStoreProvider.notifier).pickAndImport();
                      widget.onClose();
                    },
            ),
            const Spacer(),
            TfSecondaryButton(label: l.library_importCancel, onPressed: widget.onClose),
            TfPrimaryButton(label: l.library_importGo, onPressed: s.canSubmit ? store.submit : null),
          ],
        ),
      ],
    );
  }
}
