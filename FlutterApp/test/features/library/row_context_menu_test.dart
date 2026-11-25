import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/library.dart';
import 'package:toneforge/features/library/import_store.dart';
import 'package:toneforge/features/library/widgets/row_context_menu.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/l10n/app_localizations_es.dart';
import 'package:toneforge/theme/tokens.dart';

class _FakeImport extends ImportStore {
  @override
  ImportState build() => const ImportState();
}

ProjectSummary _project(SeparationState s) => ProjectSummary(
  id: 'p1',
  title: 'Delta',
  folderName: 'Delta',
  duration: 1,
  sampleRate: 44100,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  separationState: s,
  stemCount: 0,
  takeCount: 0,
  rigCount: 0,
  hasAnalysis: false,
  guitars: const [],
);

Future<void> _openMenu(WidgetTester tester, SeparationState s) async {
  final c = ProviderContainer(overrides: [importStoreProvider.overrideWith(_FakeImport.new)]);
  addTearDown(c.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: WidgetsApp(
        color: TfColors.bg,
        locale: const Locale('es'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        pageRouteBuilder: <T>(RouteSettings st, WidgetBuilder b) =>
            PageRouteBuilder<T>(settings: st, pageBuilder: (ctx, a, b2) => b(ctx)),
        home: Center(
          child: RowContextMenu(
            entry: _project(s),
            child: const Text('fila', key: Key('row')),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('row')), buttons: kSecondaryButton);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  final l = AppLocalizationsEs();



  testWidgets('reposo: separar, limpiar, revelar y eliminar; sin cancelar', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await _openMenu(tester, SeparationState.none);
    expect(find.text(l.library_menuSeparate), findsOneWidget);
    expect(find.text(l.library_menuClean), findsOneWidget);
    expect(find.text(l.library_menuRevealMac), findsOneWidget);
    expect(find.text(l.library_menuDelete), findsOneWidget);
    expect(find.text(l.library_menuCancelSeparation), findsNothing);
  });

  testWidgets('separando: aparece «Cancelar separación»', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await _openMenu(tester, SeparationState.running);
    expect(find.text(l.library_menuCancelSeparation), findsOneWidget);
    expect(find.text(l.library_menuSeparate), findsOneWidget);
    expect(find.text(l.library_menuClean), findsOneWidget);
    expect(find.text(l.library_menuDelete), findsOneWidget);
  });

  testWidgets('en cola cuenta como separando', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await _openMenu(tester, SeparationState.queued);
    expect(find.text(l.library_menuCancelSeparation), findsOneWidget);
  });

  testWidgets('macOS: «Finder»', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await _openMenu(tester, SeparationState.none);
    expect(find.text(l.library_menuRevealMac), findsOneWidget);
    expect(find.text(l.library_menuRevealWindows), findsNothing);
  });

  testWidgets('Windows: «Explorador de archivos»', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await _openMenu(tester, SeparationState.none);
    expect(find.text(l.library_menuRevealWindows), findsOneWidget);
    expect(find.text(l.library_menuRevealMac), findsNothing);
  });
}
