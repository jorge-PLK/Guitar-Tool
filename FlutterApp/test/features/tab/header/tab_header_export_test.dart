import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/tab/tab_header.dart';
import 'package:toneforge/features/tab/tab_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';

import '../../../support/harness.dart';
import '../tab_test_support.dart';

class _Rig {
  _Rig(this.core, this.container, this.dialogs);
  final MockCore core;
  final ProviderContainer container;
  final List<String> dialogs;
  List<String> get methods => [for (final c in core.calls) c.method];
}

Future<_Rig> _boot(
  WidgetTester tester, {
  String? savePath = '/tmp/x.gp',
  void Function(MockCore core)? prepare,
}) async {
  setTestSurface(tester, const Size(1100, 200));
  final core = (await tester.runAsync(loadCore))!;
  prepare?.call(core);
  final dialogs = <String>[];
  final container = ProviderContainer(overrides: [
    coreClientProvider.overrideWithValue(core),
    tabStudyProjectProvider.overrideWith((ref) => ref.watch(studyProjectProbe)),
    tabExportDataProvider.overrideWith((ref) => () async => 'AAAA'),
    tabSavePathProvider.overrideWith((ref) => (name) async {
          dialogs.add(name);
          return savePath;
        }),
  ]);
  addTearDown(container.dispose);
  container.listen(tabStoreProvider, (_, _) {});
  container.read(studyProjectProbe.notifier).set(projectId);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: tfNavApp(Localizations(
      locale: const Locale('es'),
      delegates: const [AppLocalizations.delegate, DefaultWidgetsLocalizations.delegate],
      child: const DefaultTextStyle(style: TextStyle(), child: TabHeader()),
    )),
  ));
  await tester.runAsync(settle);
  await tester.pump();
  return _Rig(core, container, dialogs);
}

Future<void> _export(WidgetTester tester) async {
  await tester.tap(find.text('Exportar a Guitar Pro'), warnIfMissed: false);
  await tester.runAsync(settle);
  await tester.pump();
}

void main() {
  setUpAll(() async {
    await findFixtures();
    await loadTfFonts();
  });

  testWidgets('nombre sugerido, diálogo y tab.export con la ruta elegida', (tester) async {
    final r = await _boot(tester);
    await _export(tester);
    expect(r.methods, containsAllInOrder(['tab.exportName', 'tab.export']));
    expect(r.dialogs, [r.container.read(tabStoreProvider).exportName]);
    final p = r.core.calls.lastWhere((c) => c.method == 'tab.export').params! as Map<String, Object?>;
    expect(p['path'], '/tmp/x.gp');
    expect(p['data'], 'AAAA');
  });

  testWidgets('diálogo cancelado: no se llama a tab.export', (tester) async {
    final r = await _boot(tester, savePath: null);
    await _export(tester);
    expect(r.dialogs, hasLength(1));
    expect(r.methods, isNot(contains('tab.export')));
    expect(r.container.read(tabStoreProvider).flash, isNull);
  });

  testWidgets('saved:true: sin aviso propio (el núcleo manda el flash)', (tester) async {
    final r = await _boot(tester);
    await _export(tester);
    expect(r.container.read(tabStoreProvider).flash, isNull);
    expect(r.container.read(tabStoreProvider).error, isNull);
  });

  testWidgets('saved:false: se ignora sin aviso ni error', (tester) async {
    final r = await _boot(tester, prepare: (c) => c.result('tab.export', {'saved': false}));
    await _export(tester);
    expect(r.methods, contains('tab.export'));
    expect(r.container.read(tabStoreProvider).flash, isNull);
    expect(r.container.read(tabStoreProvider).error, isNull);
  });

  testWidgets('fallo del núcleo: aviso «No se pudo exportar»', (tester) async {
    final r = await _boot(tester,
        prepare: (c) => c.failWith('tab.export', const CoreError('internal', 'disco lleno')));
    await _export(tester);
    expect(r.container.read(tabStoreProvider).flash, 'No se pudo exportar: disco lleno');
    await tester.pump(const Duration(seconds: 4));
  });
}
