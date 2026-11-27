import 'package:flutter/foundation.dart';

import '../core/core_client.dart' show Json;
import 'montage_events.dart';
import 'record_state.dart' show enumOf;
import 'takeview.dart' show TakeViewVideoStatus;

export 'montage_events.dart';

// Unidades: «tema» = segundos de la canción; «vídeo» = segundos del vídeo montado.
// `MontageSnapshot.transport.position` es tema; `videoPosition` es vídeo.

/// Fase de la vista previa (`MontagePreviewInfo.phase`).
enum MontagePreviewPhase { none, preparing, ready, error, unknown }

/// Fase del audio de la vista previa (`MontageAudioInfo.phase`).
enum MontageAudioPhase { none, preparing, ready, silent, error, unknown }

// ---------- Tipos anidados ----------

/// Tramo `{start, end}` en segundos (tema).
@immutable
class MontageRangeInfo {
  const MontageRangeInfo({required this.start, required this.end});
  factory MontageRangeInfo.fromJson(Json j) => MontageRangeInfo(
        start: (j['start'] as num).toDouble(),
        end: (j['end'] as num).toDouble(),
      );
  final double start;
  final double end;
  Json toJson() => {'start': start, 'end': end};
}

/// Resolución en píxeles.
@immutable
class MontageResolutionInfo {
  const MontageResolutionInfo({required this.width, required this.height});
  factory MontageResolutionInfo.fromJson(Json j) => MontageResolutionInfo(width: j['width'] as int, height: j['height'] as int);
  final int width;
  final int height;
  Json toJson() => {'width': width, 'height': height};
}

/// Caja de encuadre normalizada 0...1.
@immutable
class MontageBoxInfo {
  const MontageBoxInfo({required this.x, required this.y, required this.width, required this.height});
  factory MontageBoxInfo.fromJson(Json j) => MontageBoxInfo(
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        width: (j['width'] as num).toDouble(),
        height: (j['height'] as num).toDouble(),
      );
  final double x;
  final double y;
  final double width;
  final double height;
  Json toJson() => {'x': x, 'y': y, 'width': width, 'height': height};
}

/// Desplazamiento del encuadre seguido (rango -0,5...0,5).
@immutable
class MontageOffsetInfo {
  const MontageOffsetInfo({required this.x, required this.y});
  factory MontageOffsetInfo.fromJson(Json j) => MontageOffsetInfo(x: (j['x'] as num).toDouble(), y: (j['y'] as num).toDouble());
  final double x;
  final double y;
  Json toJson() => {'x': x, 'y': y};
}

/// Lane del montaje. `replaces` = rol (`rhythm|left|right|lead`).
@immutable
class MontageLaneInfo {
  const MontageLaneInfo({
    required this.id,
    required this.takeId,
    required this.partName,
    required this.isSolo,
    required this.presence,
    required this.take,
    required this.hasVideo,
    required this.rotation,
    this.replaces,
  });
  factory MontageLaneInfo.fromJson(Json j) => MontageLaneInfo(
        id: j['id'] as String,
        takeId: j['takeId'] as String,
        partName: j['partName'] as String,
        isSolo: j['isSolo'] as bool,
        replaces: j['replaces'] as String?,
        presence: [for (final p in j['presence'] as List) MontageRangeInfo.fromJson(p as Json)],
        take: MontageRangeInfo.fromJson(j['take'] as Json),
        hasVideo: j['hasVideo'] as bool,
        rotation: j['rotation'] as int,
      );
  final String id;
  final String takeId;
  final String partName;
  final bool isSolo;
  final String? replaces;
  final List<MontageRangeInfo> presence;
  final MontageRangeInfo take;
  final bool hasVideo;
  /// Grados: 0, 90, 180 o 270.
  final int rotation;
  Json toJson() => {
        'id': id,
        'takeId': takeId,
        'partName': partName,
        'isSolo': isSolo,
        if (replaces != null) 'replaces': replaces,
        'presence': [for (final p in presence) p.toJson()],
        'take': take.toJson(),
        'hasVideo': hasVideo,
        'rotation': rotation,
      };
}

@immutable
class MontageSegmentInfo {
  const MontageSegmentInfo({required this.start, required this.end, required this.fadeIn, required this.fadeOut});
  factory MontageSegmentInfo.fromJson(Json j) => MontageSegmentInfo(
        start: (j['start'] as num).toDouble(),
        end: (j['end'] as num).toDouble(),
        fadeIn: j['fadeIn'] as bool,
        fadeOut: j['fadeOut'] as bool,
      );
  final double start;
  final double end;
  final bool fadeIn;
  final bool fadeOut;
  Json toJson() => {'start': start, 'end': end, 'fadeIn': fadeIn, 'fadeOut': fadeOut};
}

