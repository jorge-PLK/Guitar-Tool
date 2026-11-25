import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/library/library_prefs.dart';
import 'package:toneforge/features/library/project_detail_page.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/library_detail.dart';
import 'package:toneforge/shell/selected_project.dart';
import 'package:toneforge/shell/shell_providers.dart';
import 'package:toneforge/shell/shell_route.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_buttons.dart';

import '../../support/harness.dart';

const _id = '00000000-0000-0000-0000-000000000001';

class _MemoryPrefs implements LibraryPrefs {
  final Map<String, String> values = {};

  @override
  Future<String?> get(String key) async => values[key];

  @override
  Future<void> set(String key, String value) async => values[key] = value;
}

late MockCore _core;
late ProviderContainer _c;

Future<Json> _fixture(WidgetTester tester) async {
  final s = (await tester.runAsync(() async {
    final src = (await DirectoryFixtureSource.find())!;
    return src.read('library/library.project.result.json');
  }))!;
  return (json.decode(s) as Map).cast<String, Object?>();
}

List<Json> _takes(Json p) => [
  for (final part in p['parts']! as List)
    for (final t in (part as Map)['takes'] as List) (t as Map).cast<String, Object?>(),
];

Future<void> _pump(WidgetTester tester, {void Function(Json p)? edit}) async {
  await tester.runAsync(loadTfFonts);
  setTestSurface(tester, const Size(1100, 900));
  _core = (await tester.runAsync(() async => MockCore.load((await DirectoryFixtureSource.find())!)))!;
  final p = await _fixture(tester);
  edit?.call(p);
  _core.result('library.project', p);
  _core.result('library.list', {'projects': <Object>[], 'skipped': <Object>[]});
  _c = ProviderContainer(
    overrides: [coreClientProvider.overrideWithValue(_core), libraryPrefsProvider.overrideWithValue(_MemoryPrefs())],
  );
  addTearDown(_c.dispose);
  _c.read(libraryDetailProvider.notifier).open(_id);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: _c,
      child: WidgetsApp(
        color: TfColors.bg,
        debugShowCheckedModeBanner: false,
        locale: const Locale('es'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        pageRouteBuilder: <T>(RouteSettings s, WidgetBuilder b) =>
            PageRouteBuilder<T>(settings: s, pageBuilder: (ctx, a, b2) => b(ctx)),
        home: RepaintBoundary(
          key: k5Boundary,
          child: ColoredBox(
            color: TfColors.bg,
            child: DefaultTextStyle(
              style: TfText.body().copyWith(color: TfColors.text),
              child: const ProjectDetailPage(projectId: _id),
            ),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() async => pumpEventQueue());
  await tester.pump();
  await tester.pump();
}

VoidCallback? _onPressed(WidgetTester tester, Finder f) {
  final w = tester.widget(f);
  if (w is TfSecondaryButton) return w.onPressed;
  if (w is TfPrimaryButton) return w.onPressed;
  throw StateError('tipo ${w.runtimeType}');
}

Future<void> _startEdit(WidgetTester tester) async {
  await tester.tap(find.byWidgetPredicate((w) => w is TfIconView && w.icon == TfIcon.pencil));
  await tester.pump();
  await tester.pump();
}

int _calls(String m) => _core.calls.where((c) => c.method == m).length;

void main() {
  testWidgets('datos: frecuencia, duración, estado y stems', (tester) async {
    await _pump(tester);
    expect(find.text('Delta'), findsOneWidget);
    expect(find.text('Banda'), findsOneWidget);
    expect(find.text('44,1 kHz'), findsOneWidget);
    expect(find.text('0:10'), findsOneWidget);
    expect(find.text('Separado'), findsOneWidget);
    expect(find.text('Stems'), findsOneWidget);
    expect(find.text('Sin stems todavía.'), findsNothing);
    expect(find.text('Toma 2'), findsOneWidget);
    expect(find.text('Rítmica'), findsWidgets);
  });

  testWidgets('sin stems y sin tomas: textos vacíos', (tester) async {
    await _pump(
      tester,
      edit: (p) {
        p['stems'] = <Object>[];
        p['stemCount'] = 0;
        p['takeCount'] = 0;
        p['parts'] = <Object>[];
        p['separationState'] = 'none';
      },
    );
    expect(find.text('Sin stems todavía.'), findsOneWidget);
    expect(find.text('Este tema aún no tiene tomas grabadas.'), findsOneWidget);
    expect(find.text('Importado'), findsOneWidget);
    expect(find.text('Abrir en Backing track'), findsNothing);
    await expectLater(find.byKey(k5Boundary), matchesGoldenFile('goldens/project_detail_no_takes.png'));
  });

  testWidgets('Ver toma deshabilitado sin audio o sin songStart', (tester) async {
    await _pump(tester, edit: (p) => _takes(p)[2].remove('songStart'));
    final f = find.widgetWithText(TfSecondaryButton, 'Ver toma');
    expect(f, findsNWidgets(4));
    expect(_onPressed(tester, f.at(0)), isNull); // sin audio
    expect(_onPressed(tester, f.at(1)), isNotNull);
    expect(_onPressed(tester, f.at(2)), isNull); // sin songStart
  });

  testWidgets('golden con datos', (tester) async {
    await _pump(tester);
    await expectLater(find.byKey(k5Boundary), matchesGoldenFile('goldens/project_detail_full.png'));
  });

  testWidgets('Guardar deshabilitado con título vacío', (tester) async {
    await _pump(tester);
    await _startEdit(tester);
    final save = find.widgetWithText(TfPrimaryButton, 'Guardar');
    expect(_onPressed(tester, save), isNotNull);
    await tester.enterText(find.byType(EditableText).first, '');
    await tester.pump();
    expect(_onPressed(tester, save), isNull);
  });

  testWidgets('rename sin artist si el artista está vacío', (tester) async {
      await _pump(tester);
    _core.result('library.rename', {'id': _id, 'title': 'Delta bis'});
    await _startEdit(tester);
    await tester.enterText(find.byType(EditableText).at(0), 'Delta bis');
    await tester.enterText(find.byType(EditableText).at(1), '  ');
    await tester.pump();
    await tester.tap(find.widgetWithText(TfPrimaryButton, 'Guardar'));
    await _settle(tester);
    final call = _core.calls.firstWhere((c) => c.method == 'library.rename');
    final params = (call.params! as Map).cast<String, Object?>();
    expect(params['title'], 'Delta bis');
    expect(params.containsKey('artist'), isFalse);
    expect(find.widgetWithText(TfPrimaryButton, 'Guardar'), findsNothing);
  });

  testWidgets('si rename falla sigue en edición', (tester) async {
    await _pump(tester);
    _core.failWithFixture('library.rename');
    await _startEdit(tester);
    await tester.enterText(find.byType(EditableText).at(0), 'Otro');
    await tester.pump();
    await tester.tap(find.widgetWithText(TfPrimaryButton, 'Guardar'));
    await _settle(tester);
    expect(_calls('library.rename'), 1);
    expect(find.widgetWithText(TfPrimaryButton, 'Guardar'), findsOneWidget);
  });

  testWidgets('Esc cancela la edición', (tester) async {
    await _pump(tester);
    await _startEdit(tester);
    expect(find.widgetWithText(TfPrimaryButton, 'Guardar'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.widgetWithText(TfPrimaryButton, 'Guardar'), findsNothing);
    expect(_calls('library.rename'), 0);
  });

  testWidgets('plurales de punches', (tester) async {
    await _pump(tester, edit: (p) => _takes(p)[2]['punchCount'] = 2);
    expect(find.text('1 punch'), findsOneWidget);
    expect(find.text('2 punches'), findsOneWidget);
  });

  testWidgets('eliminar toma llama deleteTake y recarga', (tester) async {
    await _pump(tester);
    _core.result('library.deleteTake', {'removed': true});
    final before = _calls('library.project');
    await tester.tap(find.text('Eliminar').at(1));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Eliminar Toma 2 · Rítmica'));
    await _settle(tester);
    expect(_calls('library.deleteTake'), 1);
    final params = (_core.calls.firstWhere((c) => c.method == 'library.deleteTake').params! as Map);
    expect(params['takeId'], '00000000-0000-0000-0000-000000000004');
    expect(_calls('library.project'), greaterThan(before));
  });

  testWidgets('Abrir en Backing track con separación done', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Abrir en Backing track'));
    await tester.pump();
    expect(_c.read(shellRouteProvider), ShellRoute.backing);
    expect(_c.read(selectedProjectProvider), _id);
  });

  testWidgets('‹ Biblioteca cierra el detalle', (tester) async {
    await _pump(tester);
    expect(_c.read(libraryDetailProvider), _id);
    await tester.tap(find.text('Biblioteca'));
    await tester.pump();
    expect(_c.read(libraryDetailProvider), isNull);
  });
}
