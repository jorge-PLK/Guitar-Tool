import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/app.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/launch_options.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/shell/shell_providers.dart';
import 'package:toneforge/shell/shell_screen.dart';

import 'harness.dart';

/// Monta la app completa (1440x900 a 1x) con un `MockCore` de fixtures; [onExit] sustituye al cierre real.
Future<ProviderContainer> pumpShell(
  WidgetTester tester, {
  LaunchOptions options = const LaunchOptions(mock: true, locale: 'es'),
  VoidCallback? onExit,
  Size size = const Size(1440, 900),
}) async {
  await tester.runAsync(loadTfFonts);
  final MockCore? core = await tester.runAsync(() async => MockCore.load((await DirectoryFixtureSource.find())!));
  setTestSurface(tester, size);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        launchOptionsProvider.overrideWithValue(options),
        coreClientProvider.overrideWithValue(core!),
        appExitProvider.overrideWithValue(() async => onExit?.call()),
      ],
      child: const ToneForgeApp(),
    ),
  );
  await tester.pump();
  return ProviderScope.containerOf(tester.element(find.byType(ShellScreen)));
}
