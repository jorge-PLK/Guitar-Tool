import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';

/// Tamaños de ventana (docs/flutter/tokens-componentes.md §6).
const Size _minWindowSize = Size(1100, 680);
const Size _initialWindowSize = Size(1440, 900);

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  _configureWindow();
  runApp(const ProviderScope(child: ToneForgeApp()));
}

void _configureWindow() {
  final window = WindowManager.instance.getCurrent();
  if (window == null) return;
  window
    ..title = 'ToneForge'
    ..minimumSize = _minWindowSize.toNative()
    ..setSize(_initialWindowSize.toNative(), false)
    ..center();
}
