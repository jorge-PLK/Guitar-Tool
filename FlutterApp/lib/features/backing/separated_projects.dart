import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/library.dart';
import 'package:toneforge/core/core_providers.dart';

/// Temas con la separación terminada (`library.list` filtrado por `separationState == done`).
/// `autoDispose`: cada vez que se muestra el selector se vuelve a leer. Lo usan Backing y Tablatura.
/// Un error del núcleo deja el `AsyncError` (sin reintento automático): quien lo pinta lo trata como lista vacía.
final separatedProjectsProvider = FutureProvider.autoDispose<List<ProjectSummary>>(
  (ref) async {
    final core = ref.watch(coreClientProvider);
    final r = await core.call('library.list', const <String, Object?>{}, LibraryListResult.fromJson);
    return [
      for (final p in r.projects)
        if (p.separationState == SeparationState.done) p,
    ];
  },
  retry: (_, _) => null,
);
