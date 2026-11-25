import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/launch_options.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/backing/backing_screen.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/l10n/app_localizations_es.dart';
import 'package:toneforge/shell/selected_project.dart';
import 'package:toneforge/theme/tokens.dart';

import '../../../support/harness.dart';

final AppLocalizationsEs es = AppLocalizationsEs();

/// Proyecto separado del fixture de `library.list`.
const String separatedId = '00000000-0000-0000-0000-000000000005';

class Rig {
  Rig(this.core, this.container);

  final MockCore core;
  final ProviderContainer container;

  List<String> get methods => [for (final m in core.calls) m.method];
}

Json _decode(String s) => (json.decode(s) as Map).cast<String, Object?>();

/// Copia profunda del `study.open` del fixture, para que cada test la retoque.
Future<Json> openFixture() async {
  final src = (await DirectoryFixtureSource.find())!;
  final path = (await src.list()).firstWhere((p) => p.endsWith('study.open.result.json'));
  return _decode(await src.read(path));
}

/// Monta [BackingScreen] con un `MockCore` real. [tweak] retoca el `study.open` antes de abrir;
/// [project] = proyecto ya elegido (o `null` para el selector); [setup] ajusta el núcleo antes del primer fotograma.
Future<Rig> pumpBacking(
  WidgetTester tester, {
  String? project = separatedId,
  void Function(Json open)? tweak,
  void Function(MockCore core)? setup,
  Size size = const Size(1100, 900),
  bool settle = true,
}) async {
  await tester.runAsync(loadTfFonts);
  final core = (await tester.runAsync(() async => MockCore.load((await DirectoryFixtureSource.find())!)))!;
  final open = (await tester.runAsync(openFixture))!;
  tweak?.call(open);
  core.result('study.open', open);
  setup?.call(core);
  setTestSurface(tester, size);
  final container = ProviderContainer(overrides: [
    coreClientProvider.overrideWithValue(core),
    launchOptionsProvider.overrideWithValue(const LaunchOptions()),
  ]);
  addTearDown(container.dispose);
  if (project != null) container.read(selectedProjectProvider.notifier).select(project);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: WidgetsApp(
        color: TfColors.bg,
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        debugShowCheckedModeBanner: false,
        pageRouteBuilder: <T>(RouteSettings s, WidgetBuilder b) => PageRouteBuilder<T>(
          settings: s,
          pageBuilder: (BuildContext c, Animation<double> a, Animation<double> b2) => b(c),
        ),
        home: const BackingScreen(),
      ),
    ),
  );
  if (settle) await settleFrames(tester);
  return Rig(core, container);
}

/// Avanza fotogramas sin `pumpAndSettle` (el spinner anima sin fin).
Future<void> settleFrames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}
