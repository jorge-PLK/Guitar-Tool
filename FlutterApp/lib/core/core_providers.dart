import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core_client.dart';
import 'launch_options.dart';
import 'mock_core.dart';

/// Argumentos de arranque. `main` lo sobrescribe con `LaunchOptions.parse(args)`.
final launchOptionsProvider = Provider<LaunchOptions>((ref) => const LaunchOptions());

/// Origen de fixtures de `--mock`: assets si están empaquetados; si no, `Contract/fixtures` del repo.
Future<FixtureSource> _findFixtures() async {
  const assets = AssetFixtureSource();
  try {
    if ((await assets.list()).isNotEmpty) return assets;
  } catch (_) {
    // sin manifiesto o sin assets: probamos el repo
  }
  final dir = await DirectoryFixtureSource.find();
  if (dir == null) throw StateError('No se encuentran los fixtures de Contract/fixtures.');
  return dir;
}

/// Único cliente del núcleo: `MockCore` con `--mock`, el núcleo real por FFI si no.
/// Los tests lo sobrescriben con un `MockCore`.
final coreClientProvider = Provider<CoreClient>((ref) {
  final o = ref.watch(launchOptionsProvider);
  if (o.mock) return MockCore.lazy(_findFixtures, state: o.state);
  final client = createFfiCoreClient(o);
  ref.onDispose(() => client.shutdown());
  return client;
});
