/// Argumentos de arranque (arquitectura.md, «Arranque, capturas y desarrollo»).
/// Mismo formato que `AppCore.LaunchOptions.parse`: `--flag valor` o `--flag=valor`; lo desconocido se ignora.
/// Solo Dart (no van al núcleo): `--mock`, `--locale`, `--core-lib`.
class LaunchOptions {
  const LaunchOptions({
    this.projectsFolder,
    this.supportDir,
    this.screen,
    this.project,
    this.snapshot,
    this.snapshotDelay,
    this.window,
    this.audio,
    this.camera,
    this.mock = false,
    this.locale,
    this.coreLib,
  });

  final String? projectsFolder;
  final String? supportDir;
  final String? screen;
  final String? project;

  /// Ruta del PNG de captura (`--snapshot`).
  final String? snapshot;

  /// Segundos antes de la captura; nulo = el valor por defecto del núcleo.
  final double? snapshotDelay;

  /// `--window 1280x800`.
  final ({int width, int height})? window;
  final String? audio;
  final String? camera;
  final bool mock;

  /// `es` o `en`.
  final String? locale;

  /// Ruta de la biblioteca del núcleo (Mac: si falta, símbolos del proceso).
  final String? coreLib;

  static const _valueFlags = {
    '--projects-folder', '--support-dir', '--screen', '--project', '--snapshot',
    '--snapshot-delay', '--window', '--audio', '--camera', '--locale',
    '--core-lib',
  };

  factory LaunchOptions.parse(List<String> args) {
    final v = <String, String>{};
    var mock = false;
    var i = 0;
    while (i < args.length) {
      final a = args[i];
      if (!a.startsWith('--')) {
        i++;
        continue;
      }
      final eq = a.indexOf('=');
      final key = eq < 0 ? a : a.substring(0, eq);
      if (key == '--mock') {
        mock = true;
        i++;
      } else if (_valueFlags.contains(key)) {
        final String? value;
        var step = 1;
        if (eq >= 0) {
          value = a.substring(eq + 1);
        } else if (i + 1 < args.length) {
          value = args[i + 1];
          step = 2;
        } else {
          value = null;
        }
        if (value != null && value.isNotEmpty) v[key] = value;
        i += step;
      } else {
        i++;
      }
    }

    final delay = double.tryParse(v['--snapshot-delay'] ?? '');
    final loc = v['--locale']?.toLowerCase();
    return LaunchOptions(
      projectsFolder: v['--projects-folder'],
      supportDir: v['--support-dir'],
      screen: v['--screen'],
      project: v['--project'],
      snapshot: v['--snapshot'],
      snapshotDelay: (delay != null && delay >= 0) ? delay : null,
      window: _parseWindow(v['--window']),
      audio: v['--audio']?.toLowerCase(),
      camera: v['--camera']?.toLowerCase(),
      mock: mock,
      locale: (loc == 'es' || loc == 'en') ? loc : null,
      coreLib: v['--core-lib'],
    );
  }

  static ({int width, int height})? _parseWindow(String? s) {
    final parts = s?.toLowerCase().split('x');
    if (parts == null || parts.length != 2) return null;
    final w = int.tryParse(parts[0]);
    final h = int.tryParse(parts[1]);
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return (width: w, height: h);
  }

  /// Lo que se pasa al núcleo (`{"args": [...]}`), sin `--mock`, `--locale` ni `--core-lib`.
  List<String> toCoreArgs() => [
        if (projectsFolder != null) ...['--projects-folder', projectsFolder!],
        if (supportDir != null) ...['--support-dir', supportDir!],
        if (screen != null) ...['--screen', screen!],
        if (project != null) ...['--project', project!],
        if (snapshot != null) ...['--snapshot', snapshot!],
        if (snapshotDelay != null) ...['--snapshot-delay', '$snapshotDelay'],
        if (window != null) ...['--window', '${window!.width}x${window!.height}'],
        if (audio != null) ...['--audio', audio!],
        if (camera != null) ...['--camera', camera!],
      ];
}
