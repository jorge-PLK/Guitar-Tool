import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/tools.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/settings/settings_tools_store.dart';

Future<(ProviderContainer, MockCore)> setup() async {
  final core = await MockCore.load((await DirectoryFixtureSource.find())!);
  final c = ProviderContainer(overrides: [coreClientProvider.overrideWithValue(core)]);
  addTearDown(c.dispose);
  c.listen(settingsToolsStoreProvider, (_, _) {});
  return (c, core);
}

int infoCalls(MockCore core) => core.calls.where((x) => x.method == 'tools.info').length;

void main() {
  group('settings_tools_store', () {
    test('comprobando hasta tener tools.info', () async {
      final (c, _) = await setup();
      expect(c.read(settingsToolsStoreProvider).info, isNull);
      await pumpEventQueue();
      final s = c.read(settingsToolsStoreProvider);
      expect(s.info?.ytDlpOrigin, YtDlpOrigin.embedded);
      expect(s.canRevert, isFalse);
    });

    test('updateYtDlp ok: indeterminado, resultado y recarga de info', () async {
      final (c, core) = await setup();
      await pumpEventQueue();
      core.handle('tools.updateYtDlp', (_) => {'version': '2026.11.1', 'origin': 'updated', 'alreadyLatest': false});
      core.handle('tools.info', (_) => {'ytDlpVersion': '2026.11.1', 'ytDlpOrigin': 'updated'});
      final fut = c.read(settingsToolsStoreProvider.notifier).updateYtDlp();
      expect(c.read(settingsToolsStoreProvider).updating, isTrue);
      await fut;
      final s = c.read(settingsToolsStoreProvider);
      expect(s.status, YtDlpUpdateStatus.done);
      expect(s.updateResult?.alreadyLatest, isFalse);
      expect(s.info?.ytDlpOrigin, YtDlpOrigin.updated);
      expect(s.canRevert, isTrue);
      expect(infoCalls(core), 2);
    });

    test('updateYtDlp alreadyLatest', () async {
      final (c, core) = await setup();
      await pumpEventQueue();
      core.handle('tools.updateYtDlp', (_) => {'version': '2026.10.26', 'origin': 'embedded', 'alreadyLatest': true});
      await c.read(settingsToolsStoreProvider.notifier).updateYtDlp();
      final s = c.read(settingsToolsStoreProvider);
      expect(s.status, YtDlpUpdateStatus.done);
      expect(s.updateResult?.alreadyLatest, isTrue);
    });

    test('updateYtDlp con error: failed y recarga info igualmente', () async {
      final (c, core) = await setup();
      await pumpEventQueue();
      core.failWith('tools.updateYtDlp', const CoreError('internal', 'Sin red'));
      await c.read(settingsToolsStoreProvider.notifier).updateYtDlp();
      final s = c.read(settingsToolsStoreProvider);
      expect(s.status, YtDlpUpdateStatus.failed);
      expect(s.error?.message, 'Sin red');
      expect(infoCalls(core), 2);
    });

    test('revertYtDlp llama y recarga info', () async {
      final (c, core) = await setup();
      await pumpEventQueue();
      expect(await c.read(settingsToolsStoreProvider.notifier).revertYtDlp(), isNull);
      expect(core.calls.any((x) => x.method == 'tools.revertYtDlp'), isTrue);
      expect(infoCalls(core), 2);
      expect(c.read(settingsToolsStoreProvider).status, YtDlpUpdateStatus.idle);
    });

    test('revertYtDlp con error', () async {
      final (c, core) = await setup();
      await pumpEventQueue();
      core.failWith('tools.revertYtDlp', const CoreError('internal', 'x'));
      expect((await c.read(settingsToolsStoreProvider.notifier).revertYtDlp())?.code, 'internal');
      expect(c.read(settingsToolsStoreProvider).status, YtDlpUpdateStatus.failed);
    });
  });
}
