import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/launch_options.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/features/backing/widgets/chords_area.dart';
import 'package:toneforge/features/backing/widgets/chords_expanded.dart';
import 'package:toneforge/features/backing/widgets/chords_header.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/selected_project.dart';
import 'package:toneforge/theme/tokens.dart';

import '../../../support/harness.dart';
import '../screen/screen_support.dart';

export 'package:toneforge/core/core_client.dart' show Json;
export '../screen/screen_support.dart' show es, openFixture, settleFrames, separatedId;

class MemPrefs implements ChordsExpandedPrefStore {
  final Map<String, bool> data = <String, bool>{};

  @override
  Future<bool?> read(String projectId) async => data[projectId];

  @override
  Future<void> write(String projectId, bool expanded) async => data[projectId] = expanded;
}

/// Cuatro acordes de 2 s: Cm, Cm(maj7), G, Am; compases en 0 y 4.
void fourChords(Json open, {double position = 0}) {
  final a = (open['analysis']! as Map).cast<String, Object?>();
  final base = (a['chords']! as List).cast<Map<String, Object?>>().map((m) => m.cast<String, Object?>()).toList();
  Json mk(Json src, String name, int index, double s) =>
      <String, Object?>{...src, 'name': name, 'display': name, 'index': index, 'start': s, 'end': s + 2};
  a['chords'] = <Object?>[
    mk(base[0], 'Cm', 0, 0),
    mk(base[1], 'Cm(maj7)', 7, 2),
    mk(base[0], 'G', 3, 4),
    mk(base[0], 'Am', 5, 6),
  ];
  a['downbeats'] = <Object?>[0.0, 4.0];
  (open['transport']! as Map)['position'] = position;
}

class ChordsRig extends Rig {
  ChordsRig(super.core, super.container, this.prefs);
  final MemPrefs prefs;
}

Future<ChordsRig> pumpChords(
  WidgetTester tester, {
  void Function(Json open)? tweak,
  Size size = const Size(1100, 400),
}) async {
  await tester.runAsync(loadTfFonts);
  final core = (await tester.runAsync(() async => MockCore.load((await DirectoryFixtureSource.find())!)))!;
  final open = (await tester.runAsync(openFixture))!;
  tweak?.call(open);
  core.result('study.open', open);
  setTestSurface(tester, size);
  final prefs = MemPrefs();
  final container = ProviderContainer(overrides: [
    coreClientProvider.overrideWithValue(core),
    launchOptionsProvider.overrideWithValue(const LaunchOptions()),
    chordsExpandedPrefStoreProvider.overrideWithValue(prefs),
  ]);
  addTearDown(container.dispose);
  container.read(selectedProjectProvider.notifier).select(separatedId);
  container.read(studyStoreProvider);
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
        home: const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[ChordsHeader(), ChordsArea()],
        ),
      ),
    ),
  );
  await settleFrames(tester);
  return ChordsRig(core, container, prefs);
}