@immutable
class MontageSectionInfo {
  const MontageSectionInfo({required this.id, required this.name, required this.start, required this.end, required this.solo});
  factory MontageSectionInfo.fromJson(Json j) => MontageSectionInfo(
        id: j['id'] as String,
        name: j['name'] as String,
        start: (j['start'] as num).toDouble(),
        end: (j['end'] as num).toDouble(),
        solo: j['solo'] as bool,
      );
  final String id;
  final String name;
  final double start;
  final double end;
  final bool solo;
  Json toJson() => {'id': id, 'name': name, 'start': start, 'end': end, 'solo': solo};
}

/// Corte. `partId` ausente = automático; `eligible` ordenado.
@immutable
class MontageCutInfo {
  const MontageCutInfo({required this.id, required this.time, required this.covered, required this.eligible, this.partId});
  factory MontageCutInfo.fromJson(Json j) => MontageCutInfo(
        id: j['id'] as String,
        time: (j['time'] as num).toDouble(),
        partId: j['partId'] as String?,
        covered: j['covered'] as bool,
        eligible: [for (final e in j['eligible'] as List) e as String],
      );
  final String id;
  final double time;
  final String? partId;
  final bool covered;
  final List<String> eligible;
  Json toJson() => {
        'id': id,
        'time': time,
        if (partId != null) 'partId': partId,
        'covered': covered,
        'eligible': eligible,
      };
}

@immutable
class MontagePlaneShotInfo {
  const MontagePlaneShotInfo({required this.start, required this.end, required this.black, this.partId});
  factory MontagePlaneShotInfo.fromJson(Json j) => MontagePlaneShotInfo(
        start: (j['start'] as num).toDouble(),
        end: (j['end'] as num).toDouble(),
        partId: j['partId'] as String?,
        black: j['black'] as bool,
      );
  final double start;
  final double end;
  final String? partId;
  final bool black;
  Json toJson() => {'start': start, 'end': end, if (partId != null) 'partId': partId, 'black': black};
}

/// Encuadre por lane con vídeo. `mode`: `fixed|follow`.
@immutable
class MontageFramingInfo {
  const MontageFramingInfo({
    required this.takeId,
    required this.status,
    required this.progress,
    required this.mode,
    required this.followZoom,
    required this.followOffset,
    this.samples,
    this.detected,
    this.error,
    this.manualBox,
  });
  factory MontageFramingInfo.fromJson(Json j) => MontageFramingInfo(
        takeId: j['takeId'] as String,
        status: enumOf(MontageFramingStatus.values, MontageFramingStatus.unknown, j['status']),
        progress: (j['progress'] as num).toDouble(),
        samples: j['samples'] as int?,
        detected: j['detected'] as int?,
        error: j['error'] as String?,
        mode: j['mode'] as String,
        manualBox: j['manualBox'] == null ? null : MontageBoxInfo.fromJson(j['manualBox'] as Json),
        followZoom: (j['followZoom'] as num).toDouble(),
        followOffset: MontageOffsetInfo.fromJson(j['followOffset'] as Json),
      );
  final String takeId;
  final MontageFramingStatus status;
  final double progress;
  final int? samples;
  final int? detected;
  final String? error;
  final String mode;
  final MontageBoxInfo? manualBox;
  final double followZoom;
  final MontageOffsetInfo followOffset;
  Json toJson() => {
        'takeId': takeId,
        'status': status.name,
        'progress': progress,
        if (samples != null) 'samples': samples,
        if (detected != null) 'detected': detected,
        if (error != null) 'error': error,
        'mode': mode,
        if (manualBox != null) 'manualBox': manualBox!.toJson(),
        'followZoom': followZoom,
        'followOffset': followOffset.toJson(),
      };
}

