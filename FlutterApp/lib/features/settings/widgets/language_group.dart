import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/features/settings/settings_metrics.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/locale_pref.dart';
import 'package:toneforge/widgets/tf_segmented.dart';
import 'package:toneforge/widgets/tf_settings_group.dart';

/// Grupo «Idioma» (nuevo en la 7f): Sistema / Español / English, se aplica al momento. Sin nota.
class LanguageGroup extends ConsumerWidget {
  const LanguageGroup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final choice = ref.watch(localeChoiceProvider);
    return TfSettingsGroup(
      title: l.settings_lang_title,
      note: '',
      children: <Widget>[
        TfInfoRow(
          label: l.settings_lang_label,
          trailing: TfSegmented<LocaleChoice>(
            width: SettingsMetrics.languageSegmentWidth,
            value: choice,
            onChanged: (c) => ref.read(localeChoiceProvider.notifier).set(c),
            segments: <TfSegment<LocaleChoice>>[
              TfSegment(value: LocaleChoice.system, label: l.settings_lang_system),
              TfSegment(value: LocaleChoice.es, label: l.settings_lang_es),
              TfSegment(value: LocaleChoice.en, label: l.settings_lang_en),
            ],
          ),
        ),
      ],
    );
  }
}
