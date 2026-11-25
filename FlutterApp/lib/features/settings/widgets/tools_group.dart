import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/tools.dart';
import 'package:toneforge/features/library/library_errors.dart';
import 'package:toneforge/features/settings/settings_metrics.dart';
import 'package:toneforge/features/settings/settings_tools_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_accent_bar.dart';
import 'package:toneforge/widgets/tf_alert.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_chip.dart';
import 'package:toneforge/widgets/tf_settings_group.dart';

/// Grupo «Fuentes externas» (SettingsView.swift:156-180).
class ToolsGroup extends ConsumerWidget {
  const ToolsGroup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(settingsToolsStoreProvider);
    final store = ref.read(settingsToolsStoreProvider.notifier);
    final info = s.info;
    final origin = info?.ytDlpOrigin;
    String version(String? v) => info == null ? l.settings_tools_checking : (v ?? l.settings_tools_unavailable);
    Widget value(String text) =>
        Text(text, style: TfText.body(14, TfWeight.semibold).copyWith(color: TfColors.text2));
    final result = s.updateResult;
    return TfSettingsGroup(
      title: l.settings_tools_title,
      note: l.settings_tools_note,
      children: <Widget>[
        TfInfoRow(
          label: 'yt-dlp',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: TfSpace.s8,
            children: <Widget>[
              value(version(info?.ytDlpVersion)),
              if (origin == YtDlpOrigin.updated || origin == YtDlpOrigin.embedded)
                TfChip(
                  origin == YtDlpOrigin.updated ? l.settings_tools_updated : l.settings_tools_embedded,
                  kind: origin == YtDlpOrigin.updated ? TfChipKind.ok : TfChipKind.neutral,
                ),
            ],
          ),
        ),
        TfInfoRow(label: 'Deno', trailing: value(version(info?.denoVersion))),
        TfInfoRow(label: 'ffmpeg', trailing: value(version(info?.ffmpegVersion))),
        if (s.updating) const TfAccentBar(),
        if (s.status == YtDlpUpdateStatus.done && result != null)
          Text(
            result.alreadyLatest
                ? l.settings_tools_upToDate(result.version)
                : l.settings_tools_updateDone(result.version),
            style: TfText.body(13).copyWith(color: TfColors.ok),
          ),
        if (s.status == YtDlpUpdateStatus.failed && s.error != null)
          Text(coreErrorText(l, s.error!), style: TfText.body(13).copyWith(color: TfColors.danger)),
        Wrap(
          spacing: SettingsMetrics.buttonGap,
          runSpacing: SettingsMetrics.buttonGap,
          children: <Widget>[
            TfPrimaryButton(label: l.settings_tools_update, onPressed: s.updating ? null : store.updateYtDlp),
            TfSecondaryButton(
              label: l.settings_tools_revert,
              onPressed: s.canRevert ? () => _revert(context, store) : null,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _revert(BuildContext context, SettingsToolsStore store) async {
    final error = await store.revertYtDlp();
    if (error == null || !context.mounted) return;
    final l = AppLocalizations.of(context);
    await showTfAlert(
      context: context,
      title: l.library_noticeTitle,
      message: coreErrorText(l, error),
      okLabel: l.library_noticeOk,
    );
  }
}
