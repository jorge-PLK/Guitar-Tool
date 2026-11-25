import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/launch_options.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/selected_project.dart';
import 'package:toneforge/theme/tokens.dart';

import '../../../support/harness.dart';
import '../screen/screen_support.dart' show openFixture;

const String mixerProject = '00000000-0000-0000-0000-000000000005';

Map<String, Object?> ch(String id, String kind,
        {String? role, String? name, double gain = 0, bool muted = false, bool solo = false}) =>
    <String, Object?>{
      'id': id,
      'kind': kind,
      'guitarRole': ?role,
      'name': name ?? id,
      'gainDB': gain,
      'muted': muted,
      'solo': solo,
    };

class MixerRig {
  MixerRig(this.core, this.container);

  final MockCore core;
  final ProviderContainer container;

  List<Json> callsOf(String method) =>
      <Json>[for (final MockCall c in core.calls) if (c.method == method) (c.params! as Map).cast<String, Object?>()];
}

/// Monta [child] con un `MockCore` real y el estudio del fixture abierto; [tweak] retoca el `study.open`.
Future<MixerRig> pumpMixer(
  WidgetTester tester,
  Widget child, {
  void Function(Json open, Json transport)? tweak,
  Size size = const Size(1100, 700),
}) async {
  await tester.runAsync(loadTfFonts);
  final MockCore core = (await tester.runAsync(() async => MockCore.load((await DirectoryFixtureSource.find())!)))!;
  final Json open = (await tester.runAsync(openFixture))!;
  tweak?.call(open, (open['transport']! as Map).cast<String, Object?>());
  core.result('study.open', open);
  setTestSurface(tester, size);
  final ProviderContainer container = ProviderContainer(overrides: [
    coreClientProvider.overrideWithValue(core),
    launchOptionsProvider.overrideWithValue(const LaunchOptions()),
  ]);
  addTearDown(container.dispose);
  container.read(selectedProjectProvider.notifier).select(mixerProject);
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
        home: Align(alignment: Alignment.topLeft, child: child),
      ),
    ),
  );
  for (int i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  return MixerRig(core, container);
}