/// Opciones de exportación disponibles. En Windows `codecs` solo `h264`.
@immutable
class MontageExportOptions {
  const MontageExportOptions({required this.codecs, required this.containers, required this.resolutions, required this.fps});
  factory MontageExportOptions.fromJson(Json j) => MontageExportOptions(
        codecs: [for (final c in j['codecs'] as List) c as String],
        containers: [for (final c in j['containers'] as List) c as String],
        resolutions: [for (final r in j['resolutions'] as List) MontageResolutionInfo.fromJson(r as Json)],
        fps: [for (final f in j['fps'] as List) (f as num).toDouble()],
      );
  final List<String> codecs;
  final List<String> containers;
  final List<MontageResolutionInfo> resolutions;
  final List<double> fps;
  Json toJson() => {
        'codecs': codecs,
        'containers': containers,
        'resolutions': [for (final r in resolutions) r.toJson()],
        'fps': fps,
      };
}

/// Configuración de exportación. `codec` = guardado (puede ser `hevc`); `effectiveCodec` = el que se usará.
@immutable
class MontageExportInfo {
  const MontageExportInfo({
    required this.codec,
    required this.effectiveCodec,
    required this.container,
    required this.resolution,
    required this.size,
    required this.fps,
    required this.normalize,
    required this.limiter,
    required this.trackWAVs,
    required this.options,
    required this.canExport,
  });
  factory MontageExportInfo.fromJson(Json j) => MontageExportInfo(
        codec: j['codec'] as String,
        effectiveCodec: j['effectiveCodec'] as String,
        container: j['container'] as String,
        resolution: MontageResolutionInfo.fromJson(j['resolution'] as Json),
        size: MontageResolutionInfo.fromJson(j['size'] as Json),
        fps: (j['fps'] as num).toDouble(),
        normalize: j['normalize'] as bool,
        limiter: j['limiter'] as bool,
        trackWAVs: j['trackWAVs'] as bool,
        options: MontageExportOptions.fromJson(j['options'] as Json),
        canExport: j['canExport'] as bool,
      );
  final String codec;
  final String effectiveCodec;
  final String container;
  final MontageResolutionInfo resolution;
  /// Tamaño final según el layout.
  final MontageResolutionInfo size;
  final double fps;
  final bool normalize;
  final bool limiter;
  final bool trackWAVs;
  final MontageExportOptions options;
  final bool canExport;
  Json toJson() => {
        'codec': codec,
        'effectiveCodec': effectiveCodec,
        'container': container,
        'resolution': resolution.toJson(),
        'size': size.toJson(),
        'fps': fps,
        'normalize': normalize,
        'limiter': limiter,
        'trackWAVs': trackWAVs,
        'options': options.toJson(),
        'canExport': canExport,
      };
}

/// Audio de la vista previa. `file` = nombre del WAV en `cache/montage/`.
@immutable
class MontageAudioInfo {
  const MontageAudioInfo({required this.phase, required this.progress, this.error, this.file});
  factory MontageAudioInfo.fromJson(Json j) => MontageAudioInfo(
        phase: enumOf(MontageAudioPhase.values, MontageAudioPhase.unknown, j['phase']),
        progress: (j['progress'] as num).toDouble(),
        error: j['error'] as String?,
        file: j['file'] as String?,
      );
  final MontageAudioPhase phase;
  final double progress;
  final String? error;
  final String? file;
  Json toJson() => {
        'phase': phase.name,
        'progress': progress,
        if (error != null) 'error': error,
        if (file != null) 'file': file,
      };
}

/// Vista previa de vídeo. Tiempos de frame en ms; `width`/`height` = tamaño de fotogramas.
@immutable
class MontagePreviewInfo {
  const MontagePreviewInfo({
    required this.phase,
    required this.audio,
    required this.fps,
    required this.maxDimension,
    required this.width,
    required this.height,
    required this.delivered,
    required this.skipped,
    required this.lastFrameMillis,
    required this.frameP50Ms,
    required this.frameP95Ms,
    required this.videos,
    this.error,
    this.duration,
  });
  factory MontagePreviewInfo.fromJson(Json j) => MontagePreviewInfo(
        phase: enumOf(MontagePreviewPhase.values, MontagePreviewPhase.unknown, j['phase']),
        error: j['error'] as String?,
        audio: MontageAudioInfo.fromJson(j['audio'] as Json),
        fps: (j['fps'] as num).toDouble(),
        maxDimension: j['maxDimension'] as int,
        width: j['width'] as int,
        height: j['height'] as int,
        duration: (j['duration'] as num?)?.toDouble(),
        delivered: j['delivered'] as int,
        skipped: j['skipped'] as int,
        lastFrameMillis: (j['lastFrameMillis'] as num).toDouble(),
        frameP50Ms: (j['frameP50Ms'] as num).toDouble(),
        frameP95Ms: (j['frameP95Ms'] as num).toDouble(),
        videos: [for (final v in j['videos'] as List) TakeViewVideoStatus.fromJson(v as Json)],
      );
  final MontagePreviewPhase phase;
  final String? error;
  final MontageAudioInfo audio;
  final double fps;
  final int maxDimension;
  final int width;
  final int height;
  /// Vídeo, en segundos.
  final double? duration;
  final int delivered;
  final int skipped;
  final double lastFrameMillis;
  final double frameP50Ms;
  final double frameP95Ms;
  /// Conversiones de vídeo en curso o fallidas (`video-converting` | `video-failed`).
  final List<TakeViewVideoStatus> videos;
  Json toJson() => {
        'phase': phase.name,
        if (error != null) 'error': error,
        'audio': audio.toJson(),
        'fps': fps,
        'maxDimension': maxDimension,
        'width': width,
        'height': height,
        if (duration != null) 'duration': duration,
        'delivered': delivered,
        'skipped': skipped,
        'lastFrameMillis': lastFrameMillis,
        'frameP50Ms': frameP50Ms,
        'frameP95Ms': frameP95Ms,
        'videos': [for (final v in videos) v.toJson()],
      };
}

