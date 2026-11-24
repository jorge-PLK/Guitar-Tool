import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/core_providers.dart';

/// Idioma elegido: el del sistema o uno fijo.
enum LocaleChoice { system, es, en }

/// Clave propia de la preferencia de idioma.
const String localePrefKey = 'tf.locale';

/// Preferencia local del idioma (código `es`/`en`; ausente = sistema).
abstract class LocalePrefStore {
  Future<LocaleChoice?> read();
  Future<void> write(LocaleChoice choice);
}

/// Implementación real con `SharedPreferencesAsync`.
class SharedLocalePrefStore implements LocalePrefStore {
  SharedLocalePrefStore([SharedPreferencesAsync? prefs])
    : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;

  @override
  Future<LocaleChoice?> read() async {
    final v = await _prefs.getString(localePrefKey);
    for (final c in LocaleChoice.values) {
      if (c.name == v) return c;
    }
    return null;
  }

  @override
  Future<void> write(LocaleChoice choice) => _prefs.setString(localePrefKey, choice.name);
}

/// Los tests la sustituyen por una en memoria.
final localePrefStoreProvider = Provider<LocalePrefStore>((ref) => SharedLocalePrefStore());

/// Preferencia leída en `main` antes de `runApp` (evita un primer fotograma en
/// el idioma del sistema). Null = no precargada: el notifier la lee él mismo.
final preloadedLocaleChoiceProvider = Provider<LocaleChoice?>((ref) => null);

/// Lee la preferencia guardada sin lanzar (null si no hay o no se puede leer).
Future<LocaleChoice?> readSavedLocaleChoice([LocalePrefStore? store]) async {
  try {
    return await (store ?? SharedLocalePrefStore()).read();
  } catch (_) {
    return null;
  }
}

/// Idioma activo. `Notifier` síncrono (no `AsyncNotifier`) para que la raíz
/// siempre tenga un valor: arranca con `--locale` (sesión, no se guarda), con
/// lo precargado en `main`, o con `system` y sustituye por lo guardado al cargar.
class LocaleChoiceNotifier extends Notifier<LocaleChoice> {
  bool _touched = false;

  @override
  LocaleChoice build() {
    final forced = ref.watch(launchOptionsProvider).locale;
    if (forced != null) {
      return forced == 'en' ? LocaleChoice.en : LocaleChoice.es;
    }
    final preloaded = ref.watch(preloadedLocaleChoiceProvider);
    if (preloaded != null) return preloaded;
    _touched = false;
    _load();
    return LocaleChoice.system;
  }

  Future<void> _load() async {
    LocaleChoice? saved;
    try {
      saved = await ref.read(localePrefStoreProvider).read();
    } catch (_) {
      return; // sin almacén legible: se queda en `system`
    }
    if (!ref.mounted || _touched || saved == null) return;
    state = saved;
  }

  /// Aplica al momento y guarda.
  Future<void> set(LocaleChoice choice) async {
    _touched = true;
    state = choice;
    await ref.read(localePrefStoreProvider).write(choice);
  }
}

final localeChoiceProvider = NotifierProvider<LocaleChoiceNotifier, LocaleChoice>(
  LocaleChoiceNotifier.new,
);
