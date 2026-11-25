import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/library/dialogs/clean_dialog.dart';
import 'package:toneforge/features/library/dialogs/duplicate_dialog.dart';
import 'package:toneforge/features/library/dialogs/trash_dialog.dart';
import 'package:toneforge/features/library/library_errors.dart';
import 'package:toneforge/features/library/library_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/l10n/app_localizations_es.dart';
import 'package:toneforge/shell/selected_project.dart';
import 'package:toneforge/shell/shell_providers.dart';
import 'package:toneforge/shell/shell_route.dart';
import 'package:toneforge/theme/fmt.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_sheet.dart';

import '../../support/harness.dart';
import 'library_store_test.dart' show project, setup;

const _id = '00000000-0000-0000-0000-000000000005';

Future<(ProviderContainer, MockCore)> _pump(
  WidgetTester tester,
  Future<void> Function(BuildContext, WidgetRef) onTap, {
  int stems = 2,
  int takes = 1,
  int videos = 0,
}) async {
  late ProviderContainer c;
  late MockCore core;
  await tester.runAsync(() async {
    final r = await setup(projects: [
      {...project(_id, 'Delta'), 'stemCount': stems, 'takeCount': takes},
    ]);
    c = r.$1;
    core = r.$2;
  });
  core.handle('library.project', (_) => {
        ...project(_id, 'Delta'),
        'stemCount': stems,
        'takeCount': takes,
        'stems': <Object>[],
        'parts': <Object>[],
        'videoCount': videos,
      });
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
        home: Consumer(
          builder: (ctx, ref, _) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onTap(ctx, ref),
            child: const SizedBox.expand(key: Key('go')),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('go')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return (c, core);
}

void main() {
  final l = AppLocalizationsEs();

  test('plurales del contenido', () {
    String t(int s, int k, int v) => trashContentsText(l, TrashContent(stems: s, takes: k, videos: v));
    expect(t(0, 0, 0), 'sus stems');
    expect(t(1, 1, 1), '1 stem, 1 toma, 1 vídeo');
    expect(t(5, 3, 2), '5 stems, 3 tomas, 2 vídeos');
    expect(t(0, 2, 0), 'sus stems, 2 tomas');
  });

  testWidgets('eliminar: tres botones e Intro mueve a la Papelera', (tester) async {
    bool? res;
    final (_, core) = await _pump(tester, (ctx, ref) async {
      res = await showTrashDialog(ctx, ref, projectId: _id, title: 'Delta');
    }, stems: 3, takes: 2, videos: 1);
    expect(find.text('¿Eliminar “Delta”?'), findsOneWidget);
    expect(find.textContaining('3 stems, 2 tomas, 1 vídeo'), findsOneWidget);
    expect(find.text('Mover a la Papelera'), findsOneWidget);
    expect(find.text('Eliminar del disco'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);
    core.handle('library.trash', (_) => {'removed': true});
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 300));
    expect(core.calls.where((x) => x.method == 'library.trash').length, 1);
    expect(res, isTrue);
  });

  testWidgets('eliminar: golden', (tester) async {
    await tester.runAsync(loadTfFonts);
    setTestSurface(tester, const Size(640, 420));
    await _pump(tester, (ctx, ref) async {
      await showTrashDialog(ctx, ref, projectId: _id, title: 'Delta');
    }, stems: 3, takes: 2, videos: 1);
    await tester.pump(const Duration(milliseconds: 300));
    final boundary = find.ancestor(of: find.byType(TfSheetScaffold), matching: find.byType(RepaintBoundary)).first;
    await expectLater(boundary, matchesGoldenFile('goldens/trash_dialog.png'));
  });

  testWidgets('eliminar: Esc cancela sin llamar', (tester) async {
    bool? res;
    final (_, core) = await _pump(tester, (ctx, ref) async {
      res = await showTrashDialog(ctx, ref, projectId: _id, title: 'Delta');
    });
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 300));
    expect(res, isFalse);
    expect(core.calls.where((x) => x.method.startsWith('library.trash') || x.method == 'library.delete'), isEmpty);
  });

  testWidgets('eliminar del disco llama library.delete', (tester) async {
    bool? res;
    final (_, core) = await _pump(tester, (ctx, ref) async {
      res = await showTrashDialog(ctx, ref, projectId: _id, title: 'Delta');
    });
    core.handle('library.delete', (_) => {'removed': true});
    await tester.tap(find.text('Eliminar del disco'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(core.calls.where((x) => x.method == 'library.delete').length, 1);
    expect(res, isTrue);
  });

  testWidgets('eliminar con error muestra el aviso y devuelve false', (tester) async {
    bool? res;
    final (_, core) = await _pump(tester, (ctx, ref) async {
      res = await showTrashDialog(ctx, ref, projectId: _id, title: 'Delta');
    });
    core.failWith('library.delete', const CoreError('unsafe-deletion', 'raw'));
    await tester.tap(find.text('Eliminar del disco'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(l.library_errDelete), findsOneWidget);
    expect(find.text(l.library_errUnsafeDeletion), findsOneWidget);
    await tester.tap(find.text('Aceptar'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(res, isFalse);
  });

  testWidgets('limpiar muestra los bytes y llama library.cleanup', (tester) async {
    late MockCore core;
    final done = <bool>[];
    final r = await _pump(tester, (ctx, ref) async {
      await showCleanDialog(ctx, ref, projectId: _id, title: 'Delta');
      done.add(true);
    }, stems: 0);
    core = r.$2;
    // library.cleanupInfo responde con el fixture; se compara con su propio valor.
    final info = await tester.runAsync(() => r.$1.read(libraryStoreProvider.notifier).cleanupInfo(id: _id));
    expect(find.text('Limpiar «Delta»'), findsOneWidget);
    expect(find.text('Limpiar ${TfFmt.bytes(info!, 'es')}'), findsOneWidget);
    core.handle('library.cleanup', (_) => {'cleaned': true, 'bytes': info});
    await tester.tap(find.text('Limpiar ${TfFmt.bytes(info, 'es')}'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(core.calls.where((x) => x.method == 'library.cleanup').length, 1);
    expect(done, [true]);
  });

  testWidgets('limpiar toda la biblioteca: título global y error', (tester) async {
    final (_, core) = await _pump(tester, (ctx, ref) => showCleanDialog(ctx, ref));
    expect(find.text('Limpiar toda la biblioteca'), findsOneWidget);
    core.failWith('library.cleanup', const CoreError('busy', 'raw'));
    await tester.tap(find.textContaining(RegExp('^Limpiar \\d')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(l.library_errBusy), findsOneWidget);
  });

  testWidgets('duplicado: «Abrir el existente» cambia a Biblioteca y selecciona', (tester) async {
    final (c, _) = await _pump(tester, (ctx, ref) => showDuplicateDialog(ctx, ref, _id));
    c.read(shellRouteProvider.notifier).select(ShellRoute.settings);
    expect(find.text(l.library_duplicateTitle), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(c.read(shellRouteProvider), ShellRoute.library);
    expect(c.read(selectedProjectProvider), _id);
  });

  test('coreErrorText: código conocido, desconocido y sin mensaje', () {
    expect(coreErrorText(l, const CoreError('busy', 'x')), l.library_errBusy);
    expect(coreErrorText(l, const CoreError('weird', 'Mensaje crudo')), 'Mensaje crudo');
    expect(coreErrorText(l, const CoreError('weird', ' ')), l.error_unknown);
  });
}
