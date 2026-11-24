import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/core/core_providers.dart';

/// Resuelve `--project` a id (UUID). AppCore no lo resuelve: `app.info.launch.project` devuelve el texto tal cual y
/// SwiftUI lo compara con `folderName` o `title` (AppModel.swift:445). Aquí se hace igual sobre `library.list`.
/// Sin `--project` no llama al núcleo y da `null`.
final launchProjectIdProvider = FutureProvider<String?>((ref) async {
  final wanted = ref.watch(launchOptionsProvider).project;
  if (wanted == null) return null;
  final core = ref.watch(coreClientProvider);
  final List<Map<String, Object?>> projects;
  try {
    projects = await core.call<List<Map<String, Object?>>>(
      'library.list',
      const <String, Object?>{},
      (j) => ((j['projects'] as List?) ?? const <Object?>[]).cast<Map<String, Object?>>(),
    );
  } catch (_) {
    // Sembrar es best-effort (y Riverpod 3 reintentaría un error sin fin): sin lista, sin proyecto inicial.
    return null;
  }
  for (final p in projects) {
    if (p['id'] == wanted || p['folderName'] == wanted || p['title'] == wanted) return p['id'] as String?;
  }
  return null;
});

/// Id del proyecto elegido (UUID) o `null`. Lo escribe Biblioteca; Backing, Tablatura y Grabar lo leen.
/// Se siembra desde `--project` (vía [launchProjectIdProvider]) salvo que el usuario ya haya elegido.
final selectedProjectProvider = NotifierProvider<SelectedProjectNotifier, String?>(SelectedProjectNotifier.new);

class SelectedProjectNotifier extends Notifier<String?> {
  bool _touched = false;

  @override
  String? build() {
    ref.listen<AsyncValue<String?>>(launchProjectIdProvider, (_, next) {
      final id = next.value;
      if (id != null && !_touched) state = id;
    }, fireImmediately: true);
    return null;
  }

  void select(String? id) {
    _touched = true;
    state = id;
  }
}
