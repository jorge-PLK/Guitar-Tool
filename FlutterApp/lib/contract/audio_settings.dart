import 'package:flutter/foundation.dart' show immutable;

import '../core/core_client.dart' show Json;

List<T> _list<T>(Object? raw, T Function(Json) fromJson) =>
    [for (final e in raw as List) fromJson(e as Json)];

/// `{left, right, label?}`: salidas del backing o pareja elegible.
@immutable
class AudioBacking {
  const AudioBacking({required this.left, required this.right, this.label});

  factory AudioBacking.fromJson(Json j) => AudioBacking(
        left: j['left'] as int,
        right: j['right'] as int,
        label: j['label'] as String?,
      );

  final int left;
  final int right;
  final String? label;

  Json toJson() => {'left': left, 'right': right, 'label': label}
    ..removeWhere((_, v) => v == null);
}

@immutable
class AudioSampleRate {
  const AudioSampleRate({required this.rate, required this.label});

  factory AudioSampleRate.fromJson(Json j) => AudioSampleRate(
        rate: (j['rate'] as num).toDouble(),
        label: j['label'] as String,
      );

  final double rate;
  final String label;

  Json toJson() => {'rate': rate, 'label': label};
}

@immutable
class AudioGuitarChoice {
  const AudioGuitarChoice({required this.label, this.channels});

  factory AudioGuitarChoice.fromJson(Json j) => AudioGuitarChoice(
        label: j['label'] as String,
        channels: (j['channels'] as List?)?.cast<int>(),
      );

  final String label;
  final List<int>? channels;

  Json toJson() => {'label': label, 'channels': channels}
    ..removeWhere((_, v) => v == null);
}

@immutable
class AudioRateMismatch {
  const AudioRateMismatch({
    required this.deviceRate,
    required this.workingRate,
    required this.message,
    required this.hint,
    required this.canUseDeviceRate,
    required this.useLabel,
  });

  factory AudioRateMismatch.fromJson(Json j) => AudioRateMismatch(
        deviceRate: (j['deviceRate'] as num).toDouble(),
        workingRate: (j['workingRate'] as num).toDouble(),
        message: j['message'] as String,
        hint: j['hint'] as String,
        canUseDeviceRate: j['canUseDeviceRate'] as bool,
        useLabel: j['useLabel'] as String,
      );

  final double deviceRate;
  final double workingRate;
  final String message;
  final String hint;
  final bool canUseDeviceRate;
  final String useLabel;

  Json toJson() => {
        'deviceRate': deviceRate,
        'workingRate': workingRate,
        'message': message,
        'hint': hint,
        'canUseDeviceRate': canUseDeviceRate,
        'useLabel': useLabel,
      };
}

/// Bloque `calibration` de `audio.settings`. `date` se guarda tal cual llega (ISO 8601).
@immutable
class AudioCalibrationSummary {
  const AudioCalibrationSummary({
    required this.calibrated,
    required this.label,
    this.latencyMS,
    this.date,
  });

  factory AudioCalibrationSummary.fromJson(Json j) => AudioCalibrationSummary(
        calibrated: j['calibrated'] as bool,
        label: j['label'] as String,
        latencyMS: (j['latencyMS'] as num?)?.toDouble(),
        date: j['date'] as String?,
      );

  final bool calibrated;
  final String label;
  final double? latencyMS;
  final String? date;

  Json toJson() => {
        'calibrated': calibrated,
        'label': label,
        'latencyMS': latencyMS,
        'date': date,
      }..removeWhere((_, v) => v == null);
}

/// `AudioSettingsResult`: respuesta de `audio.settings` y de `audio.setSettings`.
@immutable
class AudioSettings {
  const AudioSettings({
    required this.backingOut,
    required this.workingSampleRate,
    required this.allowedSampleRates,
    required this.backingChoices,
    required this.guitarChoices,
    required this.calibration,
    required this.calibrateInstructions,
    this.outputDeviceUID,
    this.inputDeviceUID,
    this.guitarIn,
    this.rateMismatch,
    this.calibrateBlock,
  });

  factory AudioSettings.fromJson(Json j) => AudioSettings(
        outputDeviceUID: j['outputDeviceUID'] as String?,
        inputDeviceUID: j['inputDeviceUID'] as String?,
        backingOut: AudioBacking.fromJson(j['backingOut'] as Json),
        guitarIn: (j['guitarIn'] as List?)?.cast<int>(),
        workingSampleRate: (j['workingSampleRate'] as num).toDouble(),
        allowedSampleRates: _list(j['allowedSampleRates'], AudioSampleRate.fromJson),
        backingChoices: _list(j['backingChoices'], AudioBacking.fromJson),
        guitarChoices: _list(j['guitarChoices'], AudioGuitarChoice.fromJson),
        rateMismatch: j['rateMismatch'] == null
            ? null
            : AudioRateMismatch.fromJson(j['rateMismatch'] as Json),
        calibration: AudioCalibrationSummary.fromJson(j['calibration'] as Json),
        calibrateBlock: j['calibrateBlock'] as String?,
        calibrateInstructions: (j['calibrateInstructions'] as List).cast<String>(),
      );

  final String? outputDeviceUID;
  final String? inputDeviceUID;
  final AudioBacking backingOut;
  final List<int>? guitarIn;
  final double workingSampleRate;
  final List<AudioSampleRate> allowedSampleRates;
  final List<AudioBacking> backingChoices;
  final List<AudioGuitarChoice> guitarChoices;
  final AudioRateMismatch? rateMismatch;
  final AudioCalibrationSummary calibration;
  final String? calibrateBlock;
  final List<String> calibrateInstructions;

  Json toJson() => {
        'outputDeviceUID': outputDeviceUID,
        'inputDeviceUID': inputDeviceUID,
        'backingOut': backingOut.toJson(),
        'guitarIn': guitarIn,
        'workingSampleRate': workingSampleRate,
        'allowedSampleRates': [for (final r in allowedSampleRates) r.toJson()],
        'backingChoices': [for (final b in backingChoices) b.toJson()],
        'guitarChoices': [for (final g in guitarChoices) g.toJson()],
        'rateMismatch': rateMismatch?.toJson(),
        'calibration': calibration.toJson(),
        'calibrateBlock': calibrateBlock,
        'calibrateInstructions': calibrateInstructions,
      }..removeWhere((_, v) => v == null);
}
