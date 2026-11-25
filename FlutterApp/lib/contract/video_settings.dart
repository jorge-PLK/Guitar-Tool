import 'package:flutter/foundation.dart' show immutable;

import '../core/core_client.dart' show Json;
import 'video.dart' show VideoResolution;

List<T> _list<T>(Object? raw, T Function(Json) fromJson) =>
    [for (final e in raw as List) fromJson(e as Json)];

Map<String, int> _intMap(Object? raw) => {
      for (final e in (raw as Map).entries)
        (e.key as String): (e.value as num).toInt(),
    };

@immutable
class VideoExport {
  const VideoExport({
    required this.codec,
    required this.resolution,
    required this.titleOverlay,
    required this.exportStemWAVs,
    required this.normalizeLUFS,
  });

  factory VideoExport.fromJson(Json j) => VideoExport(
        codec: j['codec'] as String,
        resolution: VideoResolution.fromJson(j['resolution'] as Json),
        titleOverlay: j['titleOverlay'] as bool,
        exportStemWAVs: j['exportStemWAVs'] as bool,
        normalizeLUFS: (j['normalizeLUFS'] as num).toDouble(),
      );

  final String codec;
  final VideoResolution resolution;
  final bool titleOverlay;
  final bool exportStemWAVs;
  final double normalizeLUFS;

  Json toJson() => {
        'codec': codec,
        'resolution': resolution.toJson(),
        'titleOverlay': titleOverlay,
        'exportStemWAVs': exportStemWAVs,
        'normalizeLUFS': normalizeLUFS,
      };
}

@immutable
class VideoOffsetRange {
  const VideoOffsetRange({required this.min, required this.max});

  factory VideoOffsetRange.fromJson(Json j) => VideoOffsetRange(
        // Swift lo emite como `.num(Double)`: puede llegar como 500.0.
        min: (j['min'] as num).toInt(),
        max: (j['max'] as num).toInt(),
      );

  final int min;
  final int max;

  Json toJson() => {'min': min, 'max': max};
}

@immutable
class VideoChoices {
  const VideoChoices({
    required this.codecs,
    required this.exportResolutions,
    required this.rotations,
    required this.offsetRangeMs,
  });

  factory VideoChoices.fromJson(Json j) => VideoChoices(
        codecs: (j['codecs'] as List).cast<String>(),
        exportResolutions: _list(j['exportResolutions'], VideoResolution.fromJson),
        rotations: (j['rotations'] as List).cast<int>(),
        offsetRangeMs: VideoOffsetRange.fromJson(j['offsetRangeMs'] as Json),
      );

  final List<String> codecs;
  final List<VideoResolution> exportResolutions;
  final List<int> rotations;
  final VideoOffsetRange offsetRangeMs;

  Json toJson() => {
        'codecs': codecs,
        'exportResolutions': [for (final r in exportResolutions) r.toJson()],
        'rotations': rotations,
        'offsetRangeMs': offsetRangeMs.toJson(),
      };
}

@immutable
class VideoShown {
  const VideoShown({
    required this.resolution,
    required this.fps,
    required this.fpsLabel,
  });

  factory VideoShown.fromJson(Json j) => VideoShown(
        resolution: VideoResolution.fromJson(j['resolution'] as Json),
        fps: (j['fps'] as num).toDouble(),
        fpsLabel: j['fpsLabel'] as String,
      );

  final VideoResolution resolution;
  final double fps;
  final String fpsLabel;

  Json toJson() => {
        'resolution': resolution.toJson(),
        'fps': fps,
        'fpsLabel': fpsLabel,
      };
}

/// `videoJSON`: respuesta de `video.settings` y de `video.setSettings`.
@immutable
class VideoSettings {
  const VideoSettings({
    required this.cameraConnected,
    required this.noCamera,
    required this.resolution,
    required this.fps,
    required this.fpsLabel,
    required this.offsetMs,
    required this.rotation,
    required this.offsetsMs,
    required this.rotations,
    required this.export,
    required this.choices,
    this.cameraUID,
    this.cameraName,
    this.effectiveCameraId,
    this.shown,
  });

  factory VideoSettings.fromJson(Json j) => VideoSettings(
        cameraUID: j['cameraUID'] as String?,
        cameraConnected: j['cameraConnected'] as bool,
        cameraName: j['cameraName'] as String?,
        effectiveCameraId: j['effectiveCameraId'] as String?,
        noCamera: j['noCamera'] as bool,
        resolution: VideoResolution.fromJson(j['resolution'] as Json),
        fps: (j['fps'] as num).toDouble(),
        fpsLabel: j['fpsLabel'] as String,
        shown: j['shown'] == null ? null : VideoShown.fromJson(j['shown'] as Json),
        offsetMs: j['offsetMs'] as int,
        rotation: j['rotation'] as int,
        offsetsMs: _intMap(j['offsetsMs']),
        rotations: _intMap(j['rotations']),
        export: VideoExport.fromJson(j['export'] as Json),
        choices: VideoChoices.fromJson(j['choices'] as Json),
      );

  final String? cameraUID;
  final bool cameraConnected;
  final String? cameraName;
  final String? effectiveCameraId;
  final bool noCamera;
  final VideoResolution resolution;
  final double fps;
  final String fpsLabel;
  final VideoShown? shown;
  final int offsetMs;
  final int rotation;
  final Map<String, int> offsetsMs;
  final Map<String, int> rotations;
  final VideoExport export;
  final VideoChoices choices;

  Json toJson() => {
        'cameraUID': cameraUID,
        'cameraConnected': cameraConnected,
        'cameraName': cameraName,
        'effectiveCameraId': effectiveCameraId,
        'noCamera': noCamera,
        'resolution': resolution.toJson(),
        'fps': fps,
        'fpsLabel': fpsLabel,
        'shown': shown?.toJson(),
        'offsetMs': offsetMs,
        'rotation': rotation,
        'offsetsMs': offsetsMs,
        'rotations': rotations,
        'export': export.toJson(),
        'choices': choices.toJson(),
      }..removeWhere((_, v) => v == null);
}