/// Transporte. `position` = tema; `videoPosition` = vídeo.
@immutable
class MontageTransportInfo {
  const MontageTransportInfo({required this.playing, required this.position, required this.videoPosition, required this.span, this.audioError});
  factory MontageTransportInfo.fromJson(Json j) => MontageTransportInfo(
        playing: j['playing'] as bool,
        position: (j['position'] as num).toDouble(),
        videoPosition: (j['videoPosition'] as num).toDouble(),
        span: MontageRangeInfo.fromJson(j['span'] as Json),
        audioError: j['audioError'] as String?,
      );
  final bool playing;
  final double position;
  final double videoPosition;
  final MontageRangeInfo span;
  final String? audioError;
  Json toJson() => {
        'playing': playing,
        'position': position,
        'videoPosition': videoPosition,
        'span': span.toJson(),
        if (audioError != null) 'audioError': audioError,
      };
}

// ---------- Snapshot ----------

/// `MontageSnapshot`: resultado de casi todos los `montage.*` y evento `montage.state`.
/// `autoPartId` solo con layout `single` / `single-landscape`.
@immutable
class MontageSnapshot {
  const MontageSnapshot({
    required this.projectId,
    required this.title,
    required this.layout,
    required this.isPortrait,
    required this.isSingleShot,
    required this.canvasLabel,
    required this.keepAspectApplies,
    required this.caption,
    required this.showPartLabels,
    required this.keepVideoAspect,
    required this.cutGaps,
    required this.singleRhythmCandidates,
    required this.hasPlan,
    required this.hasVideo,
    required this.span,
    required this.barDuration,
    required this.songDuration,
    required this.anticipationLabel,
    required this.lanes,
    required this.audioOnlyParts,
    required this.missingParts,
    required this.segments,
    required this.sections,
    required this.cuts,
    required this.cutCandidates,
    required this.planeShots,
    required this.framing,
    required this.isAnalyzing,
    required this.export,
    required this.exportStatus,
    required this.preview,
    required this.transport,
    this.artist,
    this.singleRhythmPartId,
    this.autoPartId,
  });
  factory MontageSnapshot.fromJson(Json j) => MontageSnapshot(
        projectId: j['projectId'] as String,
        title: j['title'] as String,
        artist: j['artist'] as String?,
        layout: j['layout'] as String,
        isPortrait: j['isPortrait'] as bool,
        isSingleShot: j['isSingleShot'] as bool,
        canvasLabel: j['canvasLabel'] as String,
        keepAspectApplies: j['keepAspectApplies'] as bool,
        caption: j['caption'] as bool,
        showPartLabels: j['showPartLabels'] as bool,
        keepVideoAspect: j['keepVideoAspect'] as bool,
        cutGaps: j['cutGaps'] as bool,
        singleRhythmPartId: j['singleRhythmPartId'] as String?,
        singleRhythmCandidates: [for (final p in j['singleRhythmCandidates'] as List) p as String],
        hasPlan: j['hasPlan'] as bool,
        hasVideo: j['hasVideo'] as bool,
        span: MontageRangeInfo.fromJson(j['span'] as Json),
        barDuration: (j['barDuration'] as num).toDouble(),
        songDuration: (j['songDuration'] as num).toDouble(),
        anticipationLabel: j['anticipationLabel'] as String,
        lanes: [for (final l in j['lanes'] as List) MontageLaneInfo.fromJson(l as Json)],
        audioOnlyParts: [for (final p in j['audioOnlyParts'] as List) p as String],
        missingParts: [for (final p in j['missingParts'] as List) p as String],
        segments: [for (final s in j['segments'] as List) MontageSegmentInfo.fromJson(s as Json)],
        sections: [for (final s in j['sections'] as List) MontageSectionInfo.fromJson(s as Json)],
        cuts: [for (final c in j['cuts'] as List) MontageCutInfo.fromJson(c as Json)],
        cutCandidates: [for (final c in j['cutCandidates'] as List) c as String],
        planeShots: [for (final p in j['planeShots'] as List) MontagePlaneShotInfo.fromJson(p as Json)],
        framing: [for (final f in j['framing'] as List) MontageFramingInfo.fromJson(f as Json)],
        isAnalyzing: j['isAnalyzing'] as bool,
        export: MontageExportInfo.fromJson(j['export'] as Json),
        exportStatus: MontageExportEvent.fromJson(j['exportStatus'] as Json),
        preview: MontagePreviewInfo.fromJson(j['preview'] as Json),
        transport: MontageTransportInfo.fromJson(j['transport'] as Json),
        autoPartId: j['autoPartId'] as String?,
      );
  final String projectId;
  final String title;
  final String? artist;
  /// `side|grid|stack|single|single-landscape`.
  final String layout;
  final bool isPortrait;
  final bool isSingleShot;
  final String canvasLabel;
  final bool keepAspectApplies;
  final bool caption;
  final bool showPartLabels;
  final bool keepVideoAspect;
  final bool cutGaps;
  final String? singleRhythmPartId;
  final List<String> singleRhythmCandidates;
  final bool hasPlan;
  final bool hasVideo;
  final MontageRangeInfo span;
  final double barDuration;
  /// 0 si se desconoce.
  final double songDuration;
  /// Texto, p. ej. «0,5 s».
  final String anticipationLabel;
  final List<MontageLaneInfo> lanes;
  final List<String> audioOnlyParts;
  final List<String> missingParts;
  final List<MontageSegmentInfo> segments;
  final List<MontageSectionInfo> sections;
  final List<MontageCutInfo> cuts;
  final List<String> cutCandidates;
  final List<MontagePlaneShotInfo> planeShots;
  final List<MontageFramingInfo> framing;
  final bool isAnalyzing;
  final MontageExportInfo export;
  final MontageExportEvent exportStatus;
  final MontagePreviewInfo preview;
  final MontageTransportInfo transport;
  /// Solo con layout `single` / `single-landscape`.
  final String? autoPartId;
  Json toJson() => {
        'projectId': projectId,
        'title': title,
        if (artist != null) 'artist': artist,
        'layout': layout,
        'isPortrait': isPortrait,
        'isSingleShot': isSingleShot,
        'canvasLabel': canvasLabel,
        'keepAspectApplies': keepAspectApplies,
        'caption': caption,
        'showPartLabels': showPartLabels,
        'keepVideoAspect': keepVideoAspect,
        'cutGaps': cutGaps,
        if (singleRhythmPartId != null) 'singleRhythmPartId': singleRhythmPartId,
        'singleRhythmCandidates': singleRhythmCandidates,
        'hasPlan': hasPlan,
        'hasVideo': hasVideo,
        'span': span.toJson(),
        'barDuration': barDuration,
        'songDuration': songDuration,
        'anticipationLabel': anticipationLabel,
        'lanes': [for (final l in lanes) l.toJson()],
        'audioOnlyParts': audioOnlyParts,
        'missingParts': missingParts,
        'segments': [for (final s in segments) s.toJson()],
        'sections': [for (final s in sections) s.toJson()],
        'cuts': [for (final c in cuts) c.toJson()],
        'cutCandidates': cutCandidates,
        'planeShots': [for (final p in planeShots) p.toJson()],
        'framing': [for (final f in framing) f.toJson()],
        'isAnalyzing': isAnalyzing,
        'export': export.toJson(),
        'exportStatus': exportStatus.toJson(),
        'preview': preview.toJson(),
        'transport': transport.toJson(),
        if (autoPartId != null) 'autoPartId': autoPartId,
      };
}

