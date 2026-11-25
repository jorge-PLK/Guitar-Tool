import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/library/import_store.dart';
import 'package:toneforge/features/library/library_alerts_host.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/l10n/app_localizations_es.dart';
import 'package:toneforge/theme/tokens.dart';

import '../../support/harness.dart';
import 'library_store_test.dart' show project, setup;

const _ms = Duration(milliseconds: 300);
final _l = AppLocalizationsEs();

void main() {
  testWidgets('host: con el núcleo en error no lanza y muestra el hijo', (tester) async {
    final c = ProviderContainer(overrides: [coreClientProvider.overrideWith((ref) => throw StateError('sin núcleo'))]);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: LibraryAlertsHost(child: Text('hijo')),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('hijo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('host: avisos seguidos se muestran uno a uno, en orden', (tester) async {
    late ProviderContainer c;
    late MockCore core;
    await tester.runAsync(() async {
      await loadTfFonts();
      final r = await setup(projects: [project('00000000-0000-0000-0000-000000000005', 'Delta')]);
      c = r.$1;
      core = r.$2;
    });
    setTestSurface(tester, const Size(800, 600));
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
          home: const LibraryAlertsHost(child: SizedBox.expand()),
        ),
      ),
    );
    await tester.pump();
    final store = c.read(importStoreProvider.notifier);
    for (final m in ['Uno', 'Dos', 'Tres']) {
      core.failWith('import.file', CoreError('unsupported', m));
      await tester.runAsync(() => store.importPaths(['/x/a.wav']));
    }
    await tester.pump(_ms);
    expect(find.text(_l.library_noticeOk), findsOneWidget);
    expect(find.text('Uno'), findsOneWidget);
    expect(find.text('Dos'), findsNothing);
    for (final (shown, next) in [('Uno', 'Dos'), ('Dos', 'Tres')]) {
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(_ms);
      await tester.pump(_ms);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(_ms);
      await tester.pump(_ms);
      expect(find.text(shown), findsNothing);
      expect(find.text(next), findsOneWidget);
      expect(find.text(_l.library_noticeOk), findsOneWidget);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(_ms);
    await tester.pump(_ms);
    expect(find.text(_l.library_noticeOk), findsNothing);
  });
}
