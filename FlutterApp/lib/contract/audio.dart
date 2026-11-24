import 'package:flutter/foundation.dart' show immutable;

import '../core/core_client.dart' show Json;
import 'audio_settings.dart';
import 'patch.dart';

export 'audio_calibration.dart';
export 'audio_settings.dart';
export 'patch.dart';

List<T> _list<T>(Object? raw, T Function(Json) fromJson) =>
    [for (final e in raw as List) fromJson(e as Json)];

List<double> _doubles(Object? raw) =>
    [for (final e in raw as List) (e as num).toDouble()];

@immutable
class AudioDeviceItem {
  const AudioDeviceItem({
    required this.uid,
    required this.name,
    required this.channels,
    required this.label,
    required this.connected,
    this.rate,
  });

  factory AudioDeviceItem.fromJson(Json j) => AudioDeviceItem(
        uid: j['uid'] as String,
        name: j['name'] as String,
        channels: j['channels'] as int,
        label: j['label'] as String,
        connected: j['connected'] as bool,
        rate: (j['rate'] as num?)?.toDouble(),
      );

  final String uid;
  final String name;
  final int channels;
  final String label;
  final bool connected;
  final double? rate;

  Json toJson() => {
        'uid': uid,
        'name': name,
        'channels': channels,
        'label': label,
        'connected': connected,
        'rate': rate,
      }..removeWhere((_, v) => v == null);
}

/// `AudioDevicesResult`: respuesta de `audio.devices` y evento `audio.devicesChanged`.
@immutable
class AudioDevices {
  const AudioDevices({
    required this.inputs,
    required this.outputs,
    this.systemDefault,
  });

  factory AudioDevices.fromJson(Json j) => AudioDevices(
        inputs: _list(j['inputs'], AudioDeviceItem.fromJson),
        outputs: _list(j['outputs'], AudioDeviceItem.fromJson),
        systemDefault: j['systemDefault'] == null
            ? null
            : AudioDeviceItem.fromJson(j['systemDefault'] as Json),
      );

  final List<AudioDeviceItem> inputs;
  final List<AudioDeviceItem> outputs;
  final AudioDeviceItem? systemDefault;

  Json toJson() => {
        'inputs': [for (final d in inputs) d.toJson()],
        'outputs': [for (final d in outputs) d.toJson()],
        'systemDefault': systemDefault?.toJson(),
      };
}

/// `AudioStateResult`: respuesta de `audio.state`, de `audio.setMeters` y evento `audio.state`.
@immutable
class AudioState {
  const AudioState({
    required this.sessionOpen,
    required this.hosting,
    required this.metersVisible,
    required this.recording,
    required this.calibrationRunning,
    required this.calibrationValid,
    required this.recordingNotices,
    required this.workingSampleRate,
    this.sessionError,
    this.interruptionNote,
    this.hostError,
    this.calibrateBlock,
    this.mismatchedRate,
  });

  factory AudioState.fromJson(Json j) => AudioState(
        sessionOpen: j['sessionOpen'] as bool,
        sessionError: j['sessionError'] as String?,
        interruptionNote: j['interruptionNote'] as String?,
        hostError: j['hostError'] as String?,
        hosting: j['hosting'] as bool,
        metersVisible: j['metersVisible'] as bool,
        recording: j['recording'] as bool,
        calibrationRunning: j['calibrationRunning'] as bool,
        calibrationValid: j['calibrationValid'] as bool,
        calibrateBlock: j['calibrateBlock'] as String?,
        recordingNotices: (j['recordingNotices'] as List).cast<String>(),
        mismatchedRate: (j['mismatchedRate'] as num?)?.toDouble(),
        workingSampleRate: (j['workingSampleRate'] as num).toDouble(),
      );

  final bool sessionOpen;
  final String? sessionError;
  final String? interruptionNote;
  final String? hostError;
  final bool hosting;
  final bool metersVisible;
  final bool recording;
  final bool calibrationRunning;
  final bool calibrationValid;
  final String? calibrateBlock;
  final List<String> recordingNotices;
  final double? mismatchedRate;
  final double workingSampleRate;

  Json toJson() => {
        'sessionOpen': sessionOpen,
        'sessionError': sessionError,
        'interruptionNote': interruptionNote,
        'hostError': hostError,
        'hosting': hosting,
        'metersVisible': metersVisible,
        'recording': recording,
        'calibrationRunning': calibrationRunning,
        'calibrationValid': calibrationValid,
        'calibrateBlock': calibrateBlock,
        'recordingNotices': recordingNotices,
        'mismatchedRate': mismatchedRate,
        'workingSampleRate': workingSampleRate,
      }..removeWhere((_, v) => v == null);
}

/// Evento `audio.levels`. `levels` vacío = sin sesión.
@immutable
class AudioLevels {
  const AudioLevels({
    required this.levels,
    required this.rmsDB,
    required this.peakDB,
  });

  factory AudioLevels.fromJson(Json j) => AudioLevels(
        levels: _doubles(j['levels']),
        rmsDB: _doubles(j['rmsDB']),
        peakDB: _doubles(j['peakDB']),
      );

  final List<double> levels;
  final List<double> rmsDB;
  final List<double> peakDB;

  Json toJson() => {'levels': levels, 'rmsDB': rmsDB, 'peakDB': peakDB};
}

/// Params de `audio.setMeters`.
@immutable
class AudioSetMetersParams {
  const AudioSetMetersParams({required this.visible});

  factory AudioSetMetersParams.fromJson(Json j) =>
      AudioSetMetersParams(visible: j['visible'] as bool);

  final bool visible;

  Json toJson() => {'visible': visible};
}

/// Params de `audio.setSettings`. Cada `Patch` ausente = no tocar; `null` = sistema/ninguna/sin asignar.
@immutable
class AudioSetSettingsParams {
  const AudioSetSettingsParams({
    this.outputDeviceUID = const Patch.absent(),
    this.inputDeviceUID = const Patch.absent(),
    this.guitarIn = const Patch.absent(),
    this.backingOut,
    this.workingSampleRate,
  });

  factory AudioSetSettingsParams.fromJson(Json j) => AudioSetSettingsParams(
        outputDeviceUID: Patch.fromMap(j, 'outputDeviceUID', (r) => r as String),
        inputDeviceUID: Patch.fromMap(j, 'inputDeviceUID', (r) => r as String),
        guitarIn: Patch.fromMap(j, 'guitarIn', (r) => (r as List).cast<int>()),
        backingOut: j['backingOut'] == null
            ? null
            : AudioBacking.fromJson(j['backingOut'] as Json),
        workingSampleRate: j['workingSampleRate'] as int?,
      );

  final Patch<String> outputDeviceUID;
  final Patch<String> inputDeviceUID;
  final Patch<List<int>> guitarIn;
  final AudioBacking? backingOut;
  final int? workingSampleRate;

  Json toJson() {
    final j = <String, Object?>{};
    outputDeviceUID.writeTo(j, 'outputDeviceUID');
    inputDeviceUID.writeTo(j, 'inputDeviceUID');
    guitarIn.writeTo(j, 'guitarIn');
    final b = backingOut;
    if (b != null) j['backingOut'] = b.toJson();
    final r = workingSampleRate;
    if (r != null) j['workingSampleRate'] = r;
    return j;
  }
}
