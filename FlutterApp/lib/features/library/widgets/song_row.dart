import 'dart:io' show File;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/library.dart';
import 'package:toneforge/features/library/dialogs/trash_dialog.dart';
import 'package:toneforge/features/library/import_store.dart';
import 'package:toneforge/features/library/library_format.dart';
import 'package:toneforge/features/library/library_store.dart';
import 'package:toneforge/features/library/sheets/song_info_sheet.dart';
import 'package:toneforge/features/library/widgets/row_context_menu.dart';
import 'package:toneforge/features/library/widgets/song_table.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/selected_project.dart';
import 'package:toneforge/theme/fmt.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_chip.dart';
import 'package:toneforge/widgets/tf_list_row.dart';
import 'package:toneforge/widgets/tf_song_cover.dart';
import 'package:toneforge/widgets/tf_tooltip.dart';

/// Fila de tema (LV:208-254): portada, título/artista, tomas, chip de estado y tres botones.
class SongRow extends ConsumerWidget {
  const SongRow({super.key, required this.entry, this.showArtist = true});

  final ProjectSummary entry;
  final bool showArtist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final selected = ref.watch(selectedProjectProvider) == entry.id;
    final artist = entry.artist;
    final coverPath = resolveCoverPath(
      ref.watch(libraryStoreProvider.select((s) => s.projectsFolder)),
      entry.cover,
    );
    final coverImage = coverPath == null ? null : FileImage(File(coverPath));
    return RowContextMenu(
      entry: entry,
      child: TfListRow(
        selected: selected,
        onTap: () => ref.read(selectedProjectProvider.notifier).select(entry.id),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  TfSongCover(image: coverImage),
                  const SizedBox(width: TfSpace.s14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TfText.body(TfSize.font14, TfWeight.semibold).copyWith(color: TfColors.text),
                        ),
                        if (showArtist && artist != null) ...[
                          const SizedBox(height: TfSpace.s2),
                          Text(
                            artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TfText.body(TfSize.font13).copyWith(color: TfColors.muted),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: SongColumns.takes,
              child: Text(
                entry.takeCount == 0 ? l.library_takesNone : '${entry.takeCount}',
                style: TfText.body().copyWith(color: TfColors.text2),
              ),
            ),
            SizedBox(width: SongColumns.state, child: Align(alignment: Alignment.centerLeft, child: _StateChip(entry: entry))),
            SizedBox(
              width: SongColumns.actions,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TfTooltip(
                    message: isMacHost ? l.library_revealTooltipMac : l.library_revealTooltipWindows,
                    child: TfIconButton(
                      icon: TfIcon.folder,
                      kind: TfIconButtonKind.secondary,
                      semanticLabel: isMacHost ? l.library_revealTooltipMac : l.library_revealTooltipWindows,
                      onPressed: () => revealProject(context, ref, entry.id),
                    ),
                  ),
                  const SizedBox(width: TfSpace.s8),
                  TfTooltip(
                    message: l.library_editTooltip,
                    child: TfIconButton(
                      icon: TfIcon.pencil,
                      kind: TfIconButtonKind.secondary,
                      semanticLabel: l.library_editTooltip,
                      onPressed: () => showSongInfoSheet(context, entry),
                    ),
                  ),
                  const SizedBox(width: TfSpace.s8),
                  TfTooltip(
                    message: l.library_deleteTooltip,
                    child: TfIconButton(
                      icon: TfIcon.trash,
                      semanticLabel: l.library_deleteLabel,
                      onPressed: () => showTrashDialog(context, ref, projectId: entry.id, title: entry.title),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StateChip extends ConsumerWidget {
  const _StateChip({required this.entry});

  final ProjectSummary entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final imports = ref.watch(importStoreProvider);
    return switch (imports.separationStateFor(entry)) {
      SeparationState.queued => TfChip(l.library_stateQueued, kind: TfChipKind.neutral),
      SeparationState.running => TfChip(
          l.library_stateRunning(TfFmt.percent(imports.separationFractionFor(entry.id) ?? 0)),
          kind: TfChipKind.working,
        ),
      SeparationState.done => TfChip(l.library_stateDone, kind: TfChipKind.ok),
      SeparationState.failed => TfTooltip(
          message: imports.separationErrorFor(entry) ?? l.library_stateFailedUnknown,
          child: TfChip(l.library_stateFailed, kind: TfChipKind.error),
        ),
      _ => TfChip(l.library_stateImported, kind: TfChipKind.neutral),
    };
  }
}
