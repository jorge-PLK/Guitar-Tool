import 'package:toneforge/contract/montage.dart';
import 'package:toneforge/core/core_client.dart' show CoreError;

const Object _keep = Object();

/// Fase de la pantalla de Montaje.
enum MontageStatus {
  /// Sin tema elegido (muestra el selector).
  noSong,

  /// `montage.open` en curso.
  loading,

  /// Hay `snapshot`.
  ready,

  /// `montage.open` falló (el tema no se pudo abrir).
  error,
}

/// `cancelled` se muestra como `idle` (desvío MO1).
MontageExportEvent normalizeExport(MontageExportEvent e) =>
    e.phase == MontageExportPhase.cancelled ? const MontageExportEvent(phase: MontageExportPhase.idle, progress: 0) : e;

/// Estado de Montaje: refleja `montage.state`, `montage.export` y `montage.framing`. Inmutable.
/// La posición (30 Hz) NO está aquí: va en `montagePositionProvider` (MO6).
class MontageState {
  const MontageState({
    this.projectId,
    this.snapshot,
    this.loading = false,
    this.loadError,
    this.actionError,
    this.exportLive,
    this.framingLive = const <String, MontageFramingEvent>{},
  });

  /// Tema abierto o en apertura.
  final String? projectId;

  /// Último `MontageSnapshot` (respuesta de un método o evento `montage.state`).
  final MontageSnapshot? snapshot;
  final bool loading;

  /// Fallo de `montage.open`.
  final CoreError? loadError;

  /// Último error de una acción (no `not-open`); se limpia con la siguiente acción correcta.
  final CoreError? actionError;

  /// Último `montage.export` recibido desde el último snapshot (sin normalizar); manda sobre `snapshot.exportStatus`.
  final MontageExportEvent? exportLive;

  /// Último `montage.framing` por toma desde el último snapshot; manda sobre `snapshot.framing`.
  final Map<String, MontageFramingEvent> framingLive;

  MontageStatus get status {
    if (loading) return MontageStatus.loading;
    if (loadError != null && snapshot == null) return MontageStatus.error;
    if (snapshot != null) return MontageStatus.ready;
    return MontageStatus.noSong;
  }

  /// Exportación efectiva con `cancelled` -> `idle` (MO1).
  MontageExportEvent get export {
    final e = exportLive ?? snapshot?.exportStatus;
    return e == null ? const MontageExportEvent(phase: MontageExportPhase.idle, progress: 0) : normalizeExport(e);
  }

  bool get exportRunning => export.phase == MontageExportPhase.running;

  /// Estado de análisis de una toma (evento vivo, si no el del snapshot); `null` si no hay encuadre para ella.
  MontageFramingStatus? framingStatus(String takeId) {
    final live = framingLive[takeId];
    if (live != null) return live.status;
    for (final f in snapshot?.framing ?? const <MontageFramingInfo>[]) {
      if (f.takeId == takeId) return f.status;
    }
    return null;
  }

  /// Muestras, detecciones y error del análisis de una toma (evento vivo, si no snapshot).
  ({int? samples, int? detected, String? error}) framingDetails(String takeId) {
    final live = framingLive[takeId];
    if (live != null) return (samples: live.samples, detected: live.detected, error: live.error);
    for (final f in snapshot?.framing ?? const <MontageFramingInfo>[]) {
      if (f.takeId == takeId) return (samples: f.samples, detected: f.detected, error: f.error);
    }
    return (samples: null, detected: null, error: null);
  }

  /// Alguna toma en `analyzing`: la pantalla deshabilita «Exportar».
  bool get isAnalyzing {
    final s = snapshot;
    if (s == null) return false;
    // Sin eventos vivos manda el flag del núcleo; con ellos, el estado por toma.
    if (framingLive.isEmpty) return s.isAnalyzing;
    final ids = {for (final f in s.framing) f.takeId, ...framingLive.keys};
    return ids.any((id) => framingStatus(id) == MontageFramingStatus.analyzing);
  }

  /// Progreso (0...1) del análisis de una toma; `null` si no hay dato.
  double? framingProgress(String takeId) {
    final live = framingLive[takeId];
    if (live != null) return live.progress;
    for (final f in snapshot?.framing ?? const <MontageFramingInfo>[]) {
      if (f.takeId == takeId) return f.progress;
    }
    return null;
  }

  /// Hay carriles (tomas) en el tema.
  bool get hasTakes => snapshot?.lanes.isNotEmpty ?? false;

  /// «1920 × 1080», tal como lo da el núcleo.
  String get canvasLabel => snapshot?.canvasLabel ?? '';
  bool get isPortrait => snapshot?.isPortrait ?? false;

  /// El selector de formato solo se muestra con más de un códec (MO3).
  bool get formatVisible => (snapshot?.export.options.codecs.length ?? 0) > 1;
  bool get keepAspectApplies => snapshot?.keepAspectApplies ?? false;

  /// «Exportar»: hay tomas con vídeo, ningún análisis en curso y ninguna exportación en marcha.
  bool get exportEnabled => (snapshot?.hasVideo ?? false) && !isAnalyzing && !exportRunning;

  /// Rango del cursor `[start, end]` (`transport.span`).
  MontageRangeInfo? get span => snapshot?.transport.span;

  MontageState copyWith({
    Object? projectId = _keep,
    Object? snapshot = _keep,
    bool? loading,
    Object? loadError = _keep,
    Object? actionError = _keep,
    Object? exportLive = _keep,
    Map<String, MontageFramingEvent>? framingLive,
  }) =>
      MontageState(
        projectId: identical(projectId, _keep) ? this.projectId : projectId as String?,
        snapshot: identical(snapshot, _keep) ? this.snapshot : snapshot as MontageSnapshot?,
        loading: loading ?? this.loading,
        loadError: identical(loadError, _keep) ? this.loadError : loadError as CoreError?,
        actionError: identical(actionError, _keep) ? this.actionError : actionError as CoreError?,
        exportLive: identical(exportLive, _keep) ? this.exportLive : exportLive as MontageExportEvent?,
        framingLive: framingLive ?? this.framingLive,
      );
}

/// Fotograma de la hoja de encuadre con la ruta ya resuelta (MO6).
class MontageFrame {
  const MontageFrame({required this.result, required this.absolutePath, this.themeFolder});

  final MontageFramingFrameResult result;

  /// `themeFolder/result.path`; si la carpeta del tema no se conoce, la ruta relativa tal cual.
  final String absolutePath;

  /// Versión del fichero (el núcleo lo reescribe en la misma ruta en cada petición).
  int get version => result.version;

  /// Carpeta del tema (`projectsFolder/folderName`), nula si la biblioteca aún no la conoce.
  final String? themeFolder;
}

/// Une carpeta y ruta relativa con el separador de la plataforma.
String joinPath(String folder, String relative, {required bool windows}) {
  final sep = windows ? r'\' : '/';
  final base = folder.endsWith('/') || folder.endsWith(r'\') ? folder.substring(0, folder.length - 1) : folder;
  final rel = windows ? relative.replaceAll('/', r'\') : relative;
  return '$base$sep$rel';
}

/// Limita [seconds] al rango `span` del snapshot.
double clampToSpan(double seconds, MontageRangeInfo span) {
  final lo = span.start;
  final hi = span.end < lo ? lo : span.end;
  return seconds.clamp(lo, hi).toDouble();
}
