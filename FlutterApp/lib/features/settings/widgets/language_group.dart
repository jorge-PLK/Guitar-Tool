import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/locale_pref.dart';
import 'package:toneforge/widgets/tf_dropdown.dart';
import 'package:toneforge/widgets/tf_settings_group.dart';

/// Grupo «Idioma»: desplegable Español / English, se aplica al momento. Sin override se muestra el
/// idioma que la app usa de verdad (el resuelto por el árbol); elegir uno siempre guarda override.
class LanguageGroup extends ConsumerWidget {
  const LanguageGroup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final choice = ref.watch(localeChoiceProvider);
    final shown = switch (choice) {
      LocaleChoice.es || LocaleChoice.en => choice,
      LocaleChoice.system =>
        Localizations.localeOf(context).languageCode == 'en' ? LocaleChoice.en : LocaleChoice.es,
    };
    return TfSettingsGroup(
      title: l.settings_lang_title,
      children: <Widget>[
        TfInfoRow(
          label: l.settings_lang_label,
          trailing: TfDropdown<LocaleChoice>(
            value: shown,
            onChanged: (c) => ref.read(localeChoiceProvider.notifier).set(c),
            items: <TfDropdownItem<LocaleChoice>>[
              TfDropdownItem(value: LocaleChoice.es, label: l.settings_lang_es),
              TfDropdownItem(value: LocaleChoice.en, label: l.settings_lang_en),
            ],
          ),
        ),
      ],
    );
  }
}
