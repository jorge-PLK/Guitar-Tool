import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/models.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/settings/settings_models_store.dart';

const id = 'bs-roformer-sw';

Future<(ProviderContainer, MockCore)> setup({String? state}) async {
  final core = await MockCore.load((await DirectoryFixtureSource.find())!, state: state);
  final c = ProviderContainer(overrides: [coreClientProvider.overrideWithValue(core)]);
  addTearDown(c.dispose);
  c.listen(settingsModelsStoreProvider, (_, _) {});
  await pumpEventQueue();
  return (c, core);
}

void main() {
  group('settings_models_store', () {
    test('models.list al entrar', () async {
      final (c, _) = await setup();
      final s = c.read(settingsModelsStoreProvider);
      expect(s.loaded, isTrue);
      expect(s.entry(id)?.state, ModelState.notInstalled);
    });

    test('estado installed con tamaño', () async {
      final (c, _) = await setup(state: 'installed');
      final m = c.read(settingsModelsStoreProvider).entry(id)!;
      expect(m.state, ModelState.installed);
      expect(m.bytes, isNotNull);
    });

    test('download devuelve started, y false si ya había descarga', () async {
      final (c, core) = await setup();
      core.result('models.download', {'started': true});
      final st = c.read(settingsModelsStoreProvider.notifier);
      expect(await st.download(id), isTrue);
      expect((core.calls.firstWhere((x) => x.method == 'models.download').params as Map)['id'], id);
      core.result('models.download', {'started': false});
      expect(await st.download(id), isFalse);
    });

    test('models.progress marca la descarga y guarda la fracción', () async {
      final (c, core) = await setup();
      core.emitFixture('models.progress');
      await pumpEventQueue();
      final m = c.read(settingsModelsStoreProvider).entry(id)!;
      expect(m.state, ModelState.downloading);
      expect(m.fraction, 0.25);
    });

    test('models.changed ok sustituye la lista', () async {
      final (c, core) = await setup();
      core.emitFixture('models.changed.ok');
      await pumpEventQueue();
      final s = c.read(settingsModelsStoreProvider);
      expect(s.failure, isNull);
      expect(s.models, isNotEmpty);
    });

    test('models.changed con model-failed deja el fallo y el mensaje en la fila', () async {
      final (c, core) = await setup();
      core.emitFixture('models.changed');
      await pumpEventQueue();
      final s = c.read(settingsModelsStoreProvider);
      expect(s.failure?.code, 'model-failed');
      expect(s.entry(id)?.state, ModelState.failed);
      expect(s.entry(id)?.message, s.failure?.message);
    });

    test('delete actualiza la lista; busy queda en error', () async {
      final (c, core) = await setup(state: 'installed');
      core.result('models.delete', {'models': <Object?>[], 'modelsBytes': 0});
      final st = c.read(settingsModelsStoreProvider.notifier);
      expect(await st.delete(id), isNull);
      expect(c.read(settingsModelsStoreProvider).models, isEmpty);
      core.failWith('models.delete', const CoreError('busy', 'Ocupado'));
      expect((await st.delete(id))?.code, 'busy');
      expect(c.read(settingsModelsStoreProvider).error?.code, 'busy');
      st.dismissError();
      expect(c.read(settingsModelsStoreProvider).error, isNull);
    });
  });
}
