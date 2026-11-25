import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/library.dart';
import 'package:toneforge/core/core_providers.dart';

/// Proyectos de la biblioteca (`library.list`) para el selector de Grabar y para la cabecera
/// (artista, estado de separación). Se recarga cada vez que Grabar se abre.
// TODO(ola3): pasar al store de biblioteca de la ola 1 al unir.
final recordTopicsProvider = FutureProvider.autoDispose<List<ProjectSummary>>((ref) async {
  final core = ref.watch(coreClientProvider);
  try {
    final r = await core.call('library.list', const <String, Object?>{}, LibraryListResult.fromJson);
    return r.projects;
  } catch (_) {
    // Sin lista, el selector queda vacío (y Riverpod 3 reintentaría un error sin fin).
    return const <ProjectSummary>[];
  }
});
