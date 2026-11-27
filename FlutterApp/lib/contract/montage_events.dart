import 'package:flutter/foundation.dart';

import '../core/core_client.dart' show Json;
import 'record_state.dart' show enumOf;

// Eventos `montage.export`, `montage.framing` y `montage.position`.
// `montage.state` es un MontageSnapshot (ver montage.dart).

/// Fase de la exportación (`MontageExportEvent.phase`, `MontageSnapshot.exportStatus`).
enum MontageExportPhase { idle, running, done, failed, cancelled, unknown }

/// Estado del análisis de encuadre por toma (`MontageFramingEvent.status`, `MontageFramingInfo.status`).
enum MontageFramingStatus { pending, analyzing, ready, failed, unknown }

/// `MontageExportResultInfo`: solo en `done`. `path` es absoluta.
@immutable
class MontageExportResultInfo {
  const MontageExportResultInfo({
    required this.path,
    required this.finalTruePeakDB,
    required this.normalized,
    required this.limitedByPeak,
    required this.limiterEnabled,
    required this.limiterApplied,
    required this.limiterMaxReductionDB,
    required this.limiterOutOfTolerance,
    required this.clippedFiles,
    required this.codec,
    this.tracksDirectory,
    this.finalLUFS,
  });
  factory MontageExportResultInfo.fromJson(Json j) => MontageExportResultInfo(
        path: j['path'] as String,
        tracksDirectory: j['tracksDirectory'] as String?,
        finalLUFS: (j['finalLUFS'] as num?)?.toDouble(),
        finalTruePeakDB: (j['finalTruePeakDB'] as num).toDouble(),
        normalized: j['normalized'] as bool,
        limitedByPeak: j['limitedByPeak'] as bool,
        limiterEnabled: j['limiterEnabled'] as bool,
        limiterApplied: j['limiterApplied'] as bool,
        limiterMaxReductionDB: (j['limiterMaxReductionDB'] as num).toDouble(),
        limiterOutOfTolerance: j['limiterOutOfTolerance'] as bool,
        clippedFiles: [for (final f in j['clippedFiles'] as List) f as String],
        codec: j['codec'] as String,
      );
  final String path;
  final String? tracksDirectory;
  final double? finalLUFS;
  final double finalTruePeakDB;
  final bool normalized;
  final bool limitedByPeak;
  final bool limiterEnabled;
  final bool limiterApplied;
  final double limiterMaxReductionDB;
  final bool limiterOutOfTolerance;
  final List<String> clippedFiles;
  final String codec;
  Json toJson() => {
        'path': path,
        if (tracksDirectory != null) 'tracksDirectory': tracksDirectory,
        if (finalLUFS != null) 'finalLUFS': finalLUFS,
        'finalTruePeakDB': finalTruePeakDB,
        'normalized': normalized,
        'limitedByPeak': limitedByPeak,
        'limiterEnabled': limiterEnabled,
        'limiterApplied': limiterApplied,
        'limiterMaxReductionDB': limiterMaxReductionDB,
        'limiterOutOfTolerance': limiterOutOfTolerance,
        'clippedFiles': clippedFiles,
        'codec': codec,
      };
}

/// Payload de `montage.export` y `MontageSnapshot.exportStatus`.
@immutable
class MontageExportEvent {
  const MontageExportEvent({required this.phase, required this.progress, this.stage, this.message, this.result});
  factory MontageExportEvent.fromJson(Json j) => MontageExportEvent(
        phase: enumOf(MontageExportPhase.values, MontageExportPhase.unknown, j['phase']),
        progress: (j['progress'] as num).toDouble(),
        stage: j['stage'] as String?,
        message: j['message'] as String?,
        result: j['result'] == null ? null : MontageExportResultInfo.fromJson(j['result'] as Json),
      );
  final MontageExportPhase phase;
  /// Fracción 0...1; la mezcla ocupa el primer 15 %.
  final double progress;
  /// Solo en `running`: texto libre del núcleo («Mezclando el audio», «Codificando el vídeo»).
  final String? stage;
  /// Solo en `failed`.
  final String? message;
  /// Solo en `done`.
  final MontageExportResultInfo? result;
  Json toJson() => {
        'phase': phase.name,
        'progress': progress,
        if (stage != null) 'stage': stage,
        if (message != null) 'message': message,
        if (result != null) 'result': result!.toJson(),
      };
}

/// Payload de `montage.framing`.
@immutable
class MontageFramingEvent {
  const MontageFramingEvent({
    required this.takeId,
    required this.status,
    required this.progress,
    this.samples,
    this.detected,
    this.error,
  });
  factory MontageFramingEvent.fromJson(Json j) => MontageFramingEvent(
        takeId: j['takeId'] as String,
        status: enumOf(MontageFramingStatus.values, MontageFramingStatus.unknown, j['status']),
        progress: (j['progress'] as num).toDouble(),
        samples: j['samples'] as int?,
        detected: j['detected'] as int?,
        error: j['error'] as String?,
      );
  final String takeId;
  final MontageFramingStatus status;
  final double progress;
  final int? samples;
  final int? detected;
  final String? error;
  Json toJson() => {
        'takeId': takeId,
        'status': status.name,
        'progress': progress,
        if (samples != null) 'samples': samples,
        if (detected != null) 'detected': detected,
        if (error != null) 'error': error,
      };
}

/// Payload de `montage.position`. Tema = `seconds`; vídeo = `videoSeconds`.
@immutable
class MontagePositionEvent {
  const MontagePositionEvent({required this.seconds, required this.videoSeconds, required this.playing});
  factory MontagePositionEvent.fromJson(Json j) => MontagePositionEvent(
        seconds: (j['seconds'] as num).toDouble(),
        videoSeconds: (j['videoSeconds'] as num).toDouble(),
        playing: j['playing'] as bool,
      );
  final double seconds;
  final double videoSeconds;
  final bool playing;
  Json toJson() => {'seconds': seconds, 'videoSeconds': videoSeconds, 'playing': playing};
}
