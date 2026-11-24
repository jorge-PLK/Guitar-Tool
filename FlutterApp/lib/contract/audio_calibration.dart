import 'package:flutter/foundation.dart' show immutable;

import '../core/core_client.dart' show Json;

/// `phase` de `AudioCalibrationState`. Valores no previstos caen en `unknown`.
enum CalibrationPhase {
  idle,
  running,
  finished,
  unknown;

  static CalibrationPhase parse(Object? raw) =>
      values.asNameMap()[raw] ?? unknown;
}

/// `outcome` de `AudioCalibrationState`. Valores no previstos caen en `unknown`.
enum CalibrationOutcome {
  success,
  failure,
  error,
  unknown;

  static CalibrationOutcome parse(Object? raw) =>
      values.asNameMap()[raw] ?? unknown;
}

/// `reason` de `failure`. Valores no previstos caen en `unknown`.
enum CalibrationFailureReason {
  noSignal,
  saturated,
  unstable,
  unknown;

  static CalibrationFailureReason parse(Object? raw) =>
      values.asNameMap()[raw] ?? unknown;
}

@immutable
class AudioCalibrationRow {
  const AudioCalibrationRow({required this.label, required this.value});

  factory AudioCalibrationRow.fromJson(Json j) => AudioCalibrationRow(
        label: j['label'] as String,
        value: j['value'] as String,
      );

  final String label;
  final String value;

  Json toJson() => {'label': label, 'value': value};
}

@immutable
class AudioCalibrationSuccess {
  const AudioCalibrationSuccess({
    required this.latencyMS,
    required this.latencySamples,
    required this.spreadMS,
    required this.spreadSamples,
    required this.correctedTakes,
    required this.rows,
    this.rigDelayMS,
  });

  factory AudioCalibrationSuccess.fromJson(Json j) => AudioCalibrationSuccess(
        latencyMS: (j['latencyMS'] as num).toDouble(),
        latencySamples: (j['latencySamples'] as num).toDouble(),
        spreadMS: (j['spreadMS'] as num).toDouble(),
        spreadSamples: (j['spreadSamples'] as num).toDouble(),
        correctedTakes: j['correctedTakes'] as int,
        rows: [
          for (final r in j['rows'] as List)
            AudioCalibrationRow.fromJson(r as Json),
        ],
        rigDelayMS: (j['rigDelayMS'] as num?)?.toDouble(),
      );

  final double latencyMS;
  final double latencySamples;
  final double spreadMS;
  final double spreadSamples;
  final int correctedTakes;
  final List<AudioCalibrationRow> rows;
  final double? rigDelayMS;

  Json toJson() => {
        'latencyMS': latencyMS,
        'latencySamples': latencySamples,
        'spreadMS': spreadMS,
        'spreadSamples': spreadSamples,
        'correctedTakes': correctedTakes,
        'rows': [for (final r in rows) r.toJson()],
        'rigDelayMS': rigDelayMS,
      }..removeWhere((_, v) => v == null);
}

@immutable
class AudioCalibrationFailure {
  const AudioCalibrationFailure({
    required this.reason,
    required this.spreadMS,
    required this.title,
    required this.hint,
  });

  factory AudioCalibrationFailure.fromJson(Json j) => AudioCalibrationFailure(
        reason: CalibrationFailureReason.parse(j['reason']),
        spreadMS: (j['spreadMS'] as num).toDouble(),
        title: j['title'] as String,
        hint: j['hint'] as String,
      );

  final CalibrationFailureReason reason;
  final double spreadMS;
  final String title;
  final String hint;

  Json toJson() => {
        'reason': reason.name,
        'spreadMS': spreadMS,
        'title': title,
        'hint': hint,
      };
}

/// `AudioCalibrationState`: respuesta de `audio.calibrate`, cancel/dismiss y evento `audio.calibration`.
@immutable
class AudioCalibrationState {
  const AudioCalibrationState({
    required this.phase,
    this.progress,
    this.outcome,
    this.success,
    this.failure,
    this.error,
  });

  factory AudioCalibrationState.fromJson(Json j) => AudioCalibrationState(
        phase: CalibrationPhase.parse(j['phase']),
        progress: (j['progress'] as num?)?.toDouble(),
        outcome: j['outcome'] == null
            ? null
            : CalibrationOutcome.parse(j['outcome']),
        success: j['success'] == null
            ? null
            : AudioCalibrationSuccess.fromJson(j['success'] as Json),
        failure: j['failure'] == null
            ? null
            : AudioCalibrationFailure.fromJson(j['failure'] as Json),
        error: j['error'] as String?,
      );

  final CalibrationPhase phase;
  final double? progress;
  final CalibrationOutcome? outcome;
  final AudioCalibrationSuccess? success;
  final AudioCalibrationFailure? failure;
  final String? error;

  Json toJson() => {
        'phase': phase.name,
        'progress': progress,
        'outcome': outcome?.name,
        'success': success?.toJson(),
        'failure': failure?.toJson(),
        'error': error,
      }..removeWhere((_, v) => v == null);
}
