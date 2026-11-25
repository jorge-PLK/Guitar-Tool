import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/library.dart';
import 'package:toneforge/core/core_providers.dart';

/// Orden de los selectores de SwiftUI (`AppModel.swift:520`): `createdAt` descendente, el más reciente primero.
/// `library.list` del núcleo llega ordenado por título; aquí se reordena. Empate o fecha no parseable:
/// se conserva el orden de entrada (fecha no parseable = la más antigua).
List<ProjectSummary> sortByCreatedAtDesc(List<ProjectSummary> projects) {
  int key(ProjectSummary p) => p.createdAtDate?.millisecondsSinceEpoch ?? 0;
  final indexed = [for (var i = 0; i < projects.length; i++) (i, projects[i])];
  indexed.sort((a, b) {
    final byDate = key(b.$2).compareTo(key(a.$2));
    return byDate != 0 ? byDate : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

/// Temas con la separación terminada (`library.list` filtrado por `separationState == done`), en orden de SwiftUI
/// (ver [sortByCreatedAtDesc]). Backing usa el mismo orden en SwiftUI (`BackingView.swift:34`, `model.entries`).
/// `autoDispose`: cada vez que se muestra el selector se vuelve a leer. Lo usan Backing y Tablatura.
/// Un error del núcleo deja el `AsyncError` (sin reintento automático): quien lo pinta lo trata como lista vacía.
final separatedProjectsProvider = FutureProvider.autoDispose<List<ProjectSummary>>(
  (ref) async {
    final core = ref.watch(coreClientProvider);
    final r = await core.call('library.list', const <String, Object?>{}, LibraryListResult.fromJson);
    return sortByCreatedAtDesc([
      for (final p in r.projects)
        if (p.separationState == SeparationState.done) p,
    ]);
  },
  retry: (_, _) => null,
);
