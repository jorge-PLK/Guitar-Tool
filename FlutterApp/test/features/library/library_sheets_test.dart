import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/library.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/library/dialogs/trash_dialog.dart';
import 'package:toneforge/features/library/import_store.dart';
import 'package:toneforge/features/library/library_alerts_host.dart';
import 'package:toneforge/features/library/library_store.dart';
import 'package:toneforge/features/library/sheets/song_info_sheet.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/l10n/app_localizations_es.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_sheet.dart';

import '../../support/harness.dart';
import 'library_store_test.dart' show project, setup;

const _id = '00000000-0000-0000-0000-000000000005';
final _l = AppLocalizationsEs();
const _ms = Duration(milliseconds: 300);

Future<(ProviderContainer, MockCore)> _pump(WidgetTester tester, Widget Function(BuildContext) home) async {
  late ProviderContainer c;
  late MockCore core;
  await tester.runAsync(() async {
    await loadTfFonts();
    final r = await setup(projects: [project(_id, 'Delta')]);
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
        home: Builder(builder: home),
      ),
    ),
  );
  await tester.pump();
  return (c, core);
}

Widget _host(BuildContext _) => const LibraryAlertsHost(child: SizedBox.expand());

Widget _opener(BuildContext ctx) => GestureDetector(
  behavior: HitTestBehavior.opaque,
  onTap: () => showSongInfoSheet(ctx, ProjectSummary.fromJson(project(_id, 'Delta'))),
  child: const SizedBox.expand(),
);

Finder _sheetBoundary() =>
    find.ancestor(of: find.byType(TfSheetScaffold), matching: find.byType(RepaintBoundary)).first;

/// Deja terminar el fundido de la hoja antes de capturar.
Future<void> _settleSheet(WidgetTester tester) async {
  await tester.pump(_ms);
  await tester.pump(_ms);
}

int _calls(MockCore core, String m) => core.calls.where((x) => x.method == m).length;

void main() {
  testWidgets('host: duplicado abre la alerta y descarta', (tester) async {
    final (c, core) = await _pump(tester, _host);
    core.handle('import.file', (_) => {'id': _id, 'duplicate': true});
    await tester.runAsync(() => c.read(importStoreProvider.notifier).importPaths(['/x/a.wav']));
    await tester.pump(_ms);
    expect(find.text(_l.library_duplicateTitle), findsOneWidget);
    expect(c.read(importStoreProvider).duplicateOf, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(_ms);
    expect(find.text(_l.library_duplicateTitle), findsNothing);
  });

  testWidgets('host: aviso del núcleo se muestra y descarta', (tester) async {
    final (c, core) = await _pump(tester, _host);
    core.failWith('import.file', const CoreError('unsupported', 'Formato raro'));
    await tester.runAsync(() => c.read(importStoreProvider.notifier).importPaths(['/x/a.wav']));
    await tester.pump(_ms);
    expect(find.text('Formato raro'), findsOneWidget);
    expect(find.text(_l.library_noticeOk), findsOneWidget);
    expect(c.read(importStoreProvider).notice, isNull);
  });

  testWidgets('host: needsFolder abre la hoja de primer arranque, Esc no la cierra', (tester) async {
    final (c, core) = await _pump(tester, _host);
    core.failWith('library.list', const CoreError('no-projects-folder', 'x'));
    await tester.runAsync(() => c.read(libraryStoreProvider.notifier).refresh());
    await tester.pump(_ms);
    expect(find.text(_l.library_firstRunTitle), findsOneWidget);
    await _settleSheet(tester);
    await expectLater(_sheetBoundary(), matchesGoldenFile('goldens/first_run_sheet.png'));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(_ms);
    expect(find.text(_l.library_firstRunTitle), findsOneWidget);
    core.handle('host.pickProjectsFolder', (_) => {'path': '/tmp/tf', 'restartRequired': false});
    core.result('library.list', {'projects': <Object>[], 'skipped': <Object>[]});
    await tester.tap(find.text(_l.library_firstRunChoose));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(_ms);
    expect(_calls(core, 'host.pickProjectsFolder'), 1);
    expect(find.text(_l.library_firstRunTitle), findsNothing);
  });

  testWidgets('hoja de corrección: Guardar deshabilitado con título vacío', (tester) async {
    final (_, core) = await _pump(tester, _opener);
    await tester.tap(find.byType(GestureDetector).first);
    await tester.pump(_ms);
    expect(find.text(_l.library_editSheetTitle), findsOneWidget);
    await _settleSheet(tester);
    await expectLater(_sheetBoundary(), matchesGoldenFile('goldens/song_info_sheet.png'));
    final fields = find.byType(EditableText);
    await tester.enterText(fields.first, '   ');
    await tester.pump();
    await tester.tap(find.text(_l.library_save));
    await tester.pump(_ms);
    expect(_calls(core, 'library.rename'), 0);
  });

  testWidgets('hoja de corrección: artista vacío se envía ausente y cierra', (tester) async {
    final (_, core) = await _pump(tester, _opener);
    Json? sent;
    core.handle('library.rename', (p) {
      sent = p as Json;
      return {'id': _id, 'title': 'Nuevo', 'artist': null};
    });
    await tester.tap(find.byType(GestureDetector).first);
    await tester.pump(_ms);
    final fields = find.byType(EditableText);
    await tester.enterText(fields.first, 'Nuevo');
    await tester.enterText(fields.last, '');
    await tester.pump();
    await tester.tap(find.text(_l.library_save));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(_ms);
    expect(sent!['title'], 'Nuevo');
    expect(sent!.containsKey('artist') ? sent!['artist'] : null, isNull);
    expect(find.text(_l.library_editSheetTitle), findsNothing);
  });

  testWidgets('hoja de corrección: si falla no cierra y avisa', (tester) async {
    final (_, core) = await _pump(tester, _opener);
    core.failWith('library.rename', const CoreError('busy', 'raw'));
    await tester.tap(find.byType(GestureDetector).first);
    await tester.pump(_ms);
    await tester.tap(find.text(_l.library_save));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(_ms);
    expect(find.text(_l.library_errSave), findsOneWidget);
    expect(find.text(_l.library_errBusy), findsOneWidget);
    await tester.tap(find.text(_l.library_noticeOk));
    await tester.pump(_ms);
    expect(find.text(_l.library_editSheetTitle), findsOneWidget);
  });

  testWidgets('eliminar: error de la Papelera usa título y cuerpo específicos', (tester) async {
    final (_, core) = await _pump(
      tester,
      (ctx) => Consumer(
        builder: (c, ref, _) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => showTrashDialog(c, ref, projectId: _id, title: 'Delta'),
          child: const SizedBox.expand(),
        ),
      ),
    );
    core.failWith('library.trash', const CoreError('busy', 'raw'));
    await tester.tap(find.byType(GestureDetector).first);
    await tester.pump(_ms);
    await tester.tap(find.text(_l.library_trashToBinMac));
    await tester.pump(_ms);
    expect(find.text(_l.library_errTrashTitleMac), findsOneWidget);
    expect(find.text(_l.library_errTrashBody(_l.library_errBusy)), findsOneWidget);
  });
}
