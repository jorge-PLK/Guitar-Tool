import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toneforge/features/backing/study_store.dart';

/// Clave de la preferencia «acordes expandidos» de un tema.
String chordsExpandedPrefKey(String projectId) => 'backing.chordsExpanded.$projectId';

/// Preferencia local (solo interfaz) del plegado de la rejilla de acordes, por tema.
abstract class ChordsExpandedPrefStore {
  Future<bool?> read(String projectId);
  Future<void> write(String projectId, bool expanded);
}

class SharedChordsExpandedPrefStore implements ChordsExpandedPrefStore {
  SharedChordsExpandedPrefStore([SharedPreferencesAsync? prefs]) : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;

  @override
  Future<bool?> read(String projectId) => _prefs.getBool(chordsExpandedPrefKey(projectId));

  @override
  Future<void> write(String projectId, bool expanded) =>
      _prefs.setBool(chordsExpandedPrefKey(projectId), expanded);
}

/// Los tests la sustituyen por una en memoria.
final chordsExpandedPrefStoreProvider =
    Provider<ChordsExpandedPrefStore>((ref) => SharedChordsExpandedPrefStore());

/// `true` = rejilla expandida del tema abierto. Plegado por defecto; se recuerda por tema.
final chordsExpandedProvider = NotifierProvider<ChordsExpandedNotifier, bool>(ChordsExpandedNotifier.new);

class ChordsExpandedNotifier extends Notifier<bool> {
  String? _id;
  bool _touched = false;

  @override
  bool build() {
    _id = ref.watch(studyStoreProvider.select((s) => s.openProjectId));
    _touched = false;
    if (_id != null) _load(_id!);
    return false;
  }

  Future<void> _load(String id) async {
    bool? saved;
    try {
      saved = await ref.read(chordsExpandedPrefStoreProvider).read(id);
    } catch (_) {
      return;
    }
    if (!ref.mounted || _touched || _id != id || saved == null) return;
    state = saved;
  }

  /// Aplica al momento y guarda.
  Future<void> set(bool expanded) async {
    _touched = true;
    state = expanded;
    final id = _id;
    if (id == null) return;
    try {
      await ref.read(chordsExpandedPrefStoreProvider).write(id, expanded);
    } catch (_) {
      // Preferencia de interfaz: si no se puede guardar, vale la sesión.
    }
  }

  Future<void> toggle() => set(!state);
}