// ---------- Resultados ----------

/// `montage.addCut`.
@immutable
class MontageAddCutResult {
  const MontageAddCutResult({required this.cutId, required this.snapshot});
  factory MontageAddCutResult.fromJson(Json j) => MontageAddCutResult(
        cutId: j['cutId'] as String,
        snapshot: MontageSnapshot.fromJson(j['snapshot'] as Json),
      );
  final String cutId;
  final MontageSnapshot snapshot;
  Json toJson() => {'cutId': cutId, 'snapshot': snapshot.toJson()};
}

/// `montage.framingFrame`. `path` relativa a la carpeta del tema, con `/`.
@immutable
class MontageFramingFrameResult {
  const MontageFramingFrameResult({
    required this.path,
    required this.width,
    required this.height,
    required this.time,
    required this.version,
    this.box,
  });
  factory MontageFramingFrameResult.fromJson(Json j) => MontageFramingFrameResult(
        path: j['path'] as String,
        width: j['width'] as int,
        height: j['height'] as int,
        time: (j['time'] as num).toDouble(),
        version: j['version'] as int,
        box: j['box'] == null ? null : MontageBoxInfo.fromJson(j['box'] as Json),
      );
  final String path;
  final int width;
  final int height;
  final double time;
  final int version;
  final MontageBoxInfo? box;
  Json toJson() => {
        'path': path,
        'width': width,
        'height': height,
        'time': time,
        'version': version,
        if (box != null) 'box': box!.toJson(),
      };
}

