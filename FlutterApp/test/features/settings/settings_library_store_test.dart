import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/library_storage.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/settings/settings_library_store.dart';

Future<(ProviderContainer, MockCore)> setup() async {
  final core = await MockCore.load((await DirectoryFixtureSource.find())!);
  final c = ProviderContainer(overrides: [coreClientProvider.overrideWithValue(core)]);
  addTearDown(c.dispose);
  c.listen(settingsLibraryStoreProvider, (_, _) {});
  return (c, core);
}

int count(MockCore core, String m) => core.calls.where((x) => x.method == m).length;

void main() {
  group('settings_library_store', () {
    test('carga inicial: carpeta y espacio', () async {
      final (c, core) = await setup();
      await pumpEventQueue();
      final s = c.read(settingsLibraryStoreProvider);
      expect(s.loaded, isTrue);
      expect(s.projectsFolder, isNull); // el fixture no tiene carpeta personalizada
      expect(s.usage, isNotNull);
      expect(count(core, 'settings.get'), 1);
      expect(count(core, 'library.usage'), 1);
    });

    test('library.changed recarga el espacio usado', () async {
      final (_, core) = await setup();
      await pumpEventQueue();
      core.emitFixture('library.changed');
      await pumpEventQueue();
      expect(count(core, 'library.usage'), 2);
    });

    test('chooseFolder cancelado devuelve null y no llama a relocate', () async {
      final (c, core) = await setup();
      core.result('host.chooseFolder', {'path': null});
      final path = await c.read(settingsLibraryStoreProvider.notifier).chooseFolder();
      expect(path, isNull);
      expect(count(core, 'host.chooseFolder'), 1);
      expect(count(core, 'host.pickProjectsFolder'), 0);
      expect(count(core, 'library.relocate'), 0);
    });

    test('chooseFolder devuelve la ruta elegida', () async {
      final (c, core) = await setup();
      core.result('host.chooseFolder', {'path': '/x/y'});
      expect(await c.read(settingsLibraryStoreProvider.notifier).chooseFolder(), '/x/y');
    });

    test('relocate move: progreso, botón deshabilitado y recarga al acabar', () async {
      final (c, core) = await setup();
      await pumpEventQueue();
      core.handle('library.relocate', (_) => {'path': '/nueva', 'mediaRemapped': true});
      final st = c.read(settingsLibraryStoreProvider.notifier);
      final fut = st.relocate('/nueva', RelocateMode.move);
      expect(c.read(settingsLibraryStoreProvider).relocating, isTrue);
      expect(c.read(settingsLibraryStoreProvider).showRelocateProgress, isTrue);
      await pumpEventQueue();
      expect(await fut, isNull);
      final p = core.calls.firstWhere((x) => x.method == 'library.relocate').params as Map;
      expect(p['mode'], 'move');
      expect(p['path'], '/nueva');
      expect(c.read(settingsLibraryStoreProvider).relocating, isFalse);
      expect(count(core, 'settings.get'), 2);
      expect(count(core, 'library.usage'), 2);
    });

    test('library.relocateProgress actualiza la fracción solo mientras se traslada', () async {
      final (c, core) = await setup();
      await pumpEventQueue();
      core.emitFixture('library.relocateProgress');
      await pumpEventQueue();
      expect(c.read(settingsLibraryStoreProvider).relocateFraction, 0);
      core.handle('library.relocate', (_) => {'path': '/n', 'mediaRemapped': false});
      final fut = c.read(settingsLibraryStoreProvider.notifier).relocate('/n', RelocateMode.move);
      core.emitFixture('library.relocateProgress');
      await pumpEventQueue();
      await fut;
      expect(c.read(settingsLibraryStoreProvider).relocating, isFalse);
    });

    test('relocate point: sin barra de progreso', () async {
      final (c, core) = await setup();
      await pumpEventQueue();
      core.result('library.relocate', {'path': '/p', 'mediaRemapped': false});
      final fut = c.read(settingsLibraryStoreProvider.notifier).relocate('/p', RelocateMode.point);
      expect(c.read(settingsLibraryStoreProvider).showRelocateProgress, isFalse);
      expect(c.read(settingsLibraryStoreProvider).relocating, isTrue);
      await fut;
      expect((core.calls.firstWhere((x) => x.method == 'library.relocate').params as Map)['mode'], 'point');
    });

    test('work-in-progress queda como código y rehabilita el botón', () async {
      final (c, core) = await setup();
      await pumpEventQueue();
      core.failWithFixture('library.relocate');
      final e = await c.read(settingsLibraryStoreProvider.notifier).relocate('/n', RelocateMode.move);
      expect(e?.code, 'work-in-progress');
      final s = c.read(settingsLibraryStoreProvider);
      expect(s.workInProgress, isTrue);
      expect(s.relocating, isFalse);
      c.read(settingsLibraryStoreProvider.notifier).dismissError();
      expect(c.read(settingsLibraryStoreProvider).error, isNull);
    });

    test('error de library.usage queda en error', () async {
      final core = await MockCore.load((await DirectoryFixtureSource.find())!);
      core.failWith('library.usage', const CoreError('internal', 'x'));
      final c = ProviderContainer(overrides: [coreClientProvider.overrideWithValue(core)]);
      addTearDown(c.dispose);
      c.listen(settingsLibraryStoreProvider, (_, _) {});
      await pumpEventQueue();
      expect(c.read(settingsLibraryStoreProvider).error?.code, 'internal');
      expect(c.read(settingsLibraryStoreProvider).loaded, isTrue);
    });
  });
}
