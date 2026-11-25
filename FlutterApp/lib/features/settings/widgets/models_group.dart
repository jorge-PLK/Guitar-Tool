import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/models.dart';
import 'package:toneforge/features/library/library_errors.dart';
import 'package:toneforge/features/settings/settings_metrics.dart';
import 'package:toneforge/features/settings/settings_models_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/fmt.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_alert.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_progress.dart';
import 'package:toneforge/widgets/tf_settings_group.dart';
import 'package:toneforge/widgets/tf_tooltip.dart';

/// Grupo «Modelos» (SettingsView.swift:137-154): una fila por modelo con su estado y botón.
class ModelsGroup extends ConsumerWidget {
  const ModelsGroup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final models = ref.watch(settingsModelsStoreProvider).models;
    return TfSettingsGroup(
      title: l.settings_models_title,
      note: l.settings_models_note,
      children: <Widget>[for (final m in models) ModelRow(entry: m)],
    );
  }
}

/// Fila de un modelo: nombre, estado coloreado, barra si descarga y botón.
class ModelRow extends ConsumerWidget {
  const ModelRow({super.key, required this.entry});

  final ModelEntry entry;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final ok = await showTfConfirm(
      context: context,
      title: l.settings_models_deleteTitle,
      message: l.settings_models_deleteMessage,
      confirmLabel: l.settings_models_delete,
      cancelLabel: l.settings_lib_cancel,
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final error = await ref.read(settingsModelsStoreProvider.notifier).delete(entry.id);
    if (error == null || !context.mounted) return;
    await showTfAlert(
      context: context,
      title: l.library_noticeTitle,
      message: coreErrorText(l, error),
      okLabel: l.library_noticeOk,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final store = ref.read(settingsModelsStoreProvider.notifier);
    final fraction = entry.fraction ?? 0;
    final TextStyle base = TfText.body(TfSize.font14, TfWeight.semibold);
    final (String text, Color color) = switch (entry.state) {
      ModelState.downloading => (l.settings_models_downloading(TfFmt.percent(fraction)), TfColors.accent),
      ModelState.verifying => (l.settings_models_verifying, TfColors.accent),
      ModelState.installing => (l.settings_models_installing, TfColors.accent),
      ModelState.installed => (
        l.settings_models_installed(TfFmt.bytes(entry.bytes ?? 0, locale)),
        TfColors.ok,
      ),
      ModelState.failed => (l.settings_models_error, TfColors.danger),
      _ => (l.settings_models_pending(TfFmt.bytes(entry.archiveBytes, locale)), TfColors.accent),
    };
    Widget status = Text(text, style: base.copyWith(color: color));
    if (entry.state == ModelState.failed && (entry.message ?? '').isNotEmpty) {
      status = TfTooltip(message: entry.message!, child: status);
    }
    final canDelete = entry.state == ModelState.installed && entry.source != ModelSource.folder;
    final canDownload = entry.state == ModelState.notInstalled || entry.state == ModelState.failed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: TfSpace.s14,
      children: <Widget>[
        TfInfoRow(label: entry.name, trailing: status),
        if (entry.state == ModelState.downloading) TfProgress(value: fraction),
        if (canDelete)
          Row(
            spacing: SettingsMetrics.buttonGap,
            children: <Widget>[
              TfSecondaryButton(label: l.settings_models_delete, onPressed: () => _delete(context, ref)),
            ],
          )
        else if (canDownload)
          Row(
            spacing: SettingsMetrics.buttonGap,
            children: <Widget>[
              TfPrimaryButton(label: l.settings_models_download, onPressed: () => store.download(entry.id)),
            ],
          ),
      ],
    );
  }
}
