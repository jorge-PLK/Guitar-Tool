import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/models.dart';
import 'package:toneforge/features/settings/settings_models_store.dart';
import 'package:toneforge/features/settings/widgets/models_group.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/l10n/app_localizations_es.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_progress.dart';

import '../../support/harness.dart';

class _FakeModels extends SettingsModelsStore {
  _FakeModels(this.initial);

  final SettingsModelsState initial;

  @override
  SettingsModelsState build() => initial;
}

Future<void> _pump(WidgetTester tester, String stateRaw) async {
  await tester.runAsync(loadTfFonts);
  setTestSurface(tester, const Size(900, 600));
  final model = ModelEntry(
    id: 'demucs',
    name: 'Demucs',
    stateRaw: stateRaw,
    archiveBytes: 300000000,
    fraction: 0.5,
  );
  final c = ProviderContainer(
    overrides: [
      settingsModelsStoreProvider.overrideWith(() => _FakeModels(SettingsModelsState(models: [model], loaded: true))),
    ],
  );
  addTearDown(c.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: WidgetsApp(
        color: TfColors.bg,
        locale: const Locale('es'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        pageRouteBuilder: <T>(RouteSettings s, WidgetBuilder b) =>
            PageRouteBuilder<T>(settings: s, pageBuilder: (ctx, a, b2) => b(ctx)),
        home: const Align(alignment: Alignment.topLeft, child: ModelsGroup()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  final l = AppLocalizationsEs();

  for (final (raw, text) in [('verifying', l.settings_models_verifying), ('installing', l.settings_models_installing)]) {
    testWidgets('$raw: texto de estado, sin barra ni botones', (tester) async {
      await _pump(tester, raw);
      expect(find.text(text), findsOneWidget);
      expect(find.byType(TfProgress), findsNothing);
      expect(find.byType(TfPrimaryButton), findsNothing);
      expect(find.byType(TfSecondaryButton), findsNothing);
      expect(find.text(l.settings_models_download), findsNothing);
      expect(find.text(l.settings_models_delete), findsNothing);
    });
  }
}
