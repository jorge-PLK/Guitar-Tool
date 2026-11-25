import 'dart:async';

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

/// En macOS la ventana aún no es «la actual» cuando arranca `main`: se reintenta unos instantes.
void _configureWindow(LaunchOptions options, [int attempt = 0]) {
  final window = WindowManager.instance.getCurrent();
  if (window == null) {
    if (attempt < 50) {
      Timer(const Duration(milliseconds: 100), () => _configureWindow(options, attempt + 1));
    }
    return;
  }
  final w = options.window;
  final size = w == null ? _initialWindowSize : Size(w.width.toDouble(), w.height.toDouble());
  window
    ..title = 'ToneForge' // tf-literal-ok: nombre de la marca; window_manager lo pide antes de que exista un contexto con AppLocalizations
    ..minimumSize = _minWindowSize.toNative()
    ..setSize(size.toNative(), false)
    ..center();
  // Al mostrarse la ventana (primer fotograma) macOS puede devolverla a su tamaño previo: se reaplica.
  Timer(const Duration(seconds: 1), () {
    window
      ..setSize(size.toNative(), false)
      ..center();
  });
}
