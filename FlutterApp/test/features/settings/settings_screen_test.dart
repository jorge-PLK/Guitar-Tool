import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/launch_options.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/settings/settings_screen.dart';
import 'package:toneforge/features/settings/sheets/calibration_sheet.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';

import '../../support/harness.dart';

void main() {
  testWidgets('«Calibrar latencia» abre la hoja de calibración', (tester) async {
    final MockCore core = (await tester.runAsync(() async {
      final src = await DirectoryFixtureSource.find();
      return MockCore.load(src!);
    }))!;
    setTestSurface(tester, const Size(1100, 900));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        coreClientProvider.overrideWithValue(core),
        launchOptionsProvider.overrideWithValue(const LaunchOptions(screen: 'settings-audio')),
      ],
      child: WidgetsApp(
        color: TfColors.bg,
        debugShowCheckedModeBanner: false,
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        pageRouteBuilder: <T>(RouteSettings s, WidgetBuilder b) =>
            PageRouteBuilder<T>(settings: s, pageBuilder: (c, a, b2) => b(c)),
        home: const DefaultTextStyle(style: TextStyle(), child: SettingsScreen()),
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(CalibrationSheet), findsNothing);
    await tester.tap(find.text('Calibrar latencia'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(CalibrationSheet), findsOneWidget);
  });
}
