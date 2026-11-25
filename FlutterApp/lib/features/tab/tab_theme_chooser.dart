import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/library.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/selected_project.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';

/// Tema elegible: solo id y título.
typedef TabChooserTheme = ({String id, String title});

/// Temas con `separationState == done` (TabScreen.swift:27-46). Lee `library.list` por el cliente del núcleo;
/// se sustituirá por el store de Biblioteca cuando exista.
final tabChooserThemesProvider = FutureProvider<List<TabChooserTheme>>((ref) async {
  final r = await ref.watch(coreClientProvider).call(
      'library.list', const <String, Object?>{}, LibraryListResult.fromJson);
  return [
    for (final p in r.projects)
      if (p.separationState == SeparationState.done) (id: p.id, title: p.title),
  ];
});

/// Selector de tema de Tablatura (sin tema elegido).
class TabThemeChooser extends ConsumerWidget {
  const TabThemeChooser({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final themes = ref.watch(tabChooserThemesProvider).value ?? const <TabChooserTheme>[];
    final muted = TfText.body(TfSize.font13).copyWith(color: TfColors.muted);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: TfSpace.s40, vertical: TfSpace.s32),
      child: Align(
        alignment: Alignment.topLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: TfSpace.s16,
          children: [
            Text(l.tab_title, style: TfText.display(30).copyWith(color: TfColors.text)),
            if (themes.isEmpty)
              Text(l.tab_chooserEmpty, style: muted)
            else ...[
              Text(l.tab_chooserPick, style: muted),
              for (final t in themes)
                _ThemeRow(
                  title: t.title,
                  onTap: () => ref.read(selectedProjectProvider.notifier).select(t.id),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ThemeRow extends StatelessWidget {
  const _ThemeRow({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: title,
      excludeSemantics: true,
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: TfSpace.s12, vertical: TfSpace.s10),
            decoration: BoxDecoration(
              color: TfColors.field,
              borderRadius: BorderRadius.circular(TfRadius.control),
            ),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TfText.body(TfSize.font13).copyWith(color: TfColors.text),
            ),
          ),
        ),
      ),
    );
  }
}
