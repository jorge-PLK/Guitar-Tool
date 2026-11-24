import 'package:flutter/foundation.dart' show immutable;

import '../core/core_client.dart' show Json;
import 'patch.dart';
import 'video.dart' show VideoResolution;

/// Params de `video.setSettings.offset`. Sin `cameraId`, se aplica a la cámara efectiva.
@immutable
class VideoOffsetParams {
  const VideoOffsetParams({required this.ms, this.cameraId});

  factory VideoOffsetParams.fromJson(Json j) => VideoOffsetParams(
        ms: (j['ms'] as num).toDouble(),
        cameraId: j['cameraId'] as String?,
      );

  final double ms;
  final String? cameraId;

  Json toJson() => {'cameraId': cameraId, 'ms': ms}
    ..removeWhere((_, v) => v == null);
}

/// Params de `video.setSettings.rotation`.
@immutable
class VideoRotationParams {
  const VideoRotationParams({required this.degrees, this.cameraId});

  factory VideoRotationParams.fromJson(Json j) => VideoRotationParams(
        degrees: j['degrees'] as int,
        cameraId: j['cameraId'] as String?,
      );

  final int degrees;
  final String? cameraId;

  Json toJson() => {'cameraId': cameraId, 'degrees': degrees}
    ..removeWhere((_, v) => v == null);
}

/// Params de `video.setSettings.export`. Todos opcionales: solo cambia lo enviado.
@immutable
class VideoExportParams {
  const VideoExportParams({
    this.codec,
    this.resolution,
    this.titleOverlay,
    this.exportStemWAVs,
  });

  factory VideoExportParams.fromJson(Json j) => VideoExportParams(
        codec: j['codec'] as String?,
        resolution: j['resolution'] == null
            ? null
            : VideoResolution.fromJson(j['resolution'] as Json),
        titleOverlay: j['titleOverlay'] as bool?,
        exportStemWAVs: j['exportStemWAVs'] as bool?,
      );

  final String? codec;
  final VideoResolution? resolution;
  final bool? titleOverlay;
  final bool? exportStemWAVs;

  Json toJson() => {
        'codec': codec,
        'resolution': resolution?.toJson(),
        'titleOverlay': titleOverlay,
        'exportStemWAVs': exportStemWAVs,
      }..removeWhere((_, v) => v == null);
}

/// Params de `video.setSettings`. `cameraUID`: ausente = no tocar; `null` = «Por defecto del sistema».
@immutable
class VideoSetSettingsParams {
  const VideoSetSettingsParams({
    this.cameraUID = const Patch.absent(),
    this.resolution,
    this.fps,
    this.offset,
    this.rotation,
    this.export,
  });

  factory VideoSetSettingsParams.fromJson(Json j) => VideoSetSettingsParams(
        cameraUID: Patch.fromMap(j, 'cameraUID', (r) => r as String),
        resolution: j['resolution'] == null
            ? null
            : VideoResolution.fromJson(j['resolution'] as Json),
        fps: (j['fps'] as num?)?.toDouble(),
        offset: j['offset'] == null
            ? null
            : VideoOffsetParams.fromJson(j['offset'] as Json),
        rotation: j['rotation'] == null
            ? null
            : VideoRotationParams.fromJson(j['rotation'] as Json),
        export: j['export'] == null
            ? null
            : VideoExportParams.fromJson(j['export'] as Json),
      );

  final Patch<String> cameraUID;
  final VideoResolution? resolution;
  final double? fps;
  final VideoOffsetParams? offset;
  final VideoRotationParams? rotation;
  final VideoExportParams? export;

  Json toJson() {
    final j = <String, Object?>{};
    cameraUID.writeTo(j, 'cameraUID');
    final r = resolution;
    if (r != null) j['resolution'] = r.toJson();
    final f = fps;
    if (f != null) j['fps'] = f;
    final o = offset;
    if (o != null) j['offset'] = o.toJson();
    final rot = rotation;
    if (rot != null) j['rotation'] = rot.toJson();
    final e = export;
    if (e != null) j['export'] = e.toJson();
    return j;
  }
}