/// Params de `montage.snapCut`: tiempo (tema) de un corte arrastrado; no guarda nada.
@immutable
class MontageSnapCutParams {
  const MontageSnapCutParams({required this.id, required this.time});
  factory MontageSnapCutParams.fromJson(Json j) => MontageSnapCutParams(id: j['id'] as String, time: (j['time'] as num).toDouble());
  final String id;
  final double time;
  Json toJson() => {'id': id, 'time': time};
}

/// `montage.snapCut`: tiempo ajustado al pulso y a los cortes vecinos.
@immutable
class MontageSnapCutResult {
  const MontageSnapCutResult({required this.time});
  factory MontageSnapCutResult.fromJson(Json j) => MontageSnapCutResult(time: (j['time'] as num).toDouble());
  final double time;
  Json toJson() => {'time': time};
}

/// Params de `montage.framingBox`: caja efectiva en `time` con overrides sobre una copia del encuadre; no guarda nada.
@immutable
class MontageFramingBoxParams {
  const MontageFramingBoxParams({
    required this.takeId,
    required this.time,
    this.mode,
    this.manualBox,
    this.clearManualBox,
    this.followZoom,
    this.followOffset,
  });
  factory MontageFramingBoxParams.fromJson(Json j) => MontageFramingBoxParams(
        takeId: j['takeId'] as String,
        time: (j['time'] as num).toDouble(),
        mode: j['mode'] as String?,
        manualBox: j['manualBox'] == null ? null : MontageBoxInfo.fromJson(j['manualBox'] as Json),
        clearManualBox: j['clearManualBox'] as bool?,
        followZoom: (j['followZoom'] as num?)?.toDouble(),
        followOffset: j['followOffset'] == null ? null : MontageOffsetInfo.fromJson(j['followOffset'] as Json),
      );
  final String takeId;
  final double time;
  final String? mode;
  final MontageBoxInfo? manualBox;
  final bool? clearManualBox;
  final double? followZoom;
  final MontageOffsetInfo? followOffset;
  Json toJson() => {
        'takeId': takeId,
        'time': time,
        if (mode != null) 'mode': mode,
        if (manualBox != null) 'manualBox': manualBox!.toJson(),
        if (clearManualBox != null) 'clearManualBox': clearManualBox,
        if (followZoom != null) 'followZoom': followZoom,
        if (followOffset != null) 'followOffset': followOffset!.toJson(),
      };
}

/// `montage.framingBox`. Sin `box` = sin caja (fotograma entero).
@immutable
class MontageFramingBoxResult {
  const MontageFramingBoxResult({this.box});
  factory MontageFramingBoxResult.fromJson(Json j) =>
      MontageFramingBoxResult(box: j['box'] == null ? null : MontageBoxInfo.fromJson(j['box'] as Json));
  final MontageBoxInfo? box;
  Json toJson() => {if (box != null) 'box': box!.toJson()};
}

/// `montage.reveal`.
@immutable
class MontageRevealResult {
  const MontageRevealResult({required this.revealed});
  factory MontageRevealResult.fromJson(Json j) => MontageRevealResult(revealed: j['revealed'] as bool);
  final bool revealed;
  Json toJson() => {'revealed': revealed};
}
