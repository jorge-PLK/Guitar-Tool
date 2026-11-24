/// Tabla única de límites por método (arquitectura.md, regla 3). Nunca se pone un límite en el sitio de la llamada.
/// Valor nulo = sin límite (diálogos del usuario: el diálogo es de Dart y siempre termina).
class CallTimeouts {
  const CallTimeouts({this.overrides = const {}});

  /// Para tests: sustituye entradas de la tabla (nulo = sin límite).
  final Map<String, Duration?> overrides;

  static const defaultTimeout = Duration(seconds: 15);

  /// Métodos exactos. Valores de `WinApp/Web/bridge.js`.
  static const Map<String, Duration?> byMethod = {
    'link.classify': Duration(seconds: 3),
    'link.search': Duration(seconds: 30),
    // Hoja de lista (playlist.search): 30 s. El `link.resolve` de una lista (300 s) no se distingue por método.
    'playlist.search': Duration(seconds: 30),
    'audio.calibrate': Duration(seconds: 60),
    'link.resolve': Duration(seconds: 120),
    'link.addManual': Duration(seconds: 120),
    'tools.updateYtDlp': Duration(seconds: 200),
    'tab.export': Duration(minutes: 10),
    'import.file': Duration(minutes: 60),
    'library.relocate': Duration(minutes: 60),
    'host.pickAudioFile': null,
    'host.pickAudioFiles': null,
    'host.chooseFolder': null,
    'host.pickProjectsFolder': null,
  };

  /// Prefijos (hoja de Songsterr: `tab.songsterr.*` 10 s). Se mira después de los métodos exactos.
  static const Map<String, Duration?> byPrefix = {
    'tab.songsterr.': Duration(seconds: 10),
  };

  /// Límite de [method]; nulo = sin límite.
  Duration? of(String method) {
    if (overrides.containsKey(method)) return overrides[method];
    if (byMethod.containsKey(method)) return byMethod[method];
    for (final e in byPrefix.entries) {
      if (method.startsWith(e.key)) return e.value;
    }
    return defaultTimeout;
  }
}
