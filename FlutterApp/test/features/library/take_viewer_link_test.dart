import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/frame_channel.dart';
import 'package:toneforge/core/frame_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/library/library_prefs.dart';
import 'package:toneforge/features/library/project_detail_page.dart';
import 'package:toneforge/features/record/sheets/take_viewer_sheet.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/library_detail.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_buttons.dart';

import '../../support/harness.dart';

const _id = '00000000-0000-0000-0000-000000000001';

class _Prefs implements LibraryPrefs {
  @override
  Future<String?> get(String key) async => null;
  @override
  Future<void> set(String key, String value) async {}
}

Json _fx(String path) =>
    (json.decode(File('../Contract/fixtures/$path.json').readAsStringSync()) as Map).cast<String, Object?>();

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() async => pumpEventQueue());
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('pulsar «Ver toma» abre el visor con ese takeId y takeview.open', (tester) async {
    await tester.runAsync(loadTfFonts);
    setTestSurface(tester, const Size(1100, 900));
    final project = _fx('library/library.project.result');
    final takes = [
      for (final part in project['parts']! as List)
        for (final t in (part as Map)['takes'] as List) (t as Map).cast<String, Object?>(),
    ];
    final takeId = takes[1]['id']! as String;
    final core = MockCore()
      ..result('library.project', project)
      ..result('library.list', {'projects': <Object>[], 'skipped': <Object>[]})
      ..result('takeview.open', {..._fx('takeview/takeview.open.result'), 'takeId': takeId})
      ..result('takeview.close', <String, Object?>{});
    final c = ProviderContainer(overrides: [
      coreClientProvider.overrideWithValue(core),
      libraryPrefsProvider.overrideWithValue(_Prefs()),
      frameChannelProvider(FrameChannelId.take).overrideWithValue(null),
    ]);
    addTearDown(c.dispose);
    c.read(libraryDetailProvider.notifier).open(_id);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: WidgetsApp(
        color: TfColors.bg,
        debugShowCheckedModeBanner: false,
        locale: const Locale('es'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        pageRouteBuilder: <T>(RouteSettings s, WidgetBuilder b) =>
            PageRouteBuilder<T>(settings: s, pageBuilder: (ctx, a, b2) => b(ctx)),
        home: const DefaultTextStyle(style: TextStyle(), child: ProjectDetailPage(projectId: _id)),
      ),
    ));
    await _settle(tester);

    await tester.tap(find.widgetWithText(TfSecondaryButton, 'Ver toma').at(1));
    await _settle(tester);

    final sheet = tester.widget<TakeViewerSheet>(find.byType(TakeViewerSheet));
    expect(sheet.takeId, takeId);
    expect(sheet.projectId, _id);
    final open = core.calls.firstWhere((x) => x.method == 'takeview.open');
    expect(open.params, {'projectId': _id, 'takeId': takeId});
    expect(find.text('Toma 2 · Rítmica'), findsOneWidget);

    // Cerrar libera el visor en el núcleo.
    await tester.tap(find.byKey(const ValueKey('viewer-close')));
    await _settle(tester);
    expect(core.calls.any((x) => x.method == 'takeview.close'), isTrue);
  });
}
