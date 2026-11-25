import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/library.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_sheet.dart';

import '../library_errors.dart';
import '../library_metrics.dart';
import '../library_store.dart';
import '../widgets/song_info_fields.dart';

/// Abre la hoja «Corregir título y artista» (SongInfoSheet, AG:133-167).
Future<void> showSongInfoSheet(BuildContext context, ProjectSummary entry) => showTfSheet<void>(
  context: context,
  builder: (BuildContext ctx) => _SongInfoSheet(entry: entry),
);

class _SongInfoSheet extends ConsumerStatefulWidget {
  const _SongInfoSheet({required this.entry});

  final ProjectSummary entry;

  @override
  ConsumerState<_SongInfoSheet> createState() => _SongInfoSheetState();
}

class _SongInfoSheetState extends ConsumerState<_SongInfoSheet> {
  late final TextEditingController _title = TextEditingController(text: widget.entry.title);
  late final TextEditingController _artist = TextEditingController(text: widget.entry.artist ?? '');
  final FocusNode _focus = FocusNode();
  bool _saving = false;

  bool get _canSave => _title.text.trim().isNotEmpty && !_saving;

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    final nav = Navigator.of(context);
    final err = await ref.read(libraryStoreProvider.notifier).rename(widget.entry.id, _title.text, _artist.text);
    if (!mounted) return;
    if (err == null) {
      nav.pop();
      return;
    }
    setState(() => _saving = false);
    final l = AppLocalizations.of(context);
    await showCoreErrorAlert(
      context,
      err,
      title: err.code == 'empty-title' ? l.library_errTitleEmptyTitle : l.library_errSave,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter): _save,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _save,
      },
      child: TfSheetScaffold(
        width: LibraryMetrics.songInfoSheetWidth,
        padding: TfSpace.s28,
        title: l.library_editSheetTitle,
        body: Padding(
          padding: const EdgeInsets.only(top: TfSpace.s6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: TfSpace.s18,
            children: <Widget>[
              SongInfoFields(
                titleController: _title,
                artistController: _artist,
                titleFocus: _focus,
                autofocusTitle: true,
                onSubmitted: _save,
                onChanged: () => setState(() {}),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                spacing: TfSpace.s10,
                children: <Widget>[
                  TfSecondaryButton(
                    label: l.library_cancel,
                    height: LibraryMetrics.songInfoButtonHeight,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  TfPrimaryButton(label: l.library_save, onPressed: _canSave ? _save : null),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
