import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/library.dart';
import 'package:toneforge/features/backing/separated_projects.dart';
import 'package:toneforge/features/tab/tab_theme_chooser.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/selected_project.dart';
import 'package:toneforge/theme/tokens.dart';

import '../../../support/harness.dart';

const _empty = 'Aún no hay temas separados. Importa uno y sepáralo en la biblioteca.';

Future<void> _pump(
  WidgetTester tester, {
  required Future<List<ProjectSummary>> Function() list,
  required Future<String?> Function() launch,
}) async {
  setTestSurface(tester, const Size(1100, 700));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      separatedProjectsProvider.overrideWith((ref) => list()),
      launchProjectIdProvider.overrideWith((ref) => launch()),
    ],
    child: WidgetsApp(
      color: TfColors.bg,
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: const [AppLocalizations.delegate, DefaultWidgetsLocalizations.delegate],
      pageRouteBuilder: <T>(RouteSettings s, WidgetBuilder b) => PageRouteBuilder<T>(
          settings: s, pageBuilder: (c, a, b2) => b(c)),
      home: const DefaultTextStyle(style: TextStyle(), child: TabThemeChooser()),
    ),
  ));
}

void main() {
  setUpAll(loadTfFonts);

  testWidgets('lista cargando: no sale «Aún no hay temas»', (tester) async {
    final never = Completer<List<ProjectSummary>>();
    await _pump(tester, list: () => never.future, launch: () async => null);
    await tester.pump();
    expect(find.text('Tablatura'), findsOneWidget);
    expect(find.text(_empty), findsNothing);
  });

  testWidgets('--project por resolver: no sale «Aún no hay temas»', (tester) async {
    final never = Completer<String?>();
    await _pump(tester, list: () async => const [], launch: () => never.future);
    await tester.pump();
    await tester.pump();
    expect(find.text(_empty), findsNothing);
  });

  testWidgets('lista resuelta y vacía: sí sale el estado vacío', (tester) async {
    await _pump(tester, list: () async => const [], launch: () async => null);
    await tester.pump();
    await tester.pump();
    expect(find.text(_empty), findsOneWidget);
  });
}
