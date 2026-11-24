import 'package:flutter/foundation.dart' show immutable;

import '../core/core_client.dart' show Json;

export 'video_set_settings_params.dart';
export 'video_settings.dart';

List<T> _list<T>(Object? raw, T Function(Json) fromJson) =>
    [for (final e in raw as List) fromJson(e as Json)];

/// `kind` de cámara. Valores no previstos caen en `unknown`.
enum CameraKind {
  builtIn,
  external,
  continuity,
  simulated,
  other,
  unknown;

  static CameraKind parse(Object? raw) => values.asNameMap()[raw] ?? unknown;
}

/// `state` de `CameraPreviewResult`. Valores no previstos caen en `unknown`.
enum PreviewState {
  idle,
  live,
  simulated,
  noCamera,
  denied,
  failed,
  unknown;

  static PreviewState parse(Object? raw) => values.asNameMap()[raw] ?? unknown;
}

@immutable
class VideoFps {
  const VideoFps({required this.value, required this.label});

  factory VideoFps.fromJson(Json j) => VideoFps(
        value: (j['value'] as num).toDouble(),
        label: j['label'] as String,
      );

  final double value;
  final String label;

  Json toJson() => {'value': value, 'label': label};
}

/// `{width, height, label?, fps?}`. `label` y `fps` faltan en los params de `video.setSettings`.
@immutable
class VideoResolution {
  const VideoResolution({
    required this.width,
    required this.height,
    this.label,
    this.fps,
  });

  factory VideoResolution.fromJson(Json j) => VideoResolution(
        width: j['width'] as int,
        height: j['height'] as int,
        label: j['label'] as String?,
        fps: j['fps'] == null ? null : _list(j['fps'], VideoFps.fromJson),
      );

  final int width;
  final int height;
  final String? label;
  final List<VideoFps>? fps;

  Json toJson() => {
        'width': width,
        'height': height,
        'label': label,
        'fps': fps?.map((f) => f.toJson()).toList(),
      }..removeWhere((_, v) => v == null);
}

@immutable
class CameraInfo {
  const CameraInfo({
    required this.id,
    required this.name,
    required this.kind,
    required this.isDefault,
    required this.resolutions,
  });

  factory CameraInfo.fromJson(Json j) => CameraInfo(
        id: j['id'] as String,
        name: j['name'] as String,
        kind: CameraKind.parse(j['kind']),
        isDefault: j['isDefault'] as bool,
        resolutions: _list(j['resolutions'], VideoResolution.fromJson),
      );

  final String id;
  final String name;
  final CameraKind kind;
  final bool isDefault;
  final List<VideoResolution> resolutions;

  Json toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'isDefault': isDefault,
        'resolutions': [for (final r in resolutions) r.toJson()],
      };
}

/// `video.cameras`.
@immutable
class VideoCameras {
  const VideoCameras({required this.cameras, this.defaultId});

  factory VideoCameras.fromJson(Json j) => VideoCameras(
        cameras: _list(j['cameras'], CameraInfo.fromJson),
        defaultId: j['defaultId'] as String?,
      );

  final List<CameraInfo> cameras;
  final String? defaultId;

  Json toJson() => {
        'cameras': [for (final c in cameras) c.toJson()],
        'defaultId': defaultId,
      };
}

/// `CameraPreviewResult`: respuesta de `video.preview.start` y `video.preview.stop`.
@immutable
class CameraPreviewResult {
  const CameraPreviewResult({
    required this.state,
    required this.rotation,
    required this.fromRecord,
    this.message,
    this.cameraId,
    this.cameraName,
    this.width,
    this.height,
    this.fps,
  });

  factory CameraPreviewResult.fromJson(Json j) => CameraPreviewResult(
        state: PreviewState.parse(j['state']),
        rotation: j['rotation'] as int,
        fromRecord: j['fromRecord'] as bool,
        message: j['message'] as String?,
        cameraId: j['cameraId'] as String?,
        cameraName: j['cameraName'] as String?,
        width: j['width'] as int?,
        height: j['height'] as int?,
        fps: (j['fps'] as num?)?.toDouble(),
      );

  final PreviewState state;
  final int rotation;
  final bool fromRecord;
  final String? message;
  final String? cameraId;
  final String? cameraName;
  final int? width;
  final int? height;
  final double? fps;

  Json toJson() => {
        'state': state.name,
        'rotation': rotation,
        'fromRecord': fromRecord,
        'message': message,
        'cameraId': cameraId,
        'cameraName': cameraName,
        'width': width,
        'height': height,
        'fps': fps,
      }..removeWhere((_, v) => v == null);
}

/// Respuesta de `video.openCameraPrivacy`.
@immutable
class VideoOpenCameraPrivacyResult {
  const VideoOpenCameraPrivacyResult({required this.opened});

  factory VideoOpenCameraPrivacyResult.fromJson(Json j) =>
      VideoOpenCameraPrivacyResult(opened: j['opened'] as bool);

  final bool opened;

  Json toJson() => {'opened': opened};
}
