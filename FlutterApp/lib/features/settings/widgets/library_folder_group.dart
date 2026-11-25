import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/features/library/dialogs/clean_dialog.dart';
import 'package:toneforge/features/library/library_errors.dart';
import 'package:toneforge/features/settings/settings_library_store.dart';
import 'package:toneforge/features/settings/settings_metrics.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/fmt.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_alert.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_settings_group.dart';

import 'folder_dialog.dart';
import 'relocation_progress.dart';

/// Grupo «Biblioteca» (SettingsView.swift:108-135): carpeta, espacio usado, progreso y botones.
class LibraryFolderGroup extends ConsumerWidget {
  const LibraryFolderGroup({super.key});

  Future<void> _change(BuildContext context, WidgetRef ref) async {
    final store = ref.read(settingsLibraryStoreProvider.notifier);
    final path = await store.chooseFolder();
    if (path == null || !context.mounted) return;
    final mode = await showFolderDialog(context, path);
    if (mode == null) return;
    final error = await store.relocate(path, mode);
    if (error == null || !context.mounted) return;
    final l = AppLocalizations.of(context);
    await showTfAlert(
      context: context,
      title: l.library_noticeTitle,
      message: error.code == 'work-in-progress' ? l.settings_lib_workInProgress : coreErrorText(l, error),
      okLabel: l.library_noticeOk,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final s = ref.watch(settingsLibraryStoreProvider);
    final usage = s.usage;
    return TfSettingsGroup(
      title: l.settings_lib_title,
      note: l.settings_lib_note,
      children: <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: SettingsMetrics.folderLabelGap,
          children: <Widget>[
            Text(l.settings_lib_folder, style: TfText.body(13).copyWith(color: TfColors.muted)),
            _FolderField(path: s.projectsFolder ?? '—'),
          ],
        ),
        TfInfoRow(
          label: l.settings_lib_usage,
          trailing: Text(
            usage == null ? '—' : TfFmt.bytes(usage.totalBytes, locale),
            style: TfText.body(14, TfWeight.semibold).copyWith(color: TfColors.text2),
          ),
        ),
        if (s.showRelocateProgress) RelocationProgress(fraction: s.relocateFraction),
        Wrap(
          spacing: SettingsMetrics.buttonGap,
          runSpacing: SettingsMetrics.buttonGap,
          children: <Widget>[
            TfSecondaryButton(
              label: l.settings_lib_change,
              onPressed: s.relocating ? null : () => _change(context, ref),
            ),
            TfSecondaryButton(
              label: l.settings_lib_clean,
              onPressed: () => showCleanDialog(context, ref),
            ),
          ],
        ),
      ],
    );
  }
}

class _FolderField extends StatelessWidget {
  const _FolderField({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: SettingsMetrics.folderFieldMinHeight),
      padding: const EdgeInsets.symmetric(horizontal: TfSpace.s12),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: TfColors.field,
        borderRadius: BorderRadius.circular(TfRadius.field),
        border: Border.all(color: TfColors.fieldLine, width: TfStroke.hairline),
      ),
      child: Text(
        path,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TfText.body().copyWith(color: TfColors.text),
      ),
    );
  }
}
