import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferencia local de un solo valor de texto (la vista Temas/Artistas).
abstract class LibraryPrefs {
  Future<String?> get(String key);
  Future<void> set(String key, String value);
}

/// Clave de la vista persistida (como `@AppStorage("libraryGrouping")` en SwiftUI).
const String libraryGroupingKey = 'libraryGrouping';

/// Implementación real con `SharedPreferencesAsync`.
class SharedLibraryPrefs implements LibraryPrefs {
  SharedLibraryPrefs([SharedPreferencesAsync? prefs])
    : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;

  @override
  Future<String?> get(String key) => _prefs.getString(key);

  @override
  Future<void> set(String key, String value) => _prefs.setString(key, value);
}

/// Los tests la sustituyen por una en memoria.
final libraryPrefsProvider = Provider<LibraryPrefs>((ref) => SharedLibraryPrefs());
