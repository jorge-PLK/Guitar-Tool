import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'core/core_providers.dart';
import 'l10n/app_localizations.dart';
import 'shell/shell_screen.dart';
import 'shell/snapshot.dart';

/// Idioma de respaldo cuando el del sistema no está entre los soportados.
const Locale _fallbackLocale = Locale('es');

/// Raíz de la app. Tema oscuro único; idioma de `--locale` o del sistema (es de respaldo).
class ToneForgeApp extends ConsumerWidget {
  const ToneForgeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final forced = ref.watch(launchOptionsProvider).locale;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context).shell_appTitle,
      theme: ThemeData(brightness: Brightness.dark),
      locale: forced == null ? null : Locale(forced),
      localeResolutionCallback: (locale, supported) {
        for (final s in supported) {
          if (s.languageCode == locale?.languageCode) return s;
        }
        return _fallbackLocale;
      },
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => SnapshotHost(child: child!),
      home: const ShellScreen(),
    );
  }
}
