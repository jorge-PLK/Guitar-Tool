import 'package:flutter/foundation.dart';

import '../core/core_client.dart' show Json;

// Métodos `takeview.*`, eventos `takeview.position` y `takeview.video`.
// Los métodos de transporte devuelven [TakeViewSnapshot]. Params vacíos (`{}`) no tienen clase.

/// `takeview.open`: abre una toma de `project.json`.
@immutable
class TakeViewOpenParams {
  const TakeViewOpenParams({required this.projectId, required this.takeId});
  factory TakeViewOpenParams.fromJson(Json j) => TakeViewOpenParams(
        projectId: j['projectId'] as String,
        takeId: j['takeId'] as String,
      );
  final String projectId;
  final String takeId;
  Json toJson() => {'projectId': projectId, 'takeId': takeId};
}

/// `takeview.seek`: `seconds` de la toma.
@immutable
class TakeViewSeekParams {
  const TakeViewSeekParams({required this.seconds});
  factory TakeViewSeekParams.fromJson(Json j) => TakeViewSeekParams(seconds: (j['seconds'] as num).toDouble());
  final double seconds;
  Json toJson() => {'seconds': seconds};
}

/// `takeview.setBacking`: enciende o apaga el backing.
@immutable
class TakeViewBackingParams {
  const TakeViewBackingParams({required this.on});
  factory TakeViewBackingParams.fromJson(Json j) => TakeViewBackingParams(on: j['on'] as bool);
  final bool on;
  Json toJson() => {'on': on};
}

/// Estado del visor: resultado de los métodos de transporte.
/// `audioError` y `videoWidth`/`videoHeight`/`videoRotation` (FC1) son opcionales y se omiten si son nulos.
@immutable
class TakeViewSnapshot {
  const TakeViewSnapshot({
    required this.projectId,
    required this.takeId,
    required this.duration,
    required this.songStart,
    required this.hasBacking,
    required this.backingOn,
    required this.playing,
    required this.position,
    required this.epoch,
    required this.outputName,
    this.audioError,
    this.video,
    this.videoWidth,
    this.videoHeight,
    this.videoRotation,
  });
  factory TakeViewSnapshot.fromJson(Json j) => TakeViewSnapshot(
        projectId: j['projectId'] as String,
        takeId: j['takeId'] as String,
        duration: (j['duration'] as num).toDouble(),
        songStart: (j['songStart'] as num).toDouble(),
        hasBacking: j['hasBacking'] as bool,
        backingOn: j['backingOn'] as bool,
        playing: j['playing'] as bool,
        position: (j['position'] as num).toDouble(),
        epoch: j['epoch'] as int,
        outputName: j['outputName'] as String,
        audioError: j['audioError'] as String?,
        video: j['video'] == null ? null : TakeViewVideoStatus.fromJson(j['video'] as Json),
        videoWidth: j['videoWidth'] as int?,
        videoHeight: j['videoHeight'] as int?,
        videoRotation: j['videoRotation'] as int?,
      );
  final String projectId;
  final String takeId;
  /// Duración de la toma (s).
  final double duration;
  /// Inicio de la toma en el tema (s).
  final double songStart;
  final bool hasBacking;
  final bool backingOn;
  final bool playing;
  /// Tiempo de la toma (s), sin alisar.
  final double position;
  /// Sube en cada discontinuidad (play, pausa, seek, final).
  final int epoch;
  final String outputName;
  final String? audioError;
  /// Swift TakeViewSnapshot.video `TakeVideoStatusInfo?`: nil = vídeo listo.
  final TakeViewVideoStatus? video;
  final int? videoWidth;
  final int? videoHeight;
  final int? videoRotation;
  Json toJson() => {
        'projectId': projectId,
        'takeId': takeId,
        'duration': duration,
        'songStart': songStart,
        'hasBacking': hasBacking,
        'backingOn': backingOn,
        'playing': playing,
        'position': position,
        'epoch': epoch,
        'outputName': outputName,
        if (audioError != null) 'audioError': audioError,
        if (video != null) 'video': video!.toJson(),
        if (videoWidth != null) 'videoWidth': videoWidth,
        if (videoHeight != null) 'videoHeight': videoHeight,
        if (videoRotation != null) 'videoRotation': videoRotation,
      };
}

/// Payload de `takeview.position`: reloj del visor.
@immutable
class TakeViewPositionEvent {
  const TakeViewPositionEvent({
    required this.seconds,
    required this.playing,
    required this.rate,
    required this.at,
    required this.epoch,
  });
  factory TakeViewPositionEvent.fromJson(Json j) => TakeViewPositionEvent(
        seconds: (j['seconds'] as num).toDouble(),
        playing: j['playing'] as bool,
        rate: (j['rate'] as num).toDouble(),
        at: (j['at'] as num).toDouble(),
        epoch: j['epoch'] as int,
      );
  /// Tiempo de la toma que se oye en `at` (s).
  final double seconds;
  final bool playing;
  /// 1 si el reloj avanza, 0 si está quieto.
  final double rate;
  /// Reloj de host del núcleo, s.
  final double at;
  final int epoch;
  Json toJson() => {
        'seconds': seconds,
        'playing': playing,
        'rate': rate,
        'at': at,
        'epoch': epoch,
      };
}

/// Estado de conversión de vídeo de una toma (`video` de `takeview.video`).
/// `code` vale `video-converting` o `video-failed`; se deja como texto (no hay enum en el contrato).
@immutable
class TakeViewVideoStatus {
  const TakeViewVideoStatus({
    required this.code,
    required this.takeId,
    required this.jobId,
    required this.message,
    this.progress,
  });
  factory TakeViewVideoStatus.fromJson(Json j) => TakeViewVideoStatus(
        code: j['code'] as String,
        takeId: j['takeId'] as String,
        jobId: j['jobId'] as String,
        message: j['message'] as String,
        progress: (j['progress'] as num?)?.toDouble(),
      );
  final String code;
  final String takeId;
  /// Clave del trabajo en `jobs.progress`.
  final String jobId;
  final String message;
  /// Fracción 0…1; ausente en `video-failed`.
  final double? progress;
  Json toJson() => {
        'code': code,
        'takeId': takeId,
        'jobId': jobId,
        if (progress != null) 'progress': progress,
        'message': message,
      };
}

/// Payload de `takeview.video`: cambio del vídeo de la toma abierta. `video` ausente = vídeo listo.
@immutable
class TakeViewVideoEvent {
  const TakeViewVideoEvent({required this.takeId, this.video});
  factory TakeViewVideoEvent.fromJson(Json j) => TakeViewVideoEvent(
        takeId: j['takeId'] as String,
        video: j['video'] == null ? null : TakeViewVideoStatus.fromJson(j['video'] as Json),
      );
  final String takeId;
  final TakeViewVideoStatus? video;
  Json toJson() => {
        'takeId': takeId,
        if (video != null) 'video': video!.toJson(),
      };
}
