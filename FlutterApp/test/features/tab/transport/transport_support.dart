import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/tab.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/launch_options.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/tab/tab_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/l10n/app_localizations_es.dart';
import 'package:toneforge/shell/selected_project.dart';
import 'package:toneforge/theme/tokens.dart';

import '../../../support/harness.dart';

final AppLocalizationsEs es = AppLocalizationsEs();

const String projectId = '00000000-0000-0000-0000-000000000005';

/// Store de Tablatura con estado fijo que anota las llamadas `span`.
class FakeTabStore extends TabStore {
  FakeTabStore(this.initial);

  final TabStoreState initial;
  final List<TabSpanAction> spans = <TabSpanAction>[];
  final List<bool?> keepAnchors = <bool?>[];

  @override
  TabStoreState build() => initial;

  @override
  Future<TabState?> span(TabSpanAction action, {bool? keepAnchor}) async {
    spans.add(action);
    keepAnchors.add(keepAnchor);
    return null;
  }
}

TabState tabWith({TabSpanInfo? span, TabSelectionInfo? selection}) => TabState(
      projectId: 'p',
      phase: TabPhase.ready,
      tracks: const <TabTrackInfo>[],
      notices: const <String>[],
      canUndo: false,
      canRedo: false,
      editMode: false,
      graceMode: false,
      listenMode: TabListenMode.stems,
      anySolo: false,
      revision: 1,
      span: span,
      selection: selection,
    );

class Rig {
  Rig(this.core, this.tab);

  final MockCore core;
  final FakeTabStore tab;

  List<MockCall> calls(String method) => [for (final c in core.calls) if (c.method == method) c];
}

Future<Rig> pumpTransport(
  WidgetTester tester,
  Widget child, {
  TabState? tab,
  void Function(Json open)? tweak,
}) async {
  await tester.runAsync(loadTfFonts);
  final core = (await tester.runAsync(() async => MockCore.load((await DirectoryFixtureSource.find())!)))!;
  final src = (await tester.runAsync(DirectoryFixtureSource.find))!;
  final path = (await tester.runAsync(src!.list))!.firstWhere((p) => p.endsWith('study.open.result.json'));
  final open = (json.decode((await tester.runAsync(() => src.read(path)))!) as Map).cast<String, Object?>();
  tweak?.call(open);
  core.result('study.open', open);
  setTestSurface(tester, const Size(1300, 300));
  final fake = FakeTabStore(TabStoreState(tab: tab));
  final container = ProviderContainer(overrides: [
    coreClientProvider.overrideWithValue(core),
    launchOptionsProvider.overrideWithValue(const LaunchOptions()),
    tabStoreProvider.overrideWith(() => fake),
  ]);
  addTearDown(container.dispose);
  container.read(selectedProjectProvider.notifier).select(projectId);
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
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  return Rig(core, fake);
}
