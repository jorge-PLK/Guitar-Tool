import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/core_providers.dart';
import 'core/launch_options.dart';
import 'shell/locale_pref.dart';
import 'theme/typography.dart';

/// Tamaños de ventana (docs/flutter/tokens-componentes.md §6).
const Size _minWindowSize = Size(1100, 680);
const Size _initialWindowSize = Size(1440, 900);

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final options = LaunchOptions.parse(args);
  registerFontLicenses();
  _configureWindow(options);
  // Idioma guardado antes del primer fotograma (con `--locale` no se lee).
  final savedLocale = options.locale == null ? await readSavedLocaleChoice() : null;
  runApp(
    ProviderScope(
      overrides: [
        launchOptionsProvider.overrideWithValue(options),
        preloadedLocaleChoiceProvider.overrideWithValue(savedLocale),
      ],
      child: const ToneForgeApp(),
    ),
  );
}

void _configureWindow(LaunchOptions options) {
  final window = WindowManager.instance.getCurrent();
  if (window == null) return;
  final w = options.window;
  final size = w == null ? _initialWindowSize : Size(w.width.toDouble(), w.height.toDouble());
  window
    ..title = 'ToneForge' // tf-literal-ok: nombre de la marca; window_manager lo pide antes de que exista un contexto con AppLocalizations
    ..minimumSize = _minWindowSize.toNative()
    ..setSize(size.toNative(), false)
    ..center();
}
