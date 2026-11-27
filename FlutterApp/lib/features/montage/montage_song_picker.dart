import 'package:flutter/widgets.dart';
import 'package:toneforge/contract/library.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_buttons.dart';

/// Selector de tema de Montaje sin tema elegido (MV:7-60): temas con tomas, ya filtrados por el store.
class MontageSongPicker extends StatelessWidget {
  const MontageSongPicker({super.key, required this.songs, required this.onPick, required this.onGoRecord});

  final List<ProjectSummary> songs;
  final ValueChanged<String> onPick;
  final VoidCallback onGoRecord;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final TextStyle muted = TfText.body().copyWith(color: TfColors.muted);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: TfSpace.s40, vertical: TfSpace.s32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l.montageTitle, style: TfText.display(TfSize.font30).copyWith(color: TfColors.text)),
          const SizedBox(height: TfSpace.s16),
          if (songs.isEmpty) ...<Widget>[
            Text(l.montageEmptyNoSongs, style: muted),
            const SizedBox(height: TfSpace.s16),
            TfSecondaryButton(label: l.montageGoRecord, onPressed: onGoRecord),
          ] else ...<Widget>[
            Text(l.montagePickSong, style: muted),
            for (final ProjectSummary p in songs) ...<Widget>[
              const SizedBox(height: TfSpace.s16),
              _SongRow(title: p.title, onTap: () => onPick(p.id)),
            ],
          ],
        ],
      ),
    );
  }
}

class _SongRow extends StatelessWidget {
  const _SongRow({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: title,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: TfSpace.s12, vertical: TfSpace.s10),
            decoration: BoxDecoration(color: TfColors.field, borderRadius: BorderRadius.circular(TfRadius.control)),
            child: Row(
              children: <Widget>[
                Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TfText.body().copyWith(color: TfColors.text))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
